// Dipakai untuk semua platform SELAIN web (Android/iOS/desktop).
//
// PENTING: unduh langsung ke penyimpanan/galeri di Android & iOS butuh
// plugin tambahan (mis. image_gallery_saver / gal / share_plus) yang belum
// ada di dependency project ini. Daripada nebak-nebak plugin yang mungkin
// belum ter-install (bisa bikin build gagal), stub ini sengaja no-op dan
// UI (lihat _CardPreviewPage di main.dart) akan kasih tau nasabah supaya
// screenshot layar sebagai alternatif di platform ini. Kalau nanti mau
// nambahin unduh langsung di Android/iOS, tinggal isi fungsi di bawah pakai
// plugin pilihan lalu update `canDownloadDirectly` jadi true.

import 'dart:typed_data';

bool get canDownloadDirectly => false;

void downloadPngBytes(Uint8List bytes, String fileName) {
  // No-op — lihat catatan di atas.
}

void printPngBytes(Uint8List bytes) {
  // No-op — cetak langsung juga butuh plugin tambahan (mis. package
  // `printing`) yang belum ada di project ini.
}
