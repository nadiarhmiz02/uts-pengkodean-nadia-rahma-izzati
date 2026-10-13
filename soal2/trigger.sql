-- ============================================
-- SOAL 2.1: Trigger Otomatisasi Mutasi Stok
-- PT Diponegoro Logistik Utama
-- ============================================

-- ============================================
-- STEP 1: Bikin tabel (sesuai soal)
-- ============================================
CREATE TABLE inventory_items (
  item_id VARCHAR(10) PRIMARY KEY,
  item_name VARCHAR(100),
  stock_qty INT NOT NULL DEFAULT 0,
  unit_cost NUMERIC(15, 2) NOT NULL
);

CREATE TABLE inventory_transactions (
  trx_id SERIAL PRIMARY KEY,
  item_id VARCHAR(10) REFERENCES inventory_items(item_id),
  trx_type VARCHAR(10) CHECK (trx_type IN ('PURCHASE', 'SALE', 'ADJUSTMENT')),
  qty INT NOT NULL,
  trx_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- STEP 2: Seed data contoh
-- ============================================
INSERT INTO inventory_items (item_id, item_name, stock_qty, unit_cost) VALUES
('ITEM001', 'Kertas A4', 100, 50000),
('ITEM002', 'Pulpen', 50, 5000),
('ITEM003', 'Tinta Printer', 10, 150000);

-- ============================================
-- STEP 3: Trigger Function
-- ============================================
CREATE OR REPLACE FUNCTION trg_update_stock_and_journal()
RETURNS TRIGGER AS $$
BEGIN
  -- ============================================
  -- KASUS 1: PURCHASE (Pembelian) → stok nambah
  -- ============================================
  IF NEW.trx_type = 'PURCHASE' THEN
    UPDATE inventory_items
    SET stock_qty = stock_qty + NEW.qty
    WHERE item_id = NEW.item_id;
  
  -- ============================================
  -- KASUS 2: SALE (Penjualan) → stok berkurang
  -- ============================================
  ELSIF NEW.trx_type = 'SALE' THEN
    -- Cek apakah stok cukup
    IF (SELECT stock_qty FROM inventory_items WHERE item_id = NEW.item_id) < NEW.qty THEN
      RAISE EXCEPTION 'Anti-negative inventory: stok tidak cukup untuk item % (stok tersedia: %, diminta: %)',
        NEW.item_id,
        (SELECT stock_qty FROM inventory_items WHERE item_id = NEW.item_id),
        NEW.qty;
    END IF;
    
    -- Update stok
    UPDATE inventory_items
    SET stock_qty = stock_qty - NEW.qty
    WHERE item_id = NEW.item_id;
  
  -- ============================================
  -- KASUS 3: ADJUSTMENT (Penyesuaian) → stok bisa tambah/kurang
  -- ============================================
  ELSIF NEW.trx_type = 'ADJUSTMENT' THEN
    UPDATE inventory_items
    SET stock_qty = stock_qty + NEW.qty
    WHERE item_id = NEW.item_id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- STEP 4: Daftarkan Trigger ke tabel
-- ============================================
CREATE TRIGGER trg_update_stock_and_journal
AFTER INSERT ON inventory_transactions
FOR EACH ROW
EXECUTE FUNCTION trg_update_stock_and_journal();