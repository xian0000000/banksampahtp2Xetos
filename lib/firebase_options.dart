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

/// Server 2 (cadangan): project server-backup1-tp2. Pakai web app config
/// yang sama polanya dengan server 1 (currentPlatform di atas).
class SecondaryFirebaseOptions {
  static FirebaseOptions? get options {
    return const FirebaseOptions(
      apiKey: 'AIzaSyCh1D3uL3bmJGF-auByzG6hlx378rT_v5g',
      appId: '1:212555470914:web:a4a7fa9b0e662f7419f5db',
      messagingSenderId: '212555470914',
      projectId: 'server-backup1-tp2',
      authDomain: 'server-backup1-tp2.firebaseapp.com',
      databaseURL:
          'https://server-backup1-tp2-default-rtdb.asia-southeast1.firebasedatabase.app',
      storageBucket: 'server-backup1-tp2.firebasestorage.app',
    );
  }
}
