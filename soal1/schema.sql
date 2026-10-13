-- ============================================
-- SOAL 1.2: DDL PostgreSQL
-- Sistem: General Ledger dengan Header-Line Pattern
-- ============================================

-- Tabel 1: Chart of Accounts
CREATE TABLE chart_of_accounts (
  account_id SERIAL PRIMARY KEY,
  kode_akun VARCHAR(10) NOT NULL UNIQUE,
  nama_akun VARCHAR(100) NOT NULL,
  tipe_saldo_normal VARCHAR(10) NOT NULL 
    CHECK (tipe_saldo_normal IN ('DEBIT', 'KREDIT')),
  klasifikasi_laporan VARCHAR(20) NOT NULL
    CHECK (klasifikasi_laporan IN ('ASET', 'LIABILITAS', 'EKUITAS', 'PENDAPATAN', 'BEBAN'))
);

-- Tabel 2: Journal Headers
CREATE TABLE journal_headers (
  header_id SERIAL PRIMARY KEY,
  tanggal_transaksi DATE NOT NULL,
  nomor_referensi VARCHAR(30) NOT NULL UNIQUE,
  deskripsi TEXT,
  status_posting VARCHAR(10) NOT NULL DEFAULT 'DRAFT'
    CHECK (status_posting IN ('DRAFT', 'POSTED'))
);

-- Tabel 3: Journal Lines
CREATE TABLE journal_lines (
  line_id SERIAL PRIMARY KEY,
  header_id INT NOT NULL,
  account_id INT NOT NULL,
  debit NUMERIC(15,2) NOT NULL DEFAULT 0 CHECK (debit >= 0),
  credit NUMERIC(15,2) NOT NULL DEFAULT 0 CHECK (credit >= 0),
  
  -- Foreign Key dengan ON DELETE RESTRICT
  CONSTRAINT fk_header FOREIGN KEY (header_id) 
    REFERENCES journal_headers(header_id) ON DELETE RESTRICT,
  CONSTRAINT fk_account FOREIGN KEY (account_id) 
    REFERENCES chart_of_accounts(account_id) ON DELETE RESTRICT,
  
  -- CHECK: tidak boleh debit & credit dua-duanya nol
  CONSTRAINT chk_not_both_zero CHECK (debit > 0 OR credit > 0)
);

-- ============================================
-- SEED DATA (Contoh data awal)
-- ============================================
INSERT INTO chart_of_accounts (kode_akun, nama_akun, tipe_saldo_normal, klasifikasi_laporan) VALUES
('1-1000', 'Kas', 'DEBIT', 'ASET'),
('1-1100', 'Piutang Usaha', 'DEBIT', 'ASET'),
('1-1200', 'Peralatan', 'DEBIT', 'ASET'),
('2-1000', 'Utang Usaha', 'KREDIT', 'LIABILITAS'),
('3-1000', 'Modal', 'KREDIT', 'EKUITAS'),
('4-1000', 'Pendapatan', 'KREDIT', 'PENDAPATAN'),
('5-1000', 'Beban Gaji', 'DEBIT', 'BEBAN');

-- Contoh transaksi jurnal
INSERT INTO journal_headers (tanggal_transaksi, nomor_referensi, deskripsi, status_posting) 
VALUES 
('2026-10-12', 'JV/2026/10/001', 'Beli komputer tunai', 'POSTED'),
('2026-10-12', 'JV/2026/10/002', 'Bayar gaji karyawan', 'POSTED');

INSERT INTO journal_lines (header_id, account_id, debit, credit) VALUES
(1, 3, 10000000, 0),      -- Debit Peralatan
(1, 1, 0, 10000000),      -- Kredit Kas
(2, 7, 5000000, 0),       -- Debit Beban Gaji
(2, 1, 0, 5000000);       -- Kredit Kas