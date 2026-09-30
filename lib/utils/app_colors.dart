// Palet aplikasi. Dulu tiap halaman bikin warnanya sendiri — dashboard
// pakai #F4F7F6, halaman preview kartu pakai hijau tua #0A3C19 yang tidak
// muncul di mana pun lagi, dan PDF punya hijau ketiga. Dikumpulkan di sini
// supaya satu perubahan warna berlaku di seluruh app sekaligus.

import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  /// Hijau utama merek. Dipakai untuk tombol primer, aksen, dan header PDF.
  static const Color hijau = Color(0xFF23524E);

  /// Varian gelap untuk teks di atas permukaan terang dan untuk outline
  /// teks di atas ilustrasi kartu.
  static const Color hijauGelap = Color(0xFF0A3C19);

  /// Latar lembut untuk blok hijau tipis (badge, panel preview).
  static const Color hijauMuda = Color(0xFFEAF5F2);

  /// Latar halaman standar.
  static const Color latar = Color(0xFFF4F7F6);

  /// Permukaan kartu di atas [latar].
  static const Color permukaan = Colors.white;

  /// Garis tipis pemisah.
  static const Color garis = Color(0xFFE3E9E7);

  /// Teks sekunder/keterangan.
  static const Color teksRedup = Color(0xFF6B7674);

  static const Color positif = Color(0xFF2E7D32);
  static const Color negatif = Color(0xFFC62828);
}
