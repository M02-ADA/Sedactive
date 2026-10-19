# Bermain dengan kamera MacBook

Aplikasi sekarang bisa berjalan langsung di MacBook menggunakan Mac Catalyst. Kamera bawaan MacBook mengirim frame nyata ke Apple Vision untuk mendeteksi tubuh dan pergelangan kedua pemain. Mouse tetap dipakai untuk memilih menu; selama ronde, gerakan tubuh menjadi kontrol game.

## Dari Xcode

1. Buka **FamilyMove.xcodeproj**.
2. Pilih scheme **FamilyMove**.
3. Pada run destination, pilih **My Mac (Mac Catalyst)**. “My Mac” di sini adalah MacBook yang sedang kamu gunakan.
4. Tekan **⌘R**. Build Mac lokal sudah memakai ad-hoc signing; development team tidak diperlukan untuk menjalankannya sendiri.
5. Pada layar awal, **Check MacBook Camera** bisa digunakan untuk memeriksa kamera terlebih dahulu. Izinkan akses kamera ketika macOS menanyakannya. Tekan **Done** untuk kembali.
6. Tambahkan minimal dua profil, pilih game dan dua pemain, lalu tekan **Play**.
7. Berdiri berdampingan dengan bahu dan pinggul terlihat. P1 di kiri layar, P2 di kanan layar. Birds & Alligators juga membutuhkan kaki terlihat.
8. Tunggu kalibrasi dan countdown. Whack the Mole dipukul dengan menggerakkan tangan menuju mole; tidak perlu menyentuh MacBook.

Apabila pilihan Mac Catalyst belum terlihat, tutup dan buka kembali `.xcodeproj`. Jangan membuka `Package.swift` sebagai proyek utama: itu paket untuk tes logika dan tidak meluncurkan aplikasi.

## Dari Terminal

Jalankan dari folder proyek:

```sh
bash Scripts/run-mac.sh
```

Perintah ini membangun dan membuka aplikasi MacBook. Untuk membuat build Release:

```sh
bash Scripts/build-mac.sh Release
```

Aplikasi hasil build berada di `.build/Mac/Build/Products/Debug-maccatalyst/FamilyMove.app` atau `Release-maccatalyst/FamilyMove.app`. Aplikasi Release dapat dibuka lagi tanpa menjalankan Xcode.

## Kamera dan ukuran jendela

- Mendukung kamera bawaan MacBook dan webcam USB yang ditemukan AVFoundation.
- Preview ditampilkan mirror; Vision menerima frame tanpa mirror, lalu mapper menerapkan mirror yang sama untuk efek tangan dan collision.
- Jalur Mac mempertahankan orientasi kamera horizontal asli. Rotasi sensor iPad tidak diterapkan pada webcam MacBook.
- Jendela memiliki ukuran minimum untuk arena dua pemain. Mengubah ukuran saat bermain akan meminta kalibrasi ulang agar posisi target tetap sesuai.
- Jika akses kamera ditolak, tekan **Open Settings**, lalu izinkan **Family Move** pada **Privacy & Security → Camera**. Kembali ke aplikasi dan coba lagi. Tutup aplikasi kamera lain jika webcam sedang dipakai secara eksklusif.
- Profil dan riwayat versi Mac disimpan lokal dalam container aplikasi Mac, terpisah dari iPad dan iPad Simulator. Tidak ada sinkronisasi otomatis.

## Simulator

Sesuai prioritas terbaru, kamera MacBook dipakai dengan menjalankan aplikasi langsung melalui **My Mac (Mac Catalyst)**. iPad Simulator tetap memiliki preview kontrol terpisah melalui scheme **FamilyMove Simulator**. Tidak diperlukan Camera Bridge atau layanan jaringan lokal.

## Validasi

Build MacBook berhasil dibuka. Pemeriksaan kamera nyata berhasil mendeteksi satu orang dan kedua pergelangannya; debug menunjukkan sekitar 10 deteksi/detik dan 7 ms pemrosesan Vision pada saat pemeriksaan. Angka ini adalah pengamatan singkat, bukan jaminan performa.

Pengujian dua orang sekaligus dan ronde lengkap dengan gerakan nyata tetap membutuhkan dua pemain di depan kamera. Frame diproses di perangkat tanpa disimpan atau diunggah.
