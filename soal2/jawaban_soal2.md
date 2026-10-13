# Soal 2.2: Penanganan Concurrency (Race Condition)

## A. Permasalahan: Race Condition pada Transaksi Concurrent

Pada sistem penjualan multi-user, race condition dapat terjadi ketika dua atau lebih transaksi mengakses data yang sama secara bersamaan. Contoh kasus: dua kasir memproses penjualan untuk item yang sama pada detik yang sama, sementara stok tersisa hanya 1 unit.

**Alur masalah (tanpa proteksi):**
1. Kasir A membaca stok ITEM001 = 1
2. Kasir B membaca stok ITEM001 = 1 (sebelum A update)
3. Kasir A cek: cukup, lalu UPDATE stok = 0
4. Kasir B cek: cukup, lalu UPDATE stok = -1 (OVERSOLD!)
5. Akibatnya stok menjadi -1 dan terjadi overselling

Masalah ini disebut **phantom stock** atau **overselling** — stok fisik berubah di luar kendali sistem, memicu selisih saat stock opname.

## B. Solusi: Locking dengan SELECT ... FOR UPDATE

Teknik `SELECT ... FOR UPDATE` melakukan **row-level lock** pada baris yang dibaca. Ketika transaksi pertama melakukan lock, transaksi kedua yang mencoba membaca baris yang sama akan **diblokir** sampai transaksi pertama selesai (COMMIT atau ROLLBACK).

**Alur dengan FOR UPDATE:**
1. Kasir A: `SELECT ... FOR UPDATE` → berhasil, baris terkunci
2. Kasir B: `SELECT ... FOR UPDATE` → BLOCKED (menunggu Kasir A selesai)
3. Kasir A: cek stok cukup → UPDATE stok = 0 → COMMIT
4. Kasir A melepas lock
5. Kasir B: baru bisa akses → baca stok = 0 → cek: tidak cukup → RAISE ERROR
6. Stok tetap 0, tidak terjadi overselling

**Keunggulan:**
- Mencegah race condition secara pasti
- Hanya mengunci baris yang relevan (bukan seluruh tabel)
- Overhead minimal

**Kekurangan:**
- Transaksi yang menunggu bisa timeout jika lock terlalu lama
- Perlu manajemen transaksi yang hati-hati

## C. Alternatif: Serializable Isolation Level

Alternatif lain adalah menggunakan **isolation level Serializable** pada transaksi. PostgreSQL akan mendeteksi konflik antar transaksi dan otomatis membatalkan (ROLLBACK) salah satu transaksi dengan error "could not serialize access due to concurrent update".

Kelebihan: tidak perlu menuliskan `FOR UPDATE` secara eksplisit.

Kekurangan: lebih banyak transaksi yang dibatalkan → perlu retry logic.

## D. Contoh Implementasi Kode

### D.1. SELECT ... FOR UPDATE (Rekomendasi)

```sql
-- Transaksi penjualan dengan row-level lock
BEGIN;

  -- Kunci baris item untuk mencegah concurrent access
  SELECT stock_qty 
  FROM inventory_items 
  WHERE item_id = 'ITEM001' 
  FOR UPDATE;

  -- Cek stok cukup (misalnya butuh 1 unit)
  -- (Logika ini biasanya ada di stored procedure atau aplikasi)
  -- Kalau stock_qty < qty_diminta -> RAISE EXCEPTION

  -- Update stok
  UPDATE inventory_items 
  SET stock_qty = stock_qty - 1 
  WHERE item_id = 'ITEM001';

COMMIT;

### D.2. Serializable Isolation Level

```sql
BEGIN ISOLATION LEVEL SERIALIZABLE;

  SELECT stock_qty 
  FROM inventory_items 
  WHERE item_id = 'ITEM001';

  -- Cek stok, kalau cukup:
  UPDATE inventory_items 
  SET stock_qty = stock_qty - 1 
  WHERE item_id = 'ITEM001';

COMMIT;
-- Jika ada konflik, PostgreSQL akan ROLLBACK otomatis
```

### D.3. Implementasi di Stored Procedure (Production-Ready)

```sql
CREATE OR REPLACE FUNCTION process_sale(
  p_item_id VARCHAR(10),
  p_qty INT
)
RETURNS VOID AS $$
DECLARE
  v_stock INT;
BEGIN
  -- Kunci baris & ambil stok saat ini
  SELECT stock_qty INTO v_stock
  FROM inventory_items
  WHERE item_id = p_item_id
  FOR UPDATE;
  
  -- Validasi stok
  IF v_stock < p_qty THEN
    RAISE EXCEPTION 'Stok tidak cukup: tersedia %, diminta %', v_stock, p_qty;
  END IF;
  
  -- Update stok
  UPDATE inventory_items
  SET stock_qty = stock_qty - p_qty
  WHERE item_id = p_item_id;
END;
$$ LANGUAGE plpgsql;
```

## E. Kesimpulan

Untuk mencegah overselling pada sistem penjualan concurrent, teknik 
**`SELECT ... FOR UPDATE`** adalah pilihan yang paling tepat karena:
1. Memberikan kontrol granular (per baris)
2. Overhead minimal
3. Menghindari phantom read tanpa perlu full table lock
4. Cocok untuk sistem perpetual inventory seperti PT Diponegoro Logistik Utama

Isolation level **Serializable** bisa menjadi alternatif, namun memerlukan 
retry logic karena seringnya transaksi dibatalkan.