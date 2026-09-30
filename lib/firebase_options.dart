// File: lib/firebase_options.dart
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    return const FirebaseOptions(
      apiKey: 'AIzaSyBRuCNCG24CAwdOJNPSTKXvtRWRL1qIPL8',
      appId: '1:306920049631:web:2f8e35b8051a8f6b01d26a',
      messagingSenderId: '306920049631',
      projectId: 'banksampahtp2xetos',
      authDomain: 'banksampahtp2xetos.firebaseapp.com',
      databaseURL: 'https://banksampahtp2xetos-default-rtdb.asia-southeast1.firebasedatabase.app',
      storageBucket: 'banksampahtp2xetos.firebasestorage.app',
    );
  }
}
