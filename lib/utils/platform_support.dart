import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// firebase_core (dan semua plugin di atasnya seperti firebase_database)
/// belum punya implementasi native untuk Linux desktop, jadi di platform
/// itu aplikasi ini pakai REST API biasa (lihat lib/rest/rtdb_rest.dart)
/// alih-alih native SDK.
bool get isLinuxDesktop =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;
