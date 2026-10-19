# Penyempurnaan Family Move

Perbaikan ini melanjutkan MVP yang sudah ada, dengan fokus pada alur game yang dapat dipakai dan tampilan yang konsisten.

## Perbaikan perilaku

- **Rotasi dan perubahan ukuran:** pose serta kalibrasi lama dibatalkan, target aktif dibersihkan, dan waktu ronde dijeda. Pemain harus siap dan dikalibrasi lagi; skor serta waktu yang sudah dimainkan dipertahankan. Frame yang diproses sebelum perubahan ukuran/orientasi ditolak.
- **Kalibrasi yang stabil:** baseline tidak lagi langsung menerima rata-rata orang yang sedang bergerak. Sampel pinggul/bahu harus berada dalam toleransi pergerakan relatif terhadap panjang torso. Sampel tidak stabil kembali ke positioning dengan petunjuk untuk diam sesaat. Countdown hanya berjalan jika kedua baseline valid.
- **Jeda manual:** tombol Pause menahan game sampai pemain memilih Continue. Pemain yang masih terlihat tidak otomatis membatalkan jeda. Rotasi saat dijeda juga mempertahankan jeda manual.
- **Keluar ronde:** tombol keluar pada ronde yang sudah dimulai menjeda permainan dan meminta pilihan Keep Playing atau End Round. Keluar sebelum ronde dimulai tetap langsung kembali. Ronde yang selesai tetap disimpan melalui jalur idempoten yang sama.
- **Kehilangan satu pemain:** footer memberi petunjuk Move back into view untuk pemain terkait. Waktu dan target tetap memakai aturan tracking sebelumnya.

## Tampilan dan interaksi

- Tiga ilustrasi SVG buatan proyek menggantikan emoji pada kartu, preview, objek game, dan hasil. Aset tetap tajam pada berbagai ukuran iPad dan dapat diganti melalui asset catalog.
- Target mole memiliki cincin sisa waktu, perubahan visual singkat yang menghormati Reduce Motion, dan tetap memakai pusat/radius yang sama untuk collision.
- Audio countdown, sukses, dan akhir ronde dibuat lokal. Pengaturan Sound tersimpan; audio mengikuti silent switch dan tidak mengambil alih musik pengguna.
- Hasil menampilkan kontribusi skor, rincian jenis gerakan, dan rata-rata reaksi masing-masing pemain.
- Achievement menampilkan kemajuan dan target yang jelas. Dashboard juga menampilkan total reaches, ducks, dan jumps milik profil yang dipilih.
- Formulir menampilkan alasan berat/nama tidak valid, menerima angka desimal dengan koma, dan membedakan kesalahan tinggi dari berat.
- Warna utama dan kedua warna pemain memenuhi rasio kontras teks putih minimal 4.5:1. Teks/nilai HUD tetap besar, dan posisi objek menghindari HUD serta label bawah.

## Pengujian

Hasil akhir dicatat di `VALIDATION.md`. Unit test mencakup penolakan kalibrasi bergerak, kalibrasi jitter kecil, rotasi, jeda manual, data gerakan per anggota, dan parsing formulir.

UI test baru menjalankan alur dua game, pause, konfirmasi keluar, replay, hasil, dan penyimpanan. Untuk menguji alur itu di Simulator, tersedia pose sintetis **khusus Debug**, yang hanya aktif jika kedua argumen `--ui-testing` dan `--synthetic-poses` diberikan. Data masuk dalam koordinat layar dan melewati kamera/Vision; ronde dipersingkat menjadi delapan detik dan memakai database UI test terpisah. Audio selalu diam selama UI test. Release di iPad fisik memakai kamera nyata dengan durasi normal; mode Simulator manual dijelaskan di `SIMULATOR.md`.

**Pengujian sintetis tidak membuktikan akurasi kamera, latensi, squat/jump fisik, atau kesesuaian jangkauan orang dewasa dan anak.** Hal tersebut tetap membutuhkan iPad fisik sesuai checklist di `VALIDATION.md`. Nilai MET masih merupakan estimasi provisional.

## Hasil akhir

- 45 unit test lulus.
- Lima alur UI terverifikasi pada iPad Pro, dengan pengujian replay ulang terarah setelah perbaikan pemeriksaan teks sementara.
- Alur Mole, jeda manual, replay, dan penyimpanan tunggal juga lulus di iPad mini.
- Build Release terakhir berhasil.
- Screenshot Home/Progress diperbarui; screenshot hasil menggunakan data uji sintetis dan diberi nama sesuai konteksnya.
