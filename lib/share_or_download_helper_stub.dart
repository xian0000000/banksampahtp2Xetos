// Dipakai untuk semua platform SELAIN web (Android/iOS/macOS/Windows).
//
// Sebelumnya file ini isinya stub no-op (canShareFile selalu false), jadi
// tombol "Bagikan" di HP nggak pernah beneran buka share sheet — cuma
// jatuh ke pesan "screenshot aja". Sekarang pakai `share_plus`, yang
// beneran wrap ACTION_SEND Intent di Android dan UIActivityViewController
// di iOS — itu yang bikin muncul pilihan WhatsApp/Telegram/Gmail/dll.
//
// XFile.fromData() dipakai (bukan nulis file sendiri ke disk dulu) karena
// data kita cuma ada di memori (Uint8List hasil render PNG/PDF) —
// share_plus yang urus nulis ke cache directory sementara di baliknya.
// `fileNameOverrides` dipakai supaya nama filenya sama seperti yang
// caller minta (tanpa itu, XFile.fromData kasih nama UUID acak).
//
// Catatan platform: share file TIDAK didukung di Linux desktop (cuma
// teks/email lewat share_plus, lihat dokumentasi plugin). canShareFile
// tetap dibiarkan true di semua platform di sini demi kesederhanaan —
// kalau ternyata gagal, shareFile() menangkap exception-nya dan balikin
// false, caller lalu fallback ke PublicFileSaver seperti biasa.

import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

bool canShareFile(
  Uint8List bytes,
  String fileName, {
  String mimeType = 'application/octet-stream',
}) =>
    true;

Future<bool> shareFile(
  Uint8List bytes,
  String fileName, {
  String mimeType = 'application/octet-stream',
  String? title,
  String? text,
}) async {
  try {
    final file = XFile.fromData(bytes, mimeType: mimeType, name: fileName);
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [file],
        fileNameOverrides: [fileName],
        title: title,
        text: text,
      ),
    );
    switch (result.status) {
      case ShareResultStatus.success:
        return true;
      case ShareResultStatus.unavailable:
        // Platform gak bisa lapor hasilnya (beberapa versi Android/iOS
        // lama) — share sheet-nya tetap kebuka & selesai tanpa error,
        // jadi dianggap berhasil daripada nampilin apa-apa ke user.
        return true;
      case ShareResultStatus.dismissed:
        // User nutup share sheet tanpa milih apa-apa — samain perlakuan
        // dengan versi web lama (AbortError -> false), caller nggak akan
        // fallback ke simpan file otomatis.
        return false;
    }
  } catch (_) {
    return false;
  }
}
