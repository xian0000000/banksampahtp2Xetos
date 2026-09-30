// Conditional export, polanya sama kayak card_save_helper.dart: kalau
// target compile-nya web, pakai implementasi asli yang manggil Web Share
// API (navigator.share) lewat JS interop. Kalau bukan web (Android/iOS/
// desktop), pakai stub kosong — di platform native, "share" file idealnya
// lewat plugin native (mis. share_plus) yang belum ada di project ini,
// jadi caller (lihat transaction_pdf.dart) tetap fallback ke jalur
// penyimpanan file yang sudah ada (public_file_saver) di platform itu.
export 'share_or_download_helper_stub.dart'
    if (dart.library.js_interop) 'share_or_download_helper_web.dart';
