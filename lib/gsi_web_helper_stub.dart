// Dipakai untuk semua platform SELAIN web (Android/iOS/desktop).
//
// PENTING: file ini sengaja TIDAK mengimpor `google_sign_in_web`, karena
// package itu bergantung pada `dart:ui_web` yang cuma valid untuk target
// web. Kalau di-import langsung tanpa syarat di `main.dart`, compiler
// AOT release (`flutter build apk --release`) ikut mencoba mengkompilasi
// `dart:ui_web` dan gagal dengan error:
//   FileSystemException: StandardFileSystem only supports file:* and
//   data:* URIs (org-dartlang-untranslatable-uri:dart%3Aui_web)
//
// Lihat gsi_web_helper.dart untuk mekanisme conditional import-nya.

import 'package:flutter/material.dart';

Widget? tryRenderGoogleSignInButton() => null;
