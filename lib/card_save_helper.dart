// Conditional export: kalau target compile-nya web (dart.library.js_interop
// tersedia), pakai implementasi asli yang mengimpor dart:html buat trigger
// download & cetak lewat browser. Kalau bukan web (Android/iOS/desktop),
// pakai stub kosong — lihat card_save_helper_stub.dart untuk penjelasan
// kenapa unduh langsung belum didukung di platform itu.
export 'card_save_helper_stub.dart'
    if (dart.library.js_interop) 'card_save_helper_web.dart';
