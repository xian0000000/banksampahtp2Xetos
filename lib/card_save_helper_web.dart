// Implementasi asli untuk platform WEB. File ini hanya di-load lewat
// conditional import di card_save_helper.dart, jadi aman diimpor di sini
// karena hanya dikompilasi saat target build-nya web.

import 'dart:html' as html;
import 'dart:typed_data';

/// True di web — browser selalu bisa memicu unduhan file secara langsung.
bool get canDownloadDirectly => true;

/// Picu unduhan file PNG lewat browser (bikin object URL sementara lalu
/// "klik" elemen <a download> secara terprogram).
void downloadPngBytes(Uint8List bytes, String fileName) {
  final blob = html.Blob([bytes], 'image/png');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();
  html.Url.revokeObjectUrl(url);
}

/// Buka gambar kartu di tab baru supaya nasabah/admin bisa pakai dialog
/// cetak bawaan browser (Ctrl+P) atau simpan gambarnya dari sana. Sengaja
/// tidak auto-trigger window.print() dari sini karena beberapa browser
/// memblokir pop-up yang langsung mencoba mencetak tanpa interaksi user
/// di tab barunya — buka di tab baru lebih konsisten di semua browser.
void printPngBytes(Uint8List bytes) {
  final blob = html.Blob([bytes], 'image/png');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.window.open(url, '_blank');
}
