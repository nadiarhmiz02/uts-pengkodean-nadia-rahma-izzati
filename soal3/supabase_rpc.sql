-- ============================================
-- SOAL 3.2: Audit Trail & Immutability
-- Sistem Voucher Kas Keluar
-- ============================================

-- ============================================
-- STEP 1: Tabel dengan field audit
-- ============================================
CREATE TABLE journal_headers (
  header_id SERIAL PRIMARY KEY,
  nomor_voucher VARCHAR(30) NOT NULL UNIQUE,
  tanggal_transaksi DATE NOT NULL,
  deskripsi TEXT,
  status_posting VARCHAR(10) NOT NULL DEFAULT 'DRAFT'
    CHECK (status_posting IN ('DRAFT', 'POSTED', 'REVERSED')),
  
  -- Field audit trail
  created_by UUID,                 -- User ID pembuat
  created_at TIMESTAMPTZ DEFAULT NOW(),
  posted_by UUID,                  -- User ID yang posting
  posted_at TIMESTAMPTZ,
  hash_checksum VARCHAR(64),       -- SHA-256 hash untuk integritas
  
  -- Field untuk reversing entry
  reversed_by INTEGER REFERENCES journal_headers(header_id),
  reversal_reason TEXT
);

CREATE TABLE journal_lines (
  line_id SERIAL PRIMARY KEY,
  header_id INTEGER NOT NULL REFERENCES journal_headers(header_id),
  account_id INTEGER NOT NULL,
  debit NUMERIC(15,2) NOT NULL DEFAULT 0 CHECK (debit >= 0),
  credit NUMERIC(15,2) NOT NULL DEFAULT 0 CHECK (credit >= 0),
  CONSTRAINT chk_not_both_zero CHECK (debit > 0 OR credit > 0)
);

-- ============================================
-- STEP 2: Function untuk generate hash_checksum
-- ============================================
CREATE OR REPLACE FUNCTION generate_journal_hash(
  p_header_id INTEGER
)
RETURNS VARCHAR(64) AS $$
DECLARE
  v_hash VARCHAR(64);
  v_content TEXT;
BEGIN
  -- Gabungkan semua data jurnal jadi 1 string
  SELECT 
    COALESCE(string_agg(
      h.nomor_voucher || '|' || 
      h.tanggal_transaksi || '|' || 
      h.deskripsi || '|' || 
      l.account_id || '|' || 
      l.debit || '|' || 
      l.credit,
      '||'
    ), '')
  INTO v_content
  FROM journal_headers h
  JOIN journal_lines l ON l.header_id = h.header_id
  WHERE h.header_id = p_header_id
  GROUP BY h.header_id;
  
  -- Generate SHA-256 hash
  v_hash := encode(digest(v_content, 'sha256'), 'hex');
  RETURN v_hash;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- STEP 3: Trigger cegah UPDATE/DELETE untuk POSTED
-- ============================================
CREATE OR REPLACE FUNCTION prevent_posted_modification()
RETURNS TRIGGER AS $$
BEGIN
  -- Cek status: kalau POSTED, cegah UPDATE/DELETE
  IF TG_OP = 'UPDATE' THEN
    IF OLD.status_posting = 'POSTED' THEN
      RAISE EXCEPTION 'Transaksi POSTED tidak dapat diubah. Gunakan reversing entry (storno).';
    END IF;
  ELSIF TG_OP = 'DELETE' THEN
    IF OLD.status_posting = 'POSTED' THEN
      RAISE EXCEPTION 'Transaksi POSTED tidak dapat dihapus. Gunakan reversing entry (storno).';
    END IF;
  END IF;
  
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Daftarkan trigger ke journal_headers
CREATE TRIGGER trg_prevent_posted_modification
BEFORE UPDATE OR DELETE ON journal_headers
FOR EACH ROW
EXECUTE FUNCTION prevent_posted_modification();

-- Daftarkan trigger serupa ke journal_lines
CREATE OR REPLACE FUNCTION prevent_posted_line_modification()
RETURNS TRIGGER AS $$
DECLARE
  v_status VARCHAR(10);
BEGIN
  -- Ambil status header
  SELECT status_posting INTO v_status
  FROM journal_headers
  WHERE header_id = COALESCE(NEW.header_id, OLD.header_id);
  
  IF v_status = 'POSTED' THEN
    RAISE EXCEPTION 'Baris jurnal dari transaksi POSTED tidak dapat diubah/dihapus.';
  END IF;
  
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_posted_line_modification
BEFORE UPDATE OR DELETE ON journal_lines
FOR EACH ROW
EXECUTE FUNCTION prevent_posted_line_modification();

-- ============================================
-- STEP 4: Function untuk POSTING jurnal (set hash)
-- ============================================
CREATE OR REPLACE FUNCTION post_journal(
  p_header_id INTEGER,
  p_user_id UUID
)
RETURNS VOID AS $$
DECLARE
  v_total_debit NUMERIC(15,2);
  v_total_credit NUMERIC(15,2);
  v_hash VARCHAR(64);
BEGIN
  -- Validasi: Total Debit = Total Kredit
  SELECT 
    COALESCE(SUM(debit), 0),
    COALESCE(SUM(credit), 0)
  INTO v_total_debit, v_total_credit
  FROM journal_lines
  WHERE header_id = p_header_id;
  
  IF v_total_debit != v_total_credit THEN
    RAISE EXCEPTION 'Zero-discrepancy violation: Total Debit (%) ≠ Total Kredit (%)',
      v_total_debit, v_total_credit;
  END IF;
  
  IF v_total_debit = 0 THEN
    RAISE EXCEPTION 'Jurnal kosong tidak dapat diposting.';
  END IF;
  
  -- Generate hash
  v_hash := generate_journal_hash(p_header_id);
  
  -- Update header jadi POSTED
  UPDATE journal_headers
  SET status_posting = 'POSTED',
      posted_by = p_user_id,
      posted_at = NOW(),
      hash_checksum = v_hash
  WHERE header_id = p_header_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- STEP 5: Function untuk REVERSING ENTRY (storno)
-- ============================================
CREATE OR REPLACE FUNCTION reverse_journal(
  p_original_header_id INTEGER,
  p_user_id UUID,
  p_reason TEXT
)
RETURNS INTEGER AS $$
DECLARE
  v_new_header_id INTEGER;
  v_original RECORD;
  v_line RECORD;
BEGIN
  -- Validasi: header asli harus POSTED
  SELECT * INTO v_original
  FROM journal_headers
  WHERE header_id = p_original_header_id;
  
  IF v_original.status_posting != 'POSTED' THEN
    RAISE EXCEPTION 'Hanya transaksi POSTED yang dapat di-reverse.';
  END IF;
  
  -- Bikin header baru untuk reversing entry
  INSERT INTO journal_headers (
    nomor_voucher, 
    tanggal_transaksi, 
    deskripsi, 
    status_posting, 
    created_by,
    reversal_reason
  ) VALUES (
    'REV-' || v_original.nomor_voucher,
    CURRENT_DATE,
    'Reversing entry untuk ' || v_original.nomor_voucher || ': ' || p_reason,
    'POSTED',
    p_user_id,
    p_reason
  )
  RETURNING header_id INTO v_new_header_id;
  
  -- Copy lines dengan DEBIT <-> KREDIT ditukar
  FOR v_line IN 
    SELECT * FROM journal_lines WHERE header_id = p_original_header_id
  LOOP
    INSERT INTO journal_lines (header_id, account_id, debit, credit)
    VALUES (
      v_new_header_id, 
      v_line.account_id, 
      v_line.credit,  -- debit di-swap jadi credit
      v_line.debit    -- credit di-swap jadi debit
    );
  END LOOP;
  
  -- Tandai header asli sebagai REVERSED
  UPDATE journal_headers
  SET status_posting = 'REVERSED',
      reversed_by = v_new_header_id
  WHERE header_id = p_original_header_id;
  
  RETURN v_new_header_id;
END;
$$ LANGUAGE plpgsql;