# Stunt Run Spike

Prototipe game gerak kooperatif untuk **iPad**: orang tua dan anak main bareng di depan kamera, dan tubuh mereka "dipotong" langsung dari video lalu ditaruh **di dalam** dunia game. Inputnya cuma gerakan badan (jongkok dan condong ke samping), tanpa sentuh layar. Inspirasinya game Shape Up.

Ini *spike* (eksperimen teknis), bukan produk jadi. Pertanyaan yang mau dijawab: **bisa nggak bikin game gerak yang kelihatan spektakuler pakai teknologi native Apple, tetap mulus real-time, dan realistis dibikin MVP-nya dalam 2 bulan?**

**Jawabannya: bisa.** Pendekatan yang dipilih adalah **2.5D SpriteKit + cutout pemain live dari Vision**.

---

## Dua mode game

### 1. Stunt Run (Neon Express)
Dua pemain berdiri di atap kereta yang melaju menembus kota synthwave saat senja.

- Gerbang rendah datang dari cakrawala, dan tiap pemain punya jalurnya sendiri (coral = Parent di kiri, teal = Child di kanan).
- Muncul **DUCK!** → dua-duanya harus jongkok sebelum gerbang lewat.
- Kalau dua-duanya berhasil: **TEAM DUCK!** Gerbangnya pecah, kereta melesat, dan Team Power bertambah.
- Kalau Team Power penuh: **TURBO**, kecepatan 2× dan suasananya berubah jadi malam.
- Nggak ada hukuman. Kalau cuma satu yang berhasil, dia tetap dapat poin dan partnernya dapat "ALMOST!".

### 2. Jungle Drift
Parent dan Child terdampar di satu rakit yang hanyut di sungai Amazon yang nggak ada ujungnya.

- **Condong (lean)** ke kiri/kanan untuk menjaga rakit tetap seimbang. Lean dua orang dijumlahkan, jadi kerja sama bikin rakit lebih cepat stabil.
- **Jongkok (duck)** untuk menghindari kawanan burung yang menukik. Jongkok juga ikut meredam goyangan rakit.
- **Buaya** menggigit pinggir rakit dan menariknya ke bawah, jadi semua harus condong ke sisi sebaliknya.
- **Lompat (jump)** untuk menghindari **piranha** yang melompat rendah melintasi rakit, setinggi tulang kering. Diawali sirip dan air yang bergolak sebagai peringatan, lalu aba-aba **JUMP!** dan hitungan "3-2-1". Ikan lewat di depan pemain yang dekat duluan, lalu pemain satunya sekitar 0,5 detik kemudian. Kalau terlambat atau terlalu cepat, kakinya "digigit" (cuma lucu-lucuan, poin nggak berkurang).
- Jadi tiap bahaya punya satu gerakan: **burung = jongkok, buaya = jaga keseimbangan, piranha = lompat.**
- Kalau rakit miring terlalu lama: **SPLASH**, Team Power berkurang, lalu rakitnya ditegakkan lagi.
- Ada 4 bioma yang berganti pelan-pelan (Open River, Deep Canopy, Lost Ruins, Misty Backwater) plus landmark seperti kuil kuno dan pohon kapuk raksasa.

---

## Hasil yang sudah terukur

Di **iPad Pro 13" (M4)** dengan kamera depan dan 1–2 orang sungguhan (mode Stunt Run):

| | Hasil |
|---|---|
| Render | **60 fps stabil** (frame terpanjang 16,7 ms) |
| Vision (pose + segmentasi) | ~30 fps, sekitar 28 ms per frame |
| Jeda dari jongkok sampai feedback di layar | **~69 ms** (di bawah ambang ~100 ms yang mulai terasa) |
| Memori | ~370 MB |
| Suhu | normal sepanjang sesi |
| Jarak main | 2,5–3 m, badan penuh kelihatan di atas pad |

Jungle Drift (termasuk piranha) sejauh ini baru dicoba di **simulator** dengan pemain simulasi: 60 fps, dan 39 tes logika lolos.

## Yang belum terbukti

- Belum ada tes 10 menit nonstop di iPad untuk cek panas.
- Akurasi hitungan jongkok belum dibandingkan dengan hitungan manual.
- Deteksi **lean** dan **lompat** dari pose asli belum dites dengan orang sungguhan (terutama anak-anak).
- Jungle Drift belum pernah jalan di iPad asli.
- Kenyamanan buat anak: goyangan rakit dan tikungan sungai.
- Buaya itu "seru-seram" atau malah terlalu seram buat anak kecil?
- Semua gambar dan suara masih placeholder yang dibuat lewat kode.

---

## Cara menjalankan

Butuh **Xcode 26** dan macOS. Nggak ada dependency, nggak butuh internet.

1. Buka `StuntRunSpike.xcodeproj`.
2. Di pengaturan *Signing & Capabilities*, ganti **Team** ke akunmu sendiri dan ubah **Bundle Identifier** (yang sekarang terdaftar di akun developer pembuatnya).
3. Pilih tujuan run:
   - **Simulator iPad:** kamera diganti test card dan dua pemain digerakkan otomatis. Tombol `1`, `2`, `3` untuk simulasi jongkok.
   - **iPad asli:** kamera depan aktif dan autoplay mati otomatis. Taruh iPad landscape, lalu berdiri sekitar 2,5–3 m di depannya.
   - **My Mac (Mac Catalyst):** untuk tes cepat pakai kamera Mac.

**Ganti mode:** pakai picker "Game" di panel developer (Stunt Run | Jungle Drift), atau launch argument `-gameMode jungle`.

**Kontrol keyboard di Jungle Drift:** `A`/`D` = P1 condong kiri/kanan, `J`/`L` = P2 condong kiri/kanan, `E` / `I` = P1 / P2 lompat, `4` = dua-duanya lompat.

**Launch argument lain yang berguna:**

| Argumen | Fungsi |
|---|---|
| `-scenario coop` | jalankan skrip deterministik (semua skenario berurutan) |
| `-cleanUI YES` | sembunyikan panel developer (buat screenshot) |
| `-mode camera` | Mode A: tampilkan kamera mentah + overlay |
| `-reduceMotion YES` | paksa Reduce Motion |

**Tes logika** (jalan di macOS, tanpa simulator):

```bash
./LogicTests/run.sh
```

---

## Isi folder

| Path | Isi |
|---|---|
| `StuntRunSpike/` | Kode app utama (SwiftUI + SpriteKit + Vision) |
| `StuntRunSpike/CameraPipeline.swift` | Kamera → pose + segmentasi → cutout pemain dengan rim warna |
| `StuntRunSpike/SquatDetector.swift`, `Pose.swift` | Deteksi jongkok (logika murni, ada unit test) |
| `StuntRunSpike/CoopLogic.swift`, `JungleLogic.swift` | Aturan kerja sama, rakit, buaya, dan burung (logika murni, ada unit test) |
| `StuntRunSpike/PiranhaLogic.swift` | Deteksi lompat dan penilaian piranha (logika murni, ada unit test) |
| `StuntRunSpike/WorldScene*.swift` | Dunia Stunt Run: proyeksi pseudo-3D, gameplay, HUD, efek |
| `StuntRunSpike/*Jungle*.swift` | Dunia, animasi, makhluk, dan shader Jungle Drift |
| `StuntRun3D/` | Eksperimen versi 3D penuh pakai RealityKit (kesimpulannya: nggak sepadan dengan usahanya) |
| `LogicTests/` | 39 tes logika deterministik |
| `Evidence/` | Screenshot, video, dan log dari tiap revisi |
| `FINDINGS.md` | Laporan teknis lengkap: pengukuran, keputusan, risiko, dan riwayat revisi 1–9 |
| `JUNGLE_ART_DIRECTION.md` | Panduan gaya visual dan animasi Jungle Drift |

## Kenapa 2.5D, bukan 3D penuh?

Cutout pemain itu pada dasarnya gambar datar, renderer apa pun yang dipakai. Kameranya juga dikunci menghadap ke depan (sama seperti kebanyakan kamera di Shape Up), jadi 3D penuh hampir nggak nambah apa-apa secara visual, tapi biaya dan risikonya jauh lebih besar. Uangnya lebih berguna buat ilustrasi, variasi rintangan, dan akurasi deteksi gerak. Versi RealityKit sudah dicoba di `StuntRun3D/` untuk membuktikan ini.

## Privasi

App ini cuma minta izin kamera (tanpa mikrofon). Nggak ada yang direkam atau di-upload, dan kamera berhenti begitu app masuk background.

---

Detail teknis lengkapnya ada di [`FINDINGS.md`](FINDINGS.md).
