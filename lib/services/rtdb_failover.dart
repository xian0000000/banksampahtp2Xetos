import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../firebase_options.dart';

/// Baca dari 2 server Realtime Database dengan failover otomatis.
///
/// • Server 0 = utama, server 1 = cadangan (project Firebase ke-2, datanya
///   di-dual-write oleh web-admin).
/// • [watch] mendengarkan server aktif. Kalau data pertama tidak datang dalam
///   [firstDataTimeout], atau koneksi putus > [disconnectGrace], semua listener
///   pindah ke server lain TANPA perlu restart (stream tetap sama).
/// • Selama di cadangan, tiap [recoveryEvery] dicoba balik ke utama.
class RtdbFailover {
  RtdbFailover._();
  static final RtdbFailover instance = RtdbFailover._();

  static const firstDataTimeout = Duration(seconds: 8);
  static const disconnectGrace = Duration(seconds: 10);
  static const recoveryEvery = Duration(seconds: 30);

  final List<FirebaseDatabase> _dbs = [];
  FirebaseAuth? _auth2;
  int _active = 0;
  final _changes = StreamController<int>.broadcast();
  StreamSubscription<DatabaseEvent>? _connSub;
  Timer? _discTimer;
  Timer? _recoveryTimer;

  int get activeIndex => _active;
  bool get hasSecondary => _dbs.length > 1;

  /// Panggil sekali di main() SETELAH Firebase.initializeApp utama.
  Future<void> init() async {
    _dbs
      ..clear()
      ..add(FirebaseDatabase.instance);
    final opts = SecondaryFirebaseOptions.options;
    if (opts != null) {
      final app2 = await Firebase.initializeApp(name: 'server2', options: opts);
      _dbs.add(FirebaseDatabase.instanceFor(
        app: app2,
        databaseURL: opts.databaseURL!,
      ));
      _auth2 = FirebaseAuth.instanceFor(app: app2);
      _monitor();
      _recoveryTimer?.cancel();
      _recoveryTimer = Timer.periodic(recoveryEvery, (_) => _probePrimary());
    }
  }

  void _monitor() {
    _connSub?.cancel();
    _discTimer?.cancel();
    _connSub = _dbs[_active].ref('.info/connected').onValue.listen((e) {
      _discTimer?.cancel();
      if (e.snapshot.value != true) {
        final watched = _active;
        _discTimer = Timer(disconnectGrace, () => _markBad(watched));
      }
    });
  }

  void _switchTo(int i) {
    if (i == _active) return;
    debugPrint('[RtdbFailover] pindah server $_active -> $i');
    _active = i;
    _monitor();
    _changes.add(i);
  }

  void _markBad(int i) {
    if (_dbs.length < 2 || _active != i) return;
    _switchTo((i + 1) % _dbs.length);
  }

  Future<void> _probePrimary() async {
    if (_active == 0 || _dbs.length < 2) return;
    try {
      await _dbs[0].ref('kategori').get().timeout(const Duration(seconds: 5));
      _switchTo(0);
    } catch (_) {
      // utama masih mati, tetap di cadangan
    }
  }

  /// Setara `ref(path).onValue`, tapi pindah server otomatis.
  Stream<dynamic> watch(String path) {
    return Stream.multi((controller) {
      StreamSubscription<DatabaseEvent>? sub;
      Timer? timer;
      var idx = _active;

      void attach(int i) {
        sub?.cancel();
        timer?.cancel();
        idx = i;
        var gotFirst = false;
        timer = Timer(firstDataTimeout, () {
          if (!gotFirst) _markBad(i);
        });
        sub = _dbs[i].ref(path).onValue.listen(
          (e) {
            gotFirst = true;
            timer?.cancel();
            controller.add(e.snapshot.value);
          },
          onError: (Object err) {
            // permission-denied = masalah rules, bukan server mati → teruskan.
            debugPrint('[RtdbFailover] error di $path (server $i): $err');
            if (err is FirebaseException && err.code == 'permission-denied') {
              controller.addError(err);
            } else {
              _markBad(i);
            }
          },
        );
      }

      attach(_active);
      final changeSub = _changes.stream.listen((a) {
        if (a != idx) attach(a);
      });
      controller.onCancel = () {
        sub?.cancel();
        timer?.cancel();
        changeSub.cancel();
      };
    });
  }

  /// Baca sekali (mis. email_to_uid), coba server aktif dulu lalu yang lain.
  Future<dynamic> getOnce(String path) async {
    final order = [_active, for (var i = 0; i < _dbs.length; i++) if (i != _active) i];
    Object? lastErr;
    for (final i in order) {
      try {
        final snap = await _dbs[i].ref(path).get().timeout(firstDataTimeout);
        return snap.exists ? snap.value : null;
      } catch (e) {
        lastErr = e;
      }
    }
    throw StateError('Semua server tidak bisa dihubungi: $lastErr');
  }

  /// Tulis ke KEDUA server (dipakai untuk PIN nasabah). Sukses kalau minimal
  /// satu server menerima.
  Future<void> write(String path, dynamic value) async {
    final results = await Future.wait(_dbs.map((d) async {
      try {
        await d.ref(path).set(value).timeout(firstDataTimeout);
        return true;
      } catch (_) {
        return false;
      }
    }));
    if (!results.contains(true)) {
      throw StateError('Gagal menyimpan: semua server tidak merespons.');
    }
  }

  /// Login juga ke server 2 dengan kredensial Google yang sama (best-effort,
  /// hanya perlu kalau Rules server 2 mewajibkan auth).
  Future<void> signInSecondary(AuthCredential credential) async {
    try {
      await _auth2?.signInWithCredential(credential);
    } catch (_) {}
  }

  Future<void> signOutSecondary() async {
    try {
      await _auth2?.signOut();
    } catch (_) {}
  }
}
