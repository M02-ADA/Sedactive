# Jungle Drift: spesifikasi aset buaya & burung

Dokumen ini buat desainer yang mau mengganti gambar placeholder buaya, burung macaw, dan efek air di mode **Jungle Drift** dengan ilustrasi asli.

Sekarang semua makhluk ini digambar pakai kode. Animasinya juga dibuat lewat kode: tiap potongan diputar dan digeser di titik engselnya. Jadi kamu cukup menggambar **potongan-potongan diam**, nggak perlu bikin animasi frame-by-frame, kecuali kepakan sayap burung dan percikan air.

Gaya gambarnya ikut [JUNGLE_ART_DIRECTION.md](../JUNGLE_ART_DIRECTION.md). Baca itu dulu.

---

## Isi folder ini

| Folder / file | Isi |
|---|---|
| `reference-placeholder/` | 43 PNG placeholder yang sekarang dipakai di game (pupil dan kilau mata nggak ikut karena cuma elips polos). Ini bentuk, ukuran, dan posisi yang harus kamu ganti. |
| `guides/` | Versi placeholder yang diberi tanda titik engsel (lihat legenda di bawah). |
| `in-game-gator.png` | Screenshot buaya waktu menyerang rakit di game. |
| `in-game-storyboard.png` | Storyboard satu putaran: hanyut → burung → buaya → landmark. |

**Legenda di `guides/`:**
- **Kotak garis putus-putus abu** = batas kanvas.
- **Silang merah dalam lingkaran** = titik putar (pivot) potongan itu. Waktu animasi, potongannya berputar di titik ini.
- **Titik biru** = tempat potongan lain dipasang (misalnya mata, ekor, kaki).
- **Garis putus-putus biru** = garis permukaan air (buaya tampak depan) atau garis dasar (percikan).

---

## Aturan umum (berlaku untuk semua aset)

1. **Format:** PNG dengan background transparan.
2. **Ukuran kanvas harus persis sama** dengan yang ada di tabel. Semua ukuran di dokumen ini dalam **pt** (point).
3. **Export di @2x.** Ukuran pixel-nya 2× ukuran kanvas, dan nama filenya diakhiri `@2x`.
   Contoh: kanvas 380×200 pt → file `croc-upper@2x.png` berukuran **760×400 px**.
4. **Titik engsel nggak boleh pindah.** Koordinatnya diukur dari **pojok kiri atas kanvas**: x ke kanan, y ke bawah, dalam pt (kalikan 2 untuk posisi pixel di file @2x).
5. **Bentuk boleh beda, proporsi jangan.** Detail di dalam siluet bebas kamu gambar ulang. Tapi ujung moncong, letak rahang, posisi mata, dan panjang badan sebaiknya tetap dekat dengan placeholder, karena sambungan antarpotongan dan titik gigitan ke rakit dihitung dari situ.
6. **Gambar di pinggir kanvas jangan sampai terpotong.** Sisakan ruang beberapa pt.
7. **Buaya akan di-mirror horizontal** waktu menyerang dari sisi kiri, jadi jangan pakai detail yang jadi aneh kalau dibalik (misalnya tulisan).

### Gaya (ringkasan dari art direction)

- **Outline:** satu warna tinta `#081A1A`, tebal sekitar **5 pt** untuk buaya (10 px di @2x), **4,5 pt** untuk burung, dan **4 pt** untuk ekor serta kaki buaya. Tebalnya sama di semua potongan, supaya waktu dirakit kelihatan seperti satu gambar.
- **Shading cel datar:** satu warna dasar, satu bayangan (di bagian bawah), satu highlight (kiri atas). **Tanpa gradien** di makhluk.
- **Mata:** sklera putih dan pupil gelap. Mata adalah fitur ekspresi utama.
- **Efek air nggak pakai outline.** Air itu cahaya, makhluk itu tinta.
- **Karakternya ramah-mengancam, bukan horor.** Bentuknya bulat dan empuk, bagian tajamnya cuma di gigi, sisik punggung, dan ujung paruh.

### Palet yang sekarang dipakai

| Peran | Hex |
|---|---|
| Outline / tinta | `#081A1A` |
| Buaya: dasar / bayangan / highlight | `#5C8F42` / `#38612E` / `#94C257` |
| Buaya: perut | `#E6D68F` |
| Buaya: mulut / tenggorokan | `#ED6B6B` / `#802133` |
| Gigi, cakar, paruh atas | `#FCF7E0` |
| Iris buaya | `#FFCC38` |
| Buih air | `#E0FCF5` |
| Macaw merah: badan / band sayap / bulu terbang | `#FF6B5E` / `#FFD140` / `#1A9ECC` |
| Macaw biru-kuning: badan / dada / kepala / bulu terbang | `#1A9ECC` / `#FFD140` / `#33C79E` / `#146BB3` |

Warna boleh disempurnakan, asal perannya tetap: lingkungan hutan dan air dominan hijau-teal, makhluk pakai aksen hangat atau saturasi tinggi supaya menonjol. Mulut coral buaya adalah satu-satunya "nada merah" penanda bahaya.

---

## 1. Buaya tampak samping (waktu menyerang)

Dipakai waktu buaya menerjang dan menggigit pinggir rakit. Dirakit dari 6 potongan badan dan 1 set mata. Potongan yang nggak tercantum di tabel (misalnya alis) diputar dari tengah kanvas.

| File | Kanvas (pt) | Export @2x (px) | Pivot (pt) | Titik pasang (pt) | Gerakannya di game |
|---|---|---|---|---|---|
| `croc-upper` (kepala + rahang atas) | 380 × 200 | 760 × 400 | **(40, 130)** = engsel rahang | mata (89, 43) · alis (92, 14) · titik gigitan (276, 130) | Mengangguk dan menggeleng saat menggigit |
| `croc-lower` (rahang bawah) | 380 × 90 | 760 × 180 | **(40, 8)** | — | Membuka sampai ±35° ke bawah |
| `croc-throat` (rongga mulut + lidah) | 340 × 200 | 680 × 400 | **(20, 6)** | — | Di-stretch vertikal dari 2% sampai 100% mengikuti rahang |
| `croc-body` (badan) | 440 × 170 | 880 × 340 | **(420, 92)** = leher | ekor (20, 96) · kaki (328, 114) | Miring sekitar 17° turun ke air, dan ikut gerak kepala dengan sedikit telat |
| `croc-tail` (ekor) | 360 × 110 | 720 × 220 | **(350, 56)** = pangkal | — | Mengibas kiri-kanan |
| `croc-leg` (kaki depan) | 150 × 160 | 300 × 320 | **(40, 18)** = bahu | — | Berputar 6°–52° waktu mencakar rakit |

**Urutan layer (dari belakang ke depan):** ekor → badan → kaki → tenggorokan → rahang bawah → kepala/rahang atas → mata → alis.

Tenggorokan dan rahang bawah sebenarnya digambar **di bawah dek rakit**, supaya waktu menggigit rahang bawah kelihatan "masuk" di bawah kayu.

**Posisi rakitan** (diukur di kanvas `croc-upper`, biar kamu bisa cek hasil rakitan di software gambarmu):
- **Rahang bawah:** pivot `croc-lower` (40, 8) ditaruh di **(40, 134)**.
- **Tenggorokan:** pivot `croc-throat` (20, 6) ditaruh di **(30, 133)**.
- **Badan:** pivot leher `croc-body` (420, 92) ditaruh di **(26, 146)**. Di game, badan otomatis diputar sekitar 17° turun ke air, jadi kalau dirakit lurus memang kelihatan agak kaku. Itu normal.
- **Ekor dan kaki:** nempel ke badan di titik biru `croc-body`.
- **Mata:** ditaruh di (89, 43) dengan skala **85%**.
- **Alis:** ditaruh di (92, 14) dengan skala 100%.

**Titik gigitan (276, 130)** adalah titik di gigi atas yang menempel ke pinggir rakit. Kalau moncongmu lebih panjang atau lebih pendek, kasih tahu developer supaya titik ini disetel ulang.

Badan bagian bawah akan tenggelam (terpotong di garis air), jadi bagian perut dan kaki nggak selalu kelihatan.

---

## 2. Mata buaya (dipakai di tampak samping dan tampak depan)

| File | Kanvas (pt) | Export @2x (px) | Pivot (pt) | Catatan |
|---|---|---|---|---|
| `croc-eye` (sklera + iris) | 80 × 80 | 160 × 160 | tengah (40, 40) | Bola mata. Kilau di (31, 30), tepi atas kelopak di (40, 6). |
| `croc-pupil` | 16 × 40 | 32 × 80 | tengah | Pupil celah vertikal. **Di-stretch horizontal 0,55×–2,2×** (celah → bulat waktu mau menyerang), jadi bentuknya harus tetap bagus kalau ditarik. Elips sederhana paling aman. |
| `croc-lid` (kelopak) | 80 × 70 | 160 × 140 | **tengah atas (40, 0)** | Turun dari atas menutupi mata: di-scale vertikal 18%–100% dan miring sampai ±10° waktu marah. Warnanya sama dengan kulit buaya. |
| `croc-brow` (alis) | 96 × 40 | 192 × 80 | tengah (48, 20) | Miring sampai ±17° waktu marah. |
| `croc-glint` (kilau) | 16 × 16 | 32 × 32 | tengah | Titik putih kecil. Diam di tempat, nggak ikut gerak pupil. |

`croc-pupil` dan `croc-glint` nggak ada di `reference-placeholder/` karena cuma elips polos. Ukurannya ikuti tabel di atas.

---

## 3. Buaya tampak depan (waktu mendekat)

| File | Kanvas (pt) | Export @2x (px) | Pivot (pt) | Catatan |
|---|---|---|---|---|
| `croc-front` | 300 × 170 | 600 × 340 | **(150, 150)** = tengah di garis air | Kepala rendah dan lebar dengan mata dan moncong di atas air. Mata (pakai set mata di atas) ditaruh di **(96, 92)** dan **(204, 92)** dengan skala **78%**. |

Semua yang ada **di bawah garis air y = 150 disembunyikan air**, jadi cukup diteruskan sedikit di bawah garis supaya nggak ada tepi yang keras. Kepala ini bergoyang sedikit (±3°) waktu berenang, dan naik-turun waktu muncul atau menyelam.

**Jangan gambar mata di file ini.** Matanya potongan terpisah supaya bisa berkedip dan pupilnya bisa berubah.

---

## 4. Bayangan buaya di bawah air

| File | Kanvas (pt) | Export @2x (px) | Catatan |
|---|---|---|---|
| `croc-shadow` | 220 × 460 | 440 × 920 | Siluet buaya dilihat dari atas, kepala menghadap ke bawah kanvas (ke arah kamera). **Tanpa outline, tepinya lembut/blur.** Warna gelap teal sekitar `#001A1A`. Di game dipipihkan jadi 42% tingginya karena rebah di permukaan air. |

---

## 5. Burung macaw

Burung **nggak dirakit dari potongan**, tapi pakai satu gambar utuh per pose. Totalnya **12 gambar per varian warna × 2 varian = 24 file**.

| | |
|---|---|
| Kanvas | **320 × 270 pt** (export 640 × 540 px) untuk semua pose |
| Pivot | **(160, 124)** = tengah badan. **Wajib sama di semua frame**, supaya kepakan sayap nggak membuat burung kelihatan bergeser. |
| Sudut pandang | Dari depan dan agak dari bawah, burung terbang ke arah kamera |
| Lebar sayap | Waktu terbentang penuh hampir selebar kanvas |
| Varian | `macaw0` = merah (scarlet), `macaw1` = biru-kuning. Proporsinya sama, cuma warnanya yang beda. |

**Daftar file per varian** (contoh untuk varian merah, `macaw0-…@2x.png`):

| File | Pose | Dipakai waktu |
|---|---|---|
| `macaw0-flap0` … `flap3` | **Downstroke:** sayap dari atas (±60° di atas horizontal) turun ke bawah (±49° di bawah), terbentang penuh | Terbang mengepak |
| `macaw0-flap4` … `flap7` | **Upstroke:** sayap naik lagi dari bawah ke atas, **agak dilipat** (paling terlipat sekitar 55% di frame 5–6) | Terbang mengepak |
| `macaw0-glide` | Sayap terbentang, sedikit ke atas (±8°) | Melayang di sela kepakan, dan lewat di atas pemain yang jongkok |
| `macaw0-tuck` | Sayap ke bawah dan terlipat rapat (±70%), ekor menguncup | Menukik |
| `macaw0-flare` | Sayap tinggi (±72°), ekor mengembang penuh, kaki keluar | Antisipasi: "mengerem" sebelum lewat di depan pemain |
| `macaw0-startled` | Sayap setengah naik (±43°), ekor mengembang, kaki keluar, **mata melotot dan pupil mengecil, paruh terbuka, jambul berdiri** | Kena kepala pemain yang nggak jongkok |

Delapan frame kepakan diputar berulang, dan kecepatannya beda-beda per burung. Supaya loop-nya mulus, **frame 7 harus nyambung balik ke frame 0**. Gerakan turun (downstroke) sengaja lebih cepat daripada naik.

Badan burung juga di-stretch vertikal sampai 4% di downstroke dan diputar waktu belok atau terjungkal. Jadi cukup gambar posenya, nggak perlu bikin versi miring.

---

## 6. Efek air

| File | Kanvas (pt) | Export @2x (px) | Pivot (pt) | Catatan |
|---|---|---|---|---|
| `splash-0` … `splash-5` | 280 × 260 | 560 × 520 | **(140, 236)** = garis dasar, tengah | **6 frame** percikan, diputar **0,065 detik per frame**: naik cepat (0–2), puncak dengan tetesan lepas (2–4), jatuh dan buih menyebar (4–5). Air berat: naiknya cepat, turunnya lebih pelan. |
| `ripple` | 240 × 240 | 480 × 480 | tengah | Cincin riak tipis yang agak putus-putus. Di game di-scale membesar sambil memudar. |
| `foam-collar` | 300 × 70 | 600 × 140 | tengah | Kalung buih menggumpal di tempat badan buaya menembus permukaan air. |

Semua efek air **tanpa outline**, pakai buih `#E0FCF5` dengan sedikit transparansi.

---

## Checklist sebelum kirim

- [ ] Semua file PNG transparan, nama persis seperti di tabel, diakhiri `@2x.png`
- [ ] Ukuran pixel = 2× ukuran kanvas
- [ ] Pivot dan titik pasang di posisi yang sama dengan `guides/`
- [ ] Outline satu warna dengan tebal yang sama di semua potongan buaya
- [ ] Mata buaya **nggak** digambar di `croc-upper` dan `croc-front`, cukup soket atau tonjolan matanya
- [ ] Kelopak `croc-lid` warnanya sama dengan kulit dan rapi waktu di-scale vertikal
- [ ] 8 frame kepakan burung loop dengan mulus (frame 7 → frame 0)
- [ ] Tengah badan burung tetap di (160, 124) di semua 12 pose
- [ ] Ada dua varian warna macaw (24 file)
- [ ] Efek air tanpa outline

**Total: 45 file**:
- buaya: 13 file (6 potongan badan, 5 potongan mata, tampak depan, bayangan)
- burung: 24 file
- efek air: 8 file (6 frame percikan, riak, buih)

Kalau mau mencoba dulu, kirim **satu potongan** (misalnya `croc-upper` dan set matanya) supaya bisa dipasang dan dicek di game sebelum mengerjakan semuanya.
