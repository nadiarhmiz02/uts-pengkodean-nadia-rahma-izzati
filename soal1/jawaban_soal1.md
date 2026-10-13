## Soal 1.3: Analisis Audit & Keamanan Finansial

### A. Keunggulan Header-Line dari Perspektif Audit Trail

Pemisahan tabel Header-Line memisahkan antara metadata transaksi 
(tanggal, nomor bukti, deskripsi, status posting) yang tersimpan 
di tabel `journal_headers` dengan detail baris jurnal (akun, 
nominal debit, nominal kredit) yang tersimpan di tabel 
`journal_lines`. Dengan struktur ini, auditor dapat melacak 
perubahan secara granular: apakah yang berubah adalah informasi 
level header (misalnya status posting berubah dari DRAFT ke 
POSTED) atau detail level baris (misalnya koreksi nominal). 
Selain itu, header dapat diberi field tambahan seperti 
`created_by`, `created_at`, dan `posted_by` tanpa menduplikasi 
data ke setiap baris jurnal.

Pada model Flat Table, semua atribut tercampur dalam satu tabel, 
sehingga sulit membedakan perubahan level transaksi vs perubahan 
level baris. Audit trail menjadi ambigu, dan informasi "siapa 
yang mengubah apa" tidak dapat dilacak dengan presisi.

### B. Keunggulan Header-Line dari Perspektif 3NF

Third Normal Form (3NF) mensyaratkan tidak ada ketergantungan 
transitif — setiap atribut non-key harus bergantung langsung ke 
primary key. Pada model Header-Line, atribut seperti 
`tanggal_transaksi` dan `nomor_referensi` hanya muncul sekali 
di tabel header, sementara atribut `debit` dan `credit` muncul 
di tabel lines. Tidak ada redundansi data.

Sebaliknya, pada Flat Table, satu transaksi dengan 5 baris jurnal 
(debit-kredit) akan mengulang field tanggal, nomor bukti, dan 
deskripsi sebanyak 5 kali. Ini melanggar prinsip 3NF karena 
terjadi ketergantungan transitif. Jika tanggal harus dikoreksi, 
pada Flat Table perlu update 5 baris sekaligus; sedangkan pada 
Header-Line cukup update 1 baris di header. Hal ini meningkatkan 
konsistensi data dan mengurangi risiko anomali update.

### C. Kesimpulan

Struktur Header-Line lebih andal dibandingkan Flat Table karena:
1. Audit trail lebih jelas & granular
2. Memenuhi 3NF → tidak ada redundansi
3. Update lebih efisien (1 baris vs banyak baris)
4. Risiko inkonsistensi data lebih rendah