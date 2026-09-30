// Implementasi asli untuk platform WEB. File ini hanya di-load lewat
// conditional import di gsi_web_helper.dart, jadi aman diimpor di sini
// karena hanya dikompilasi saat target build-nya web.

import 'package:flutter/material.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:google_sign_in_web/google_sign_in_web.dart' as gsi_web;

/// Render tombol resmi Google Identity Services (GIS) lewat plugin web
/// google_sign_in. Return null kalau plugin web somehow tidak terdeteksi.
Widget? tryRenderGoogleSignInButton() {
  final plugin = GoogleSignInPlatform.instance;
  if (plugin is gsi_web.GoogleSignInPlugin) {
    return SizedBox(
      height: 44,
      child: plugin.renderButton(),
    );
  }
  return null;
}
