// Conditional export: kalau target compile-nya web (dart.library.js_interop
// tersedia), pakai implementasi asli yang mengimpor google_sign_in_web.
// Kalau bukan web (Android/iOS/desktop), pakai stub kosong yang sama
// sekali tidak menyentuh google_sign_in_web / dart:ui_web.
export 'gsi_web_helper_stub.dart'
    if (dart.library.js_interop) 'gsi_web_helper_web.dart';
