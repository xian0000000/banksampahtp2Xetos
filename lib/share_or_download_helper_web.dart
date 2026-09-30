// Implementasi asli untuk platform WEB. File ini hanya di-load lewat
// conditional import di share_or_download_helper.dart, jadi aman diimpor
// di sini karena hanya dikompilasi saat target build-nya web.
//
// dart:html belum punya binding buat Web Share API (navigator.share),
// jadi manggilnya lewat dart:js_util biasa — polanya sama kayak
// card_save_helper_web.dart yang juga pakai dart:html buat trigger
// download.

import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:typed_data';

/// Cek apakah browser mendukung Web Share API level 2 (share dengan
/// lampiran file). Ini yang bikin di HP (Android Chrome, iOS Safari)
/// muncul share sheet asli dengan pilihan WhatsApp/Telegram/dll — di
/// browser desktop yang gak dukung, ini balikin false, jadi caller bisa
/// fallback ke unduh biasa.
bool canShareFile(
  Uint8List bytes,
  String fileName, {
  String mimeType = 'application/octet-stream',
}) {
  try {
    final nav = html.window.navigator;
    if (!js_util.hasProperty(nav, 'share') ||
        !js_util.hasProperty(nav, 'canShare')) {
      return false;
    }
    final file = html.File([bytes], fileName, {'type': mimeType});
    final shareData = js_util.newObject();
    js_util.setProperty(shareData, 'files', [file]);
    return js_util.callMethod(nav, 'canShare', [shareData]) == true;
  } catch (_) {
    return false;
  }
}

/// Buka native share sheet browser dengan file terlampir, jadi nasabah
/// tinggal pilih mau dibagikan ke mana (WA, Telegram, simpan ke Files,
/// dll) tanpa perlu tahu file-nya nyasar ke folder Download mana.
///
/// Return true kalau berhasil dibagikan. Return false kalau dibatalkan
/// user (browser lempar AbortError waktu share sheet ditutup tanpa
/// milih apa-apa) ATAU gagal karena sebab lain — caller sengaja gak
/// dibedain biar simpel: kalau false, caller cukup diem aja (anggap user
/// emang milih batal), bukan otomatis fallback unduh.
Future<bool> shareFile(
  Uint8List bytes,
  String fileName, {
  String mimeType = 'application/octet-stream',
  String? title,
  String? text,
}) async {
  try {
    final nav = html.window.navigator;
    final file = html.File([bytes], fileName, {'type': mimeType});
    final shareData = js_util.newObject();
    js_util.setProperty(shareData, 'files', [file]);
    if (title != null) js_util.setProperty(shareData, 'title', title);
    if (text != null) js_util.setProperty(shareData, 'text', text);
    final promise = js_util.callMethod(nav, 'share', [shareData]);
    await js_util.promiseToFuture(promise);
    return true;
  } catch (_) {
    return false;
  }
}
