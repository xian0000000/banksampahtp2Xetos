import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:device_preview/device_preview.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
// PENTING: jangan import 'package:google_sign_in_web/google_sign_in_web.dart'
// langsung di sini. Package itu butuh dart:ui_web yang cuma valid untuk
// target web, dan kalau di-import tanpa syarat, `flutter build apk --release`
// gagal kompilasi (AOT compiler ikut memproses dart:ui_web).
// gsi_web_helper.dart pakai conditional import supaya file itu betul-betul
// cuma di-load saat build target-nya web.
import 'gsi_web_helper.dart';
// Sama polanya kayak gsi_web_helper.dart: implementasi unduh/cetak kartu
// beda antara web (dart:html) dan platform lain (stub no-op).
import 'card_save_helper.dart';
import 'share_or_download_helper.dart';
import 'pages/setup_pin_page.dart';
import 'pages/transaction_detail_page.dart';
import 'firebase_options.dart';
import 'rest/rtdb_rest.dart';
import 'services/local_notifications.dart';
import 'services/rtdb_failover.dart';
import 'services/transaction_notifier.dart';
import 'utils/app_colors.dart';
import 'utils/formatters.dart';
import 'utils/platform_support.dart';

/// Kunci RTDB gak boleh mengandung '.', jadi disamakan dengan aturan yang
/// sama persis dipakai di web admin & database.rules.json: '.' -> ','.
String sanitizeEmailKey(String email) =>
    email.trim().toLowerCase().replaceAll('.', ',');

// ============================================================================
// Helper-helper di bawah ini top-level (bukan method di dalam class) supaya
// bisa dipakai bareng oleh NasabahDashboard (preview 4 transaksi terakhir)
// dan RiwayatLengkapPage (halaman riwayat penuh), tanpa duplikasi kode.
// ============================================================================

/// Stream generik: native SDK di platform yang support, REST di Linux
/// (lihat lib/rest/rtdb_rest.dart & lib/utils/platform_support.dart).
Stream<dynamic> watchRtdb(String path) {
  if (isLinuxDesktop) {
    return RtdbRest.watch(path);
  }
  return RtdbFailover.instance.watch(path);
}

/// Ubah snapshot mentah node `pengumuman` (Map<key, {judul, isi,
/// created_at}>) jadi List yang sudah diurutkan terbaru dulu. Dipakai
/// bareng oleh badge lonceng di AppBar, banner pengumuman terbaru di
/// dashboard, dan PengumumanPage (daftar lengkap).
List<Map<String, dynamic>> parsePengumumanList(dynamic raw) {
  if (raw is! Map) return [];
  final entries = raw.entries.map((e) {
    final v = Map<dynamic, dynamic>.from(e.value as Map);
    return {
      'key': e.key.toString(),
      'judul': (v['judul'] ?? '').toString(),
      'isi': (v['isi'] ?? '').toString(),
      'created_at': (v['created_at'] as num?)?.toInt() ?? 0,
    };
  }).toList();
  entries.sort(
    (a, b) => (b['created_at'] as int).compareTo(a['created_at'] as int),
  );
  return entries;
}

/// Ubah snapshot mentah node `kategori` (Map<key, {nama, harga}>) jadi List
/// yang sudah diurutkan alfabetis. Ini sumber "harga realtime" yang sama
/// persis dipakai admin web buat harga beli per kg (lihat web-admin/app.js).
List<Map<String, dynamic>> parseHargaSampahList(dynamic raw) {
  if (raw is! Map) return [];
  final entries = raw.entries.map((e) {
    final v = Map<dynamic, dynamic>.from(e.value as Map);
    return {
      'key': e.key.toString(),
      'nama': (v['nama'] ?? '-').toString(),
      'harga': ((v['harga'] as num?) ?? 0).round(),
    };
  }).toList();
  entries.sort(
    (a, b) => (a['nama'] as String).toLowerCase().compareTo(
      (b['nama'] as String).toLowerCase(),
    ),
  );
  return entries;
}

/// StreamBuilder untuk node RTDB yang membuat stream-nya SEKALI per State
/// (dan hanya dibuat ulang kalau [path] berubah). Memanggil
/// `watchRtdb(...)` langsung di dalam `build` bikin Stream baru tiap
/// rebuild, sehingga listener Firebase di-subscribe ulang terus.
class _RtdbBuilder extends StatefulWidget {
  const _RtdbBuilder({required this.path, required this.builder});

  final String path;
  final Widget Function(BuildContext, AsyncSnapshot<dynamic>) builder;

  @override
  State<_RtdbBuilder> createState() => _RtdbBuilderState();
}

class _RtdbBuilderState extends State<_RtdbBuilder> {
  late Stream<dynamic> _stream = watchRtdb(widget.path);

  @override
  void didUpdateWidget(covariant _RtdbBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _stream = watchRtdb(widget.path);
    }
  }

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<dynamic>(stream: _stream, builder: widget.builder);
}

/// StreamBuilder yang mempertahankan data valid TERAKHIR. Saat stream
/// subscribe ulang / pindah server / error sesaat / server baru mengirim
/// null, UI tetap menampilkan data terakhir, bukan mendadak kosong.
/// (Konsekuensi: kalau node benar-benar dihapus di server, tampilan baru
/// kosong setelah app dibuka ulang.)
class _StickyStreamBuilder extends StatefulWidget {
  const _StickyStreamBuilder({required this.stream, required this.builder});

  final Stream<dynamic> stream;
  final Widget Function(BuildContext, AsyncSnapshot<dynamic>) builder;

  @override
  State<_StickyStreamBuilder> createState() => _StickyStreamBuilderState();
}

class _StickyStreamBuilderState extends State<_StickyStreamBuilder> {
  dynamic _last;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<dynamic>(
      stream: widget.stream,
      builder: (context, snap) {
        if (snap.data != null) _last = snap.data;
        final shown = (snap.data == null && _last != null)
            ? AsyncSnapshot<dynamic>.withData(ConnectionState.active, _last)
            : snap;
        return widget.builder(context, shown);
      },
    );
  }
}

/// Kebalikan dari [watchRtdb]: tulis [value] ke [path]. Dipakai nasabah
/// buat nyimpen PIN transaksi yang dia atur sendiri (lihat SetupPinPage &
/// _PinGate) — sebelumnya app ini nggak pernah nulis apa-apa ke database,
/// semua tulis-menulis data ada di sisi web-admin.
Future<void> writeRtdb(String path, dynamic value) {
  if (isLinuxDesktop) {
    return RtdbRest.put(path, value);
  }
  return RtdbFailover.instance.write(path, value);
}

// formatRupiah() sekarang tinggal di utils/formatters.dart supaya dipakai
// bareng dengan generator PDF — dulu ada dua salinan yang beda hasil untuk
// nilai desimal.

/// Semua layar konten (dashboard, riwayat, setup PIN, detail transaksi,
/// dll — TERMASUK AppBar-nya) didesain buat lebar HP (~400an px). Daripada
/// bikin layout terpisah buat tablet/desktop (susah dijaga konsistensinya,
/// gampang out-of-sync sama layout HP), pendekatan yang dipilih: tampilan
/// mobile-nya dipakai APA ADANYA, cuma di-scale naik (zoom) berdasarkan
/// lebar layar:
///   - < 780px (HP)         -> scale 1x, gak ada perubahan sama sekali.
///   - >= 780px (tablet)    -> scale 2x.
///   - >= 1200px (desktop)  -> scale 3x.
/// Triknya: [mobileChild] dikasih ukuran "virtual" (lebar/tinggi layar
/// asli dibagi scale), jadi dia tetap ngelayout persis kayak di HP kecil,
/// lalu di-`Transform.scale` naik sebesar [scale] sehingga visualnya pas
/// mengisi lebar/tinggi layar asli. Gesture (tap/scroll) tetap jalan benar
/// karena Transform di Flutter otomatis nge-transform balik koordinat
/// sentuhannya.
///
/// PENTING: fungsi ini dipanggil SEKALI SAJA, di `builder` milik
/// `MaterialApp` (lihat [BankSampahApp]) — yaitu di atas `Navigator`,
/// jadi ngebungkus SEMUA layar sekaligus (termasuk AppBar, dialog, & layar
/// yang belum kebayang bakal ditambah nanti). Sebelumnya fungsi ini
/// dipanggil manual di masing-masing body layar (cuma 2 dari sekian
/// banyak layar yang kepasang, dan AppBar-nya selalu kelewat) — itu
/// sebabnya ukuran tampilan kelihatan nggak konsisten (ada yang gede ada
/// yang kecil) antar layar di tablet/desktop. JANGAN panggil fungsi ini
/// lagi di level body/halaman individual, nanti dobel scale.
Widget scaleForWideScreen(Widget mobileChild) {
  return LayoutBuilder(
    builder: (context, constraints) {
      double scale = 1;
      if (constraints.maxWidth >= 1200) {
        scale = 3;
      } else if (constraints.maxWidth >= 780) {
        scale = 2;
      }

      if (scale == 1) return mobileChild;

      final virtualWidth = constraints.maxWidth / scale;
      final double virtualHeight = constraints.maxHeight.isFinite
          ? constraints.maxHeight / scale
          : constraints.maxHeight;

      // PENTING: `ClipRect` langsung ngebungkus `Transform.scale` itu bug —
      // ukuran layout `Transform` ikut ukuran child SEBELUM di-scale
      // (virtualWidth x virtualHeight, yang kecil), jadi `ClipRect` motong
      // balik hasil scale-nya ke ukuran kecil itu juga (cuma pojok kiri-atas
      // yang ke-render, sisanya ke-clip/kosong).
      // Fix-nya pakai `OverflowBox`: dia bikin box seukuran layar ASLI
      // (constraints.maxWidth x maxHeight) tapi ngasih child-nya (yang di
      // dalam Transform) constraint virtual yang kecil TANPA ngeclip hasil
      // paint-nya yang udah di-scale gede. Alignment topCenter di dua-duanya
      // (OverflowBox & Transform) dipasang biar titik jangkarnya nyambung:
      // hasil akhirnya pas mengisi penuh layar asli, center secara
      // horizontal, nempel ke atas.
      return SizedBox(
        width: constraints.maxWidth,
        height: constraints.maxHeight.isFinite ? constraints.maxHeight : null,
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minWidth: 0,
          maxWidth: virtualWidth,
          minHeight: 0,
          maxHeight: virtualHeight,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: virtualWidth,
              height: virtualHeight,
              child: mobileChild,
            ),
          ),
        ),
      );
    },
  );
}

Widget buildTransactionTile(
  BuildContext context,
  Map tx, {
  String? txId,
  bool isLast = false,
  String namaNasabah = '',
  String kelasNasabah = '',
}) {
  final bool isSetor = tx['tipe'] == 'Setor';
  final String title = isSetor
      ? 'Setor ${formatKg((tx['berat_kg'] as num?) ?? 0)} ${tx['kategori'] ?? ''}'.trim()
      : 'Penarikan Tunai';

  final String dateStr = formatTanggalJam(tx['tanggal']);

  return GestureDetector(
    onTap: () {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TransactionDetailPage.fromMap(
            tx,
            txId: txId,
            namaNasabah: namaNasabah,
            kelasNasabah: kelasNasabah,
          ),
        ),
      );
    },
    child: Container(
      margin: EdgeInsets.only(bottom: isLast ? 0 : 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor:
            isSetor ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
        child: Icon(
          isSetor ? Icons.arrow_downward : Icons.arrow_upward,
          color: isSetor ? Colors.green : Colors.red,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
      ),
      subtitle: Text(dateStr, style: const TextStyle(fontSize: 12)),
      trailing: Text(
        '${isSetor ? '+' : '-'} ${formatRupiah(tx['total_rp'] as num?)}',
        style: TextStyle(
          color: isSetor ? Colors.green : Colors.red,
          fontWeight: FontWeight.bold,
          fontSize: 13.5,
        ),
      ),
    ),
  ),
);
}

Widget buildEmptyRiwayat({String message = 'Belum ada transaksi.'}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 28),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.receipt_long_outlined, size: 36, color: Colors.grey.shade400),
        const SizedBox(height: 10),
        Text(message, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
      ],
    ),
  );
}

/// Halaman riwayat transaksi penuh — dibuka dari tombol "Lihat Semua" di
/// dashboard, karena dashboard sendiri cuma nampilin 4 transaksi terakhir.
class RiwayatLengkapPage extends StatelessWidget {
  final String uid;

  // Nama & kelas dibawa dari dashboard: node transaksi tidak menyimpan
  // identitas nasabah, padahal bukti PDF butuh itu.
  final String namaNasabah;
  final String kelasNasabah;

  const RiwayatLengkapPage({
    Key? key,
    required this.uid,
    this.namaNasabah = '',
    this.kelasNasabah = '',
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.latar,
      appBar: AppBar(title: const Text('Riwayat Transaksi')),
      body: SafeArea(
        child: _RtdbBuilder(
          path: 'transactions/$uid',
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(
                    'Gagal memuat riwayat transaksi.\n${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ),
              );
            }

            if (!snapshot.hasData || snapshot.data == null) {
              return Padding(
                padding: const EdgeInsets.all(18),
                child: buildEmptyRiwayat(),
              );
            }

            final Map<dynamic, dynamic> txns =
                Map<dynamic, dynamic>.from(snapshot.data as Map);
            final txList = txns.entries
                .map((e) => MapEntry(
                      e.key.toString(),
                      Map<String, dynamic>.from(e.value as Map),
                    ))
                .toList();

            if (txList.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(18),
                child: buildEmptyRiwayat(),
              );
            }

            txList.sort((a, b) => (b.value['tanggal'] ?? '')
                .toString()
                .compareTo((a.value['tanggal'] ?? '').toString()));

            return ListView.builder(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
                itemCount: txList.length,
                itemBuilder: (context, index) {
                  return buildTransactionTile(
                    context,
                    txList[index].value,
                    txId: txList[index].key,
                    isLast: index == txList.length - 1,
                    namaNasabah: namaNasabah,
                    kelasNasabah: kelasNasabah,
                  );
                },
              );
          },
        ),
      ),
    );
  }
}

// ============================================================================
// Google Sign-In (paket versi 7+) — API-nya pakai singleton + inisialisasi
// async sekali di awal, beda dari versi lama yang langsung `GoogleSignIn()`.
// Semua layar (Login, NotRegistered, Dashboard) pakai helper yang sama ini
// biar gak initialize() berkali-kali.
//
// PENTING soal WEB:
// Di web, `authenticate()` TIDAK didukung (akan throw UnsupportedError).
// Google Identity Services (GIS) mewajibkan tombol resmi yang di-render
// lewat `renderButton()`, bukan tombol custom yang manggil authenticate()
// secara programatik. Makanya LoginPage di bawah punya dua jalur:
//   - kIsWeb == true  -> pakai gsi_web renderButton() + dengarkan
//     authenticationEvents untuk tau kapan user berhasil login.
//   - selain web       -> pakai authenticate() seperti biasa.
//
// Selain itu, WAJIB ada meta tag client ID di web/index.html:
//   <meta name="google-signin-client_id"
//         content="ISI_WEB_CLIENT_ID.apps.googleusercontent.com">
// Ambil "Web client ID" dari Firebase Console -> Authentication ->
// Sign-in method -> Google -> Web SDK configuration.
// ============================================================================

final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
Future<void>? _googleSignInInitFuture;

Future<void> ensureGoogleSignInInitialized() {
  // WAJIB DIISI untuk web: ambil "Web client ID" dari Firebase Console ->
  // Authentication -> Sign-in method -> Google -> Web SDK configuration.
  // Tanpa ini, web akan throw "ClientID not set" (persis error yang kamu
  // lihat), karena GIS SDK di web butuh clientId eksplisit — beda dari
  // Android/iOS yang baca dari google-services.json / GoogleService-Info.plist.
  //
  // TODO: kalau nanti login Google di Android gagal dengan error soal
  // audience/ID token gak valid, isi serverClientId di bawah juga pakai
  // Web client ID yang sama.
  _googleSignInInitFuture ??= _googleSignIn.initialize(
    clientId: kIsWeb
        ? '306920049631-h0fn6hitv7u0ls6npqmn9j3rt7e0ubil.apps.googleusercontent.com'
        : null,
    // serverClientId TIDAK boleh diisi di web (google_sign_in_web akan
    // throw assertion error kalau ini diisi bareng clientId di web).
    // Hanya dibutuhkan di Android/iOS supaya ID token bisa divalidasi
    // Firebase Auth.
    serverClientId: kIsWeb
        ? null
        : '306920049631-h0fn6hitv7u0ls6npqmn9j3rt7e0ubil.apps.googleusercontent.com',
  );
  return _googleSignInInitFuture!;
}

Future<void> signOutGoogleAndFirebase() async {
  await ensureGoogleSignInInitialized();
  await _googleSignIn.signOut();
  await FirebaseAuth.instance.signOut();
  await RtdbFailover.instance.signOutSecondary();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Di mode release, widget yang error diganti kotak abu-abu polos yang
  // tingginya tak terbatas kalau ada di dalam list (bikin layar abu-abu
  // terus waktu di-scroll). Ganti dengan kotak kecil yang menampilkan
  // pesan errornya, supaya (a) layar tidak rusak total, (b) penyebab
  // aslinya kelihatan.
  ErrorWidget.builder = (FlutterErrorDetails details) => Material(
        color: Colors.red.shade50,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Text(
            'Terjadi error: ${details.exceptionAsString()}',
            style: const TextStyle(fontSize: 11, color: Colors.red),
          ),
        ),
      );
  // firebase_core belum ada implementasi native di Linux desktop, jadi
  // di-skip di sana — nasabah dashboard fallback ke REST (lihat lib/rest/).
  if (!isLinuxDesktop) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await RtdbFailover.instance.init();
  }
  await LocalNotifications.init();

  runApp(
    // DevicePreview cuma berguna buat ngintip UI di Linux desktop (tempat
    // login Google/Firebase di-skip dan dashboard dibuka pakai demo UID
    // statis, lihat AuthGate di bawah). Di build sungguhan (Android/iOS/web)
    // ini WAJIB mati, karena kalau enabled: true, app beneran ke-bungkus
    // frame device-picker DevicePreview alih-alih tampil normal.
    DevicePreview(
      enabled: isLinuxDesktop,
      builder: (context) => const BankSampahApp(),
    ),
  );
}

class BankSampahApp extends StatelessWidget {
  const BankSampahApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const bgColor = AppColors.latar;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      useInheritedMediaQuery: true,
      locale: DevicePreview.locale(context),
      // Digabung: DevicePreview bungkus dulu (device-picker frame pas
      // preview di Linux desktop), baru hasilnya di-scale rata pakai
      // scaleForWideScreen supaya SEMUA layar (termasuk AppBar) dapet
      // ukuran zoom yang sama persis berdasarkan lebar layar asli —
      // bukan cuma sebagian layar kayak sebelumnya.
      builder: (context, child) {
        final devicePreviewChild = DevicePreview.appBuilder(context, child);
        return scaleForWideScreen(devicePreviewChild ?? const SizedBox());
      },
      title: 'Resik For School',
      theme: ThemeData(
        primarySwatch: Colors.green,
        scaffoldBackgroundColor: bgColor,
        appBarTheme: const AppBarTheme(
          backgroundColor: bgColor,
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.black87),
          titleTextStyle: TextStyle(
            color: Colors.black87,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

// ============================================================================
// AuthGate — nentuin layar mana yang tampil berdasar status login.
//
// - Linux desktop: firebase_core belum ada implementasi native, jadi login
//   Google di-skip dan langsung ke _PinGate pakai UID demo contoh (sama
//   seperti perilaku lama, cuma sekarang tetap lewat _PinGate juga supaya
//   alur setup PIN bisa dipreview di desktop). REST fallback (RtdbRest)
//   diasumsikan cuma dipakai untuk preview lokal di mesin dev, bukan build
//   produksi.
// - Android/iOS/Web: alur normal → belum login -> LoginPage, sudah login
//   tapi emailnya belum didaftarkan admin -> NotRegisteredPage, sudah
//   terdaftar tapi belum atur PIN -> SetupPinPage, sudah atur PIN ->
//   NasabahDashboard dengan UID hasil lookup email_to_uid.
// ============================================================================

class AuthGate extends StatefulWidget {
  const AuthGate({Key? key}) : super(key: key);

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  // Di Linux desktop gak ada Firebase asli, jadi tombol login di
  // LoginPage cuma dipakai buat "lewatin" layar ini secara demo,
  // supaya tampilan login-nya tetap kelihatan dulu sebelum ke dashboard.
  bool _demoLoggedIn = false;

  @override
  Widget build(BuildContext context) {
    if (isLinuxDesktop) {
      if (!_demoLoggedIn) {
        return LoginPage(
          onDemoLogin: () => setState(() => _demoLoggedIn = true),
        );
      }
      const demoUid = '-P1GTshXiPzrUlY_PNDl';
      return const _PinGate(uid: demoUid);
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = authSnapshot.data;
        if (user == null) {
          return const LoginPage();
        }

        return _NasabahLookup(user: user);
      },
    );
  }
}

/// Cari `users/{uid}` yang emailnya cocok dengan akun Google yang lagi
/// login, lewat lookup table `email_to_uid` yang diisi admin saat
/// mendaftarkan nasabah baru.
class _NasabahLookup extends StatelessWidget {
  final User user;
  const _NasabahLookup({required this.user});

  Future<String?> _lookupUid() async {
    final email = user.email;
    if (email == null || email.isEmpty) return null;
    final key = sanitizeEmailKey(email);
    final v = await RtdbFailover.instance.getOnce('email_to_uid/$key');
    return v as String?;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _lookupUid(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final uid = snapshot.data;
        if (uid == null) {
          return const NotRegisteredPage();
        }

        return _PinGate(uid: uid);
      },
    );
  }
}

// ============================================================================
// _PinGate — nasabah WAJIB punya PIN transaksi sebelum bisa buka dashboard.
//
// PIN dulu dibikinkan admin (di-generate random pas daftar nasabah baru,
// lihat web-admin). Sekarang PIN cuma boleh muncul kalau nasabah sendiri
// yang mengatur lewat aplikasi mobile ini — `users/{uid}/pin` dibiarkan
// kosong sampai nasabah mengisinya di SetupPinPage.
//
// Dengerin `users/{uid}/pin` secara live (bukan cuma sekali baca) supaya:
//  - Begitu nasabah selesai simpan PIN, otomatis pindah ke NasabahDashboard
//    tanpa perlu restart/navigasi manual.
//  - Kalau admin suatu saat reset PIN nasabah dari web-admin (jadi kosong
//    lagi), aplikasi yang lagi kebuka otomatis balik minta setup ulang.
// ============================================================================

class _PinGate extends StatelessWidget {
  final String uid;
  const _PinGate({required this.uid});

  bool _hasPin(dynamic rawPin) =>
      rawPin != null && rawPin.toString().trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return _RtdbBuilder(
      path: 'users/$uid/pin',
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Gagal memuat status PIN nasabah.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.negatif),
                ),
              ),
            ),
          );
        }

        if (!_hasPin(snapshot.data)) {
          return SetupPinPage(
            uid: uid,
            onSubmit: (u, pin) => writeRtdb('users/$u/pin', pin),
            onSignOut: signOutGoogleAndFirebase,
          );
        }

        return NasabahDashboard(uid: uid);
      },
    );
  }
}

// ============================================================================
// LoginPage — tombol "Login dengan Google" doang, gak ada password.
//
// Dua jalur login:
//  - Web: pakai tombol resmi Google (renderButton) + dengarkan
//    `authenticationEvents` untuk tau kapan user selesai login.
//  - Non-web (Android/iOS/dst): pakai `authenticate()` langsung dari
//    tombol custom seperti sebelumnya.
// ============================================================================

class LoginPage extends StatefulWidget {
  // Kalau diisi (dipakai khusus preview Linux desktop, lihat AuthGate),
  // tombol login gak nyoba Google Sign-In beneran — cuma manggil ini buat
  // lanjut ke layar berikutnya, biar halaman login-nya tetap kelihatan
  // dulu sebelum masuk dashboard demo.
  final VoidCallback? onDemoLogin;

  const LoginPage({Key? key, this.onDemoLogin}) : super(key: key);

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _loading = false;
  bool _initialized = false;
  String? _error;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _authEventsSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (widget.onDemoLogin != null) {
      // Mode preview Linux desktop: gak perlu inisialisasi Google
      // Sign-In beneran, cukup tandai siap supaya tombol demo muncul.
      if (mounted) setState(() => _initialized = true);
      return;
    }

    try {
      await ensureGoogleSignInInitialized();

      if (kIsWeb) {
        // Di web, hasil login gak balik lewat return value seperti
        // authenticate(), tapi lewat stream event ini. Di sinilah kita
        // tangkap kapan user berhasil (atau gagal) login lewat tombol
        // renderButton() di bawah.
        _authEventsSub = _googleSignIn.authenticationEvents.listen(
          _handleAuthEvent,
          onError: (Object e) {
            if (mounted) {
              setState(() {
                _error = 'Gagal login. Coba lagi.\n$e';
                _loading = false;
              });
            }
          },
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Gagal inisialisasi Google Sign-In.\n$e';
        });
      }
    } finally {
      if (mounted) setState(() => _initialized = true);
    }
  }

  Future<void> _handleAuthEvent(GoogleSignInAuthenticationEvent event) async {
    if (event is! GoogleSignInAuthenticationEventSignIn) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final googleUser = event.user;
      final idToken = googleUser.authentication.idToken;
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      await FirebaseAuth.instance.signInWithCredential(credential);
      RtdbFailover.instance.signInSecondary(credential).ignore();
      // Sisanya ditangani AuthGate/authStateChanges.
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Gagal login ke Firebase.\n$e';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Jalur non-web: tombol custom yang langsung memicu authenticate().
  Future<void> _signInWithGoogleNonWeb() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ensureGoogleSignInInitialized();
      final googleUser = await _googleSignIn.authenticate();
      final googleAuth = googleUser.authentication; // sinkron di v7
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
      RtdbFailover.instance.signInSecondary(credential).ignore();
      // Sisanya ditangani AuthGate/authStateChanges.
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled) {
        setState(() {
          _error = 'Gagal login. Cek koneksi internet lalu coba lagi.\n$e';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Gagal login. Cek koneksi internet lalu coba lagi.\n$e';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _authEventsSub?.cancel();
    super.dispose();
  }

  Widget _buildSignInButton() {
    if (!_initialized) {
      return const SizedBox(
        height: 52,
        child: Center(
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 2.4,
          ),
        ),
      );
    }

    if (widget.onDemoLogin != null) {
      // Mode preview Linux desktop: gak ada Firebase asli, jadi tombol
      // ini cuma lanjut ke layar berikutnya.
      return _GradientLoginButton(onPressed: widget.onDemoLogin!);
    }

    if (kIsWeb) {
      // Tombol resmi dari Google Identity Services. Wajib pakai ini di
      // web karena authenticate() custom gak didukung di sana.
      final button = tryRenderGoogleSignInButton();
      if (button != null) {
        return button;
      }
      // Fallback kalau somehow plugin web-nya gak terdeteksi.
      return const Text(
        'Google Sign-In tidak tersedia di platform ini.',
        style: TextStyle(color: AppColors.negatif),
      );
    }

    return _GradientLoginButton(onPressed: _signInWithGoogleNonWeb);
  }

  @override
  Widget build(BuildContext context) {
    // Hijau terang yang sama kayak kartu saldo di beranda
    // (_buildBalanceCard: Colors.green -> Colors.teal), bukan hijau
    // gelap AppColors.hijau/hijauGelap, biar konsisten sama tampilan app.
    const brandGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Colors.green, Colors.teal],
    );

    return Scaffold(
      backgroundColor: Colors.teal.shade700,
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(decoration: BoxDecoration(gradient: brandGradient)),
          ),
          // Dekorasi lingkaran translucent + pola daun samar biar gak polos.
          Positioned(
            top: -70,
            left: -50,
            child: _decoCircle(190, Colors.white.withOpacity(0.10)),
          ),
          Positioned(
            top: 60,
            right: -40,
            child: _decoCircle(90, Colors.white.withOpacity(0.08)),
          ),
          Positioned(
            bottom: -80,
            right: -60,
            child: _decoCircle(230, Colors.white.withOpacity(0.08)),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                // ---- Bagian atas: logo & judul di atas latar hijau ----
                Expanded(
                  flex: 5,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.18),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'assets/images/logo.png',
                            height: 76,
                            width: 76,
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Resik',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'FOR SCHOOLING',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // ---- Bagian bawah: kartu putih dengan tepi gelombang ----
                Expanded(
                  flex: 7,
                  child: ClipPath(
                    clipper: _LoginCardClipper(),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(28, 44, 28, 28),
                      color: Colors.white,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 4,
                                height: 22,
                                decoration: BoxDecoration(
                                  gradient: brandGradient,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'Selamat Datang',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  color: AppColors.teksRedup,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          RichText(
                            text: TextSpan(
                              style: const TextStyle(
                                fontSize: 25,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                                height: 1.2,
                              ),
                              children: [
                                const TextSpan(text: 'Bank Sampah '),
                                TextSpan(
                                  text: 'Nasabah',
                                  style: TextStyle(color: Colors.green.shade700),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Masuk pakai akun Google yang sudah\ndidaftarkan ke Admin sekolah.',
                            style: TextStyle(
                              color: AppColors.teksRedup,
                              height: 1.45,
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(height: 30),
                          _loading
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 14),
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      color: Colors.green,
                                    ),
                                  ),
                                )
                              : _buildSignInButton(),
                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.negatif.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  color: AppColors.negatif,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          ],
                          const Spacer(),
                          Center(
                            child: Text(
                              'Resik For Schooling © ${DateTime.now().year}',
                              style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _decoCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

/// Tombol login gradasi hijau->teal senada kartu saldo di beranda, dengan
/// ikon dalam lingkaran putih supaya kelihatan lebih "premium" dibanding
/// ElevatedButton polos.
class _GradientLoginButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _GradientLoginButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onPressed,
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Colors.green, Colors.teal],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.green.withOpacity(0.35),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.login, size: 18, color: Colors.teal),
              ),
              const SizedBox(width: 12),
              const Text(
                'LOGIN DENGAN GOOGLE',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bikin tepi atas kartu putih berbentuk gelombang lembut, biar transisi
/// dari latar hijau ke kartu gak cuma sudut membulat biasa.
class _LoginCardClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    const waveHeight = 34.0;
    path.lineTo(0, waveHeight);
    path.quadraticBezierTo(
      size.width * 0.25,
      -waveHeight * 0.6,
      size.width * 0.5,
      waveHeight * 0.55,
    );
    path.quadraticBezierTo(
      size.width * 0.75,
      waveHeight * 1.7,
      size.width,
      0,
    );
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Ikon celengan babi digambar sendiri (vector, bukan Icons.savings bawaan
/// Material, dan bukan lagi cuma dua lingkaran sederhana) supaya kartu
/// saldo di beranda kelihatan lebih custom & lucu. Versi ini nambahin
/// kuping, moncong dengan lubang hidung, mata, kaki, ekor keriting, dan
/// celah koin di punggung — lebih jelas kebaca sebagai "babi" walau
/// digambar cuma pakai satu warna solid + bayangan tipis.
class PiggyBankIcon extends StatelessWidget {
  final double size;
  final Color color;

  const PiggyBankIcon({Key? key, this.size = 26, this.color = Colors.white})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _PiggyBankPainter(color: color),
    );
  }
}

class _PiggyBankPainter extends CustomPainter {
  final Color color;
  _PiggyBankPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final body = Paint()..color = color;
    final shade = Paint()..color = color.withOpacity(0.42);

    // Badan bulat gemuk khas celengan.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.05, h * 0.28, w * 0.80, h * 0.54),
        Radius.circular(h * 0.28),
      ),
      body,
    );

    // Kuping segitiga di kiri atas badan.
    final ear = Path()
      ..moveTo(w * 0.20, h * 0.24)
      ..lineTo(w * 0.10, h * 0.06)
      ..lineTo(w * 0.32, h * 0.20)
      ..close();
    canvas.drawPath(ear, body);

    // Moncong lonjong di kiri.
    canvas.drawOval(
      Rect.fromLTWH(w * 0.00, h * 0.46, w * 0.26, h * 0.22),
      body,
    );
    // Dua lubang hidung di moncong.
    canvas.drawCircle(Offset(w * 0.07, h * 0.57), w * 0.02, shade);
    canvas.drawCircle(Offset(w * 0.17, h * 0.57), w * 0.02, shade);

    // Mata.
    canvas.drawCircle(Offset(w * 0.34, h * 0.42), w * 0.03, shade);

    // Kaki.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.22, h * 0.78, w * 0.12, h * 0.16),
        Radius.circular(w * 0.03),
      ),
      body,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.60, h * 0.78, w * 0.12, h * 0.16),
        Radius.circular(w * 0.03),
      ),
      body,
    );

    // Ekor keriting di kanan.
    final tail = Path()
      ..moveTo(w * 0.90, h * 0.44)
      ..quadraticBezierTo(w * 0.99, h * 0.38, w * 0.94, h * 0.30)
      ..quadraticBezierTo(w * 0.90, h * 0.24, w * 0.85, h * 0.30);
    canvas.drawPath(
      tail,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.045
        ..strokeCap = StrokeCap.round,
    );

    // Celah koin di punggung.
    canvas.drawLine(
      Offset(w * 0.44, h * 0.30),
      Offset(w * 0.58, h * 0.22),
      Paint()
        ..color = shade.color
        ..strokeWidth = h * 0.045
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _PiggyBankPainter oldDelegate) =>
      oldDelegate.color != color;
}

// ============================================================================
// NotRegisteredPage — akun Google valid tapi belum didaftarkan admin
// sebagai nasabah (belum ada di email_to_uid).
// ============================================================================

class NotRegisteredPage extends StatelessWidget {
  const NotRegisteredPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_off_outlined,
                    size: 56, color: Colors.grey.shade500),
                const SizedBox(height: 16),
                Text(
                  'Akun $email belum terdaftar sebagai nasabah.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Daftar dulu ke Admin Bank Sampah di sekolah, minta email ini dihubungkan ke kartu nasabah kamu.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: () async {
                    await signOutGoogleAndFirebase();
                  },
                  child: const Text('Ganti akun / Keluar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// PengumumanPage — daftar lengkap pengumuman dari admin, realtime. Dibuka
// dari lonceng notifikasi di AppBar dashboard.
// ============================================================================

class PengumumanPage extends StatelessWidget {
  const PengumumanPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.latar,
      appBar: AppBar(
        backgroundColor: AppColors.latar,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text(
          'Pengumuman',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        ),
      ),
      body: _RtdbBuilder(
        path: 'pengumuman',
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = parsePengumumanList(snapshot.data);
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.campaign_outlined,
                      size: 48,
                      color: Colors.grey.withOpacity(0.5),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Belum ada pengumuman.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(18),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final item = items[i];
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.green, Colors.teal],
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.campaign,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            item['judul'] as String,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      item['isi'] as String,
                      style: const TextStyle(
                        color: AppColors.teksRedup,
                        height: 1.45,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      formatTanggalJam(
                        DateTime.fromMillisecondsSinceEpoch(
                          item['created_at'] as int,
                        ),
                      ),
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class NasabahDashboard extends StatefulWidget {
  final String uid;
  const NasabahDashboard({Key? key, required this.uid}) : super(key: key);

  @override
  State<NasabahDashboard> createState() => _NasabahDashboardState();
}

class _NasabahDashboardState extends State<NasabahDashboard> {
  String get firebaseUID => widget.uid;

  // Pakai helper top-level watchRtdb() & formatRupiah() (lihat dekat atas
  // file) — sama-sama dipakai juga oleh RiwayatLengkapPage.
  Stream<dynamic> _watch(String path) => watchRtdb(path);

  // Stream dibuat SEKALI per State (bukan di dalam build). Sebelumnya
  // `_watch(...)` dipanggil di build, jadi tiap rebuild bikin Stream baru
  // -> semua StreamBuilder unsubscribe + subscribe ulang ke Firebase.
  late final Stream<dynamic> _userStream = _watch('users/$firebaseUID');
  late final Stream<dynamic> _pengumumanStream = _watch('pengumuman');
  late final Stream<dynamic> _kategoriStream = _watch('kategori');
  late final Stream<dynamic> _riwayatStream =
      _watch('transactions/$firebaseUID').map((value) {
    if (value is! Map) return value;
    final entries = value.entries.toList()
      ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
    final last4 =
        entries.length > 4 ? entries.sublist(entries.length - 4) : entries;
    return {for (final e in last4) e.key: e.value};
  });

  // Judul pengumuman yang baru saja ditutup (di-dismiss) nasabah, supaya
  // banner yang sama gak langsung muncul lagi selama nasabah masih di
  // halaman dashboard yang sama. Direset kalau pengumuman terbarunya beda.
  String? _dismissedPengumumanKey;

  // Mendengarkan transaksi baru nasabah ini dan menampilkan notifikasi
  // lokal tiap kali ada transaksi tercatat (lihat services/transaction_
  // notifier.dart). Baseline transaksi yang sudah ada diambil begitu
  // start() dipanggil, jadi histori lama tidak ikut memicu notifikasi.
  late final TransactionNotifier _txNotifier = TransactionNotifier(
    uid: firebaseUID,
    watch: watchRtdb,
  );

  @override
  void initState() {
    super.initState();
    _txNotifier.start();
  }

  @override
  void dispose() {
    _txNotifier.dispose();
    super.dispose();
  }

  String _initialsOf(String nama) {
    final words =
        nama.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    final chars = words.take(2).map((w) => w[0].toUpperCase()).join();
    return chars;
  }

  // Mode preview kartu: dibuka saat kartu nasabah di-tahan (long press).
  // Nampilin kartunya lebih besar di halaman penuh, siap buat diunduh
  // sebagai gambar (PNG) atau dicetak — jadi nasabah bisa nyimpen kartunya
  // sendiri kalau butuh cetak fisik atau dibagikan.
  void _openCardPreview(String namaSiswa, String kelas) {
    final String safeName =
        (namaSiswa.trim().isEmpty ? firebaseUID : namaSiswa.trim())
            .replaceAll(RegExp(r'\s+'), '_');
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _CardPreviewPage(
          card: _buildAccessCard(namaSiswa, kelas),
          namaSiswa: namaSiswa,
          fileBaseName: 'kartu-nasabah-$safeName',
        ),
      ),
    );
  }

  // Kartu QR versi besar, dibuka lewat dialog supaya lebih mudah dipindai
  // admin (gak perlu mepetin HP ke QR kecil di dashboard).
  void _showQrDialog(String namaSiswa) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Kartu QR Nasabah',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                namaSiswa,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.green.shade200, width: 2),
                ),
                child: QrImageView(
                  data: firebaseUID,
                  version: QrVersions.auto,
                  size: 220.0,
                  foregroundColor: Colors.black87,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Tunjukkan QR ini ke Admin saat\nmenyetor sampah atau menarik saldo',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.green),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Tutup'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(String? nama) {
    final String firstName = (nama == null || nama.trim().isEmpty)
        ? ''
        : nama.trim().split(RegExp(r'\s+')).first;

    // FIX: title 2-baris dan action icon-button dulu keliatan gak sejajar
    // vertikalnya (title ke-center berdasarkan tinggi teksnya sendiri,
    // sedangkan IconButton punya tap-target minimum 48px yang bikin icon-nya
    // "duduk" di posisi beda). Sekarang title & tiap action sama-sama
    // dibungkus SizedBox setinggi toolbar lalu di-Center manual, jadi
    // titik tengahnya dijamin sama persis berapa pun tinggi toolbar-nya.
    return AppBar(
      titleSpacing: 18,
      elevation: 0,
      toolbarHeight: kToolbarHeight,
      backgroundColor: AppColors.latar,
      title: SizedBox(
        height: kToolbarHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              firstName.isEmpty ? 'Selamat datang' : 'Halo, $firstName',
              style: TextStyle(
                fontSize: 12,
                color: Colors.green.shade700,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 1),
            const Text(
              'Dashboard Nasabah',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
      actions: [
        SizedBox(
          height: kToolbarHeight,
          child: Center(
            child: StreamBuilder<dynamic>(
              stream: _pengumumanStream,
              builder: (context, snapshot) {
                final count = parsePengumumanList(snapshot.data).length;
                return Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_outlined, size: 26),
                      tooltip: 'Pengumuman',
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const PengumumanPage(),
                          ),
                        );
                      },
                    ),
                    if (count > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: Colors.red.shade600,
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: AppColors.latar, width: 1.5),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        if (!isLinuxDesktop)
          SizedBox(
            height: kToolbarHeight,
            child: Center(
              child: IconButton(
                icon: const Icon(Icons.logout, size: 22),
                tooltip: 'Keluar',
                onPressed: () async {
                  await signOutGoogleAndFirebase();
                },
              ),
            ),
          ),
        const SizedBox(width: 6),
      ],
    );
  }

  // Banner pengumuman TERBARU di paling atas isi dashboard (di bawah
  // AppBar), realtime — begitu admin kirim pengumuman baru lewat web,
  // banner ini langsung muncul tanpa nasabah perlu buka lonceng dulu.
  // Bisa ditutup (dismiss); tersembunyi lagi kalau pengumuman terbarunya
  // ganti (pengumuman baru datang).
  Widget _buildPengumumanBanner() {
    return StreamBuilder<dynamic>(
      stream: _pengumumanStream,
      builder: (context, snapshot) {
        final items = parsePengumumanList(snapshot.data);
        if (items.isEmpty) return const SizedBox.shrink();

        final latest = items.first;
        final latestKey = latest['key'] as String;
        if (_dismissedPengumumanKey == latestKey) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PengumumanPage()),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.green, Colors.teal],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.22),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.campaign,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            latest['judul'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            latest['isi'] as String,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        setState(() => _dismissedPengumumanKey = latestKey);
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.close, color: Colors.white70, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // Daftar harga sampah REALTIME — mengambil node `kategori` yang sama
  // persis dipakai admin web buat harga beli per kg. Begitu admin ubah
  // harga di web-admin (menu Kategori), nasabah langsung lihat harga
  // barunya di sini tanpa perlu update aplikasi atau refresh manual.
  Widget _buildHargaSampahSection() {
    return _StickyStreamBuilder(
      stream: _kategoriStream,
      builder: (context, snapshot) {
        final items = parseHargaSampahList(snapshot.data);

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.sell_outlined,
                      size: 16,
                      color: Colors.green.shade700,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Harga Sampah Hari Ini',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: Colors.green.shade600,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Realtime',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (snapshot.hasError && items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Gagal memuat harga sampah.\n${snapshot.error}',
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                )
              else if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Belum ada kategori sampah.',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12.5),
                  ),
                )
              else
                Column(
                  children: List.generate(items.length, (i) {
                    final item = items[i];
                    final isLast = i == items.length - 1;
                    return Padding(
                      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: Colors.teal.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.recycling,
                              size: 17,
                              color: Colors.teal.shade700,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              item['nama'] as String,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            '${formatRupiah(item['harga'] as int)} / kg',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
            ],
          ),
        );
      },
    );
  }

  // Placeholder rapi untuk state kosong/loading/error, dipakai di beberapa
  // tempat biar konsisten tampilannya.
  Widget _buildStateMessage({
    required IconData icon,
    required String message,
    Color color = Colors.grey,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: color.withOpacity(0.6)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: color, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // Kartu nasabah, versi baru: dulu nama/kelas/ID dan kotak QR ditumpuk di
  // atas poster pakai koordinat piksel absolut, dan di layar sempit/rasio
  // aneh itu bikin kotak QR ketiban ilustrasi atau kepotong sudut kartu.
  // Lalu sempat dipisah jadi bar hijau solid di bawah poster — tapi itu
  // nutupin ilustrasinya juga. Sekarang: poster ditampilkan utuh (aspect
  // ratio disamakan dengan ukuran asli gambar, 1004x626, jadi BoxFit.cover
  // gak motong apa pun), dan nama/kelas/ID + QR ditumpuk LANGSUNG di atas
  // poster pakai Stack + Positioned (bukan koordinat piksel absolut, jadi
  // tetap rapi di berbagai ukuran layar). Gak ada lagi blok warna solid;
  // cuma scrim gradasi gelap tipis di bagian bawah biar teksnya kebaca di
  // atas ilustrasi.
  Widget _buildAccessCard(String namaSiswa, String kelas) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.18),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: AspectRatio(
        aspectRatio: 1004 / 626,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/images/kartu_green_technology.png',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
            // Scrim gradasi tipis cuma di bagian bawah, biar teks putih
            // tetap kebaca di atas ilustrasi tanpa nutupin gambarnya.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 92,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0),
                      Colors.black.withOpacity(0.55),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 14,
              bottom: 12,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          namaSiswa,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(
                                color: Colors.black54,
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Kelas $kelas',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12.5,
                            shadows: [
                              Shadow(
                                color: Colors.black54,
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'ID: $firebaseUID',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                            shadows: [
                              Shadow(
                                color: Colors.black54,
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => _showQrDialog(namaSiswa),
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.25),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: QrImageView(
                        data: firebaseUID,
                        version: QrVersions.auto,
                        size: 56,
                        padding: EdgeInsets.zero,
                        foregroundColor: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceCard(int currentBalance) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.green, Colors.teal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Total Saldo Aktif',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 6),
                Text(
                  formatRupiah(currentBalance),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              shape: BoxShape.circle,
            ),
            child: const PiggyBankIcon(size: 26, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<dynamic>(
      stream: _userStream,
      builder: (context, snapshot) {
        final bool isLoading =
            snapshot.connectionState == ConnectionState.waiting;

        // PENTING: cek error dulu sebelum cek data. Tanpa ini, error apa pun
        // (permission-denied dari Firebase Rules, cast gagal, dll) akan
        // ketutup dan cuma keliatan seperti "data tidak ditemukan", padahal
        // penyebabnya beda-beda dan butuh penanganan beda-beda juga.
        if (!isLoading && snapshot.hasError) {
          return Scaffold(
            appBar: _buildAppBar(null),
            body: _buildStateMessage(
              icon: Icons.error_outline,
              message: 'Gagal memuat data nasabah.\n${snapshot.error}',
              color: Colors.red,
            ),
          );
        }

        if (!isLoading && (!snapshot.hasData || snapshot.data == null)) {
          return Scaffold(
            appBar: _buildAppBar(null),
            body: _buildStateMessage(
              icon: Icons.person_off_outlined,
              message: 'Data nasabah tidak ditemukan.',
            ),
          );
        }

        String namaSiswa = '';
        String kelas = '-';
        int currentBalance = 0;

        if (!isLoading) {
          final data = Map<dynamic, dynamic>.from(snapshot.data as Map);
          namaSiswa = data['nama'] ?? 'Tanpa Nama';
          kelas = data['kelas'] ?? '-';
          // FIX: jangan `as int` langsung. Angka yang ditulis dari web admin
          // (JavaScript) bisa kesimpen sebagai double gara-gara floating
          // point (mis. hasil kali berat_kg desimal x harga -> 300.00000000000006),
          // sehingga `as int` akan throw dan bikin widget ini gagal render
          // (keliatan seperti "tidak ada data" di HP).
          currentBalance = ((data['saldo_terakhir'] ?? 0) as num).round();
        }

        return Scaffold(
          appBar: _buildAppBar(isLoading ? null : namaSiswa),
          body: isLoading
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(
                  child: _buildDashboardSingleColumn(
                    namaSiswa,
                    kelas,
                    currentBalance,
                  ),
                ),
        );
      },
    );
  }

  // Header "Riwayat Terakhir" + tombol "Lihat Semua".
  Widget _buildRiwayatHeader(
    BuildContext context,
    String namaSiswa,
    String kelas,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildSectionHeader('Riwayat Terakhir'),
        TextButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RiwayatLengkapPage(
                  uid: firebaseUID,
                  namaNasabah: namaSiswa,
                  kelasNasabah: kelas,
                ),
              ),
            );
          },
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 0),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: Colors.green.shade700,
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Lihat Semua',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(width: 2),
              Icon(Icons.chevron_right, size: 16),
            ],
          ),
        ),
      ],
    );
  }

  // Layout HP (dan tablet sempit < 700px): semuanya turun ke bawah dalam
  // satu ListView, kayak sebelumnya.
  Widget _buildDashboardSingleColumn(
    String namaSiswa,
    String kelas,
    int currentBalance,
  ) {
    // Cuma 6 child, jadi tidak perlu lazy ListView. Dengan Column biasa,
    // StreamBuilder di dalamnya tidak pernah di-dispose/dibuat ulang saat
    // di-scroll (itu pemicu kotak abu-abu sebelumnya).
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildPengumumanBanner(),
        GestureDetector(
          // Tahan kartu buat masuk mode preview (kartu ditampilkan lebih
          // besar, siap diunduh/dicetak). Tap singkat di kotak QR tetap
          // jalan seperti biasa (buka dialog QR besar) karena itu gesture
          // yang beda (tap vs tahan lama).
          onLongPress: () => _openCardPreview(namaSiswa, kelas),
          child: _buildAccessCard(namaSiswa, kelas),
        ),
        const SizedBox(height: 16),
        _buildBalanceCard(currentBalance),
        const SizedBox(height: 22),
        _buildHargaSampahSection(),
        const SizedBox(height: 26),
        _buildRiwayatHeader(context, namaSiswa, kelas),
        const SizedBox(height: 10),
        _buildRiwayatTransaksi(namaSiswa, kelas),
      ],
      ),
    );
  }

  Widget _buildRiwayatTransaksi(String namaSiswa, String kelas) {
    return _StickyStreamBuilder(
      stream: _riwayatStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return _buildStateMessage(
            icon: Icons.error_outline,
            message: 'Gagal memuat riwayat transaksi.\n${snapshot.error}',
            color: Colors.red,
          );
        }

        if (!snapshot.hasData || snapshot.data == null) {
          return _buildEmptyRiwayat();
        }

        final Map<dynamic, dynamic> txns =
            Map<dynamic, dynamic>.from(snapshot.data as Map);
        final txList = txns.entries
            .map((e) => MapEntry(e.key.toString(), Map<String, dynamic>.from(e.value as Map)))
            .toList();

        if (txList.isEmpty) {
          return _buildEmptyRiwayat();
        }

        txList.sort((a, b) => (b.value['tanggal'] ?? '').toString().compareTo((a.value['tanggal'] ?? '').toString()));

        return Column(
          children: List.generate(
            txList.length,
            (index) => buildTransactionTile(
              context,
              txList[index].value,
              txId: txList[index].key,
              isLast: index == txList.length - 1,
              namaNasabah: namaSiswa,
              kelasNasabah: kelas,
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyRiwayat() {
    return buildEmptyRiwayat(message: 'Belum ada transaksi.');
  }
}

// ============================================================================
// Halaman preview kartu (muncul saat kartu di-tahan/long press). Nampilin
// kartu lebih besar dan menyiapkan gambarnya (lewat RepaintBoundary) supaya
// bisa diunduh sebagai PNG atau dibuka di tab baru untuk dicetak.
// ============================================================================

class _CardPreviewPage extends StatefulWidget {
  final Widget card;
  final String namaSiswa;
  final String fileBaseName;

  const _CardPreviewPage({
    required this.card,
    required this.namaSiswa,
    required this.fileBaseName,
  });

  @override
  State<_CardPreviewPage> createState() => _CardPreviewPageState();
}

class _CardPreviewPageState extends State<_CardPreviewPage> {
  final GlobalKey _boundaryKey = GlobalKey();
  bool _isBusy = false;

  Future<Uint8List?> _capturePng() async {
    try {
      final boundary = _boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;
      // pixelRatio 3x biar hasil gambarnya tetap tajam waktu dicetak/di-zoom,
      // bukan cuma sesuai resolusi layar HP.
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _handleDownload() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    final bytes = await _capturePng();
    if (!mounted) return;
    setState(() => _isBusy = false);
    if (bytes == null) {
      _showMessage('Gagal menyiapkan gambar kartu. Coba lagi.');
      return;
    }
    final fileName = '${widget.fileBaseName}.png';
    // Coba share sheet asli duluan (WA, Telegram, dll) — didukung di
    // Android/iOS lewat share_plus, dan di browser HP yang support Web
    // Share API. Baru kalau platform-nya beneran gak bisa (browser
    // desktop lama), jatuh ke unduh biasa / pesan screenshot.
    if (canShareFile(bytes, fileName, mimeType: 'image/png')) {
      final shared = await shareFile(
        bytes,
        fileName,
        mimeType: 'image/png',
        title: 'Kartu Nasabah',
        text: 'Kartu nasabah ${widget.namaSiswa} — Resik For School',
      );
      if (!mounted) return;
      if (shared) {
        _showMessage('Kartu berhasil dibagikan.');
      }
      // Kalau shared == false, anggap user sengaja batal di share
      // sheet — gak usah fallback unduh otomatis atau kasih pesan
      // error, biar gak kesan aneh.
      return;
    }
    if (canDownloadDirectly) {
      downloadPngBytes(bytes, fileName);
      _showMessage('Kartu berhasil diunduh.');
    } else {
      _showMessage(
        'Bagikan/unduh langsung belum didukung di platform ini. Untuk '
        'sekarang, screenshot layar ini buat menyimpan kartunya.',
      );
    }
  }

  Future<void> _handlePrint() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    final bytes = await _capturePng();
    if (!mounted) return;
    setState(() => _isBusy = false);
    if (bytes == null) {
      _showMessage('Gagal menyiapkan gambar kartu. Coba lagi.');
      return;
    }
    printPngBytes(bytes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Latar disamakan dengan halaman lain. Sebelumnya halaman ini pakai
      // hijau tua #0A3C19 yang tidak dipakai di layar mana pun lagi,
      // sementara judul AppBar-nya tetap hitam karena titleTextStyle dari
      // ThemeData menang atas foregroundColor — hasilnya teks hitam di atas
      // hijau tua.
      backgroundColor: AppColors.latar,
      appBar: AppBar(
        title: const Text('Kartu Nasabah'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            children: [
              Text(
                widget.namaSiswa,
                style: const TextStyle(
                  color: AppColors.hijau,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Kartu siap dibagikan — kirim ke WhatsApp atau simpan '
                'sebagai gambar.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.teksRedup, fontSize: 12.5),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      // Panel hijau tipis di belakang kartu: memberi bingkai
                      // supaya ilustrasi kartu tidak mengambang di latar
                      // kosong, tanpa ikut terbawa ke hasil PNG (RepaintBoundary
                      // hanya membungkus kartunya).
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.hijauMuda,
                          borderRadius: BorderRadius.circular(26),
                        ),
                        child: RepaintBoundary(
                          key: _boundaryKey,
                          child: widget.card,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isBusy ? null : _handleDownload,
                      icon: _isBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.ios_share_rounded),
                      label: const Text('Bagikan'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.hijau,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  // Cetak (buka tab baru buat dialog print browser) cuma
                  // masuk akal di web — di Android/iOS gak ada tab browser
                  // buat dibuka.
                  if (kIsWeb) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isBusy ? null : _handlePrint,
                        icon: const Icon(Icons.print_rounded),
                        label: const Text('Cetak'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.hijau,
                          side: const BorderSide(color: AppColors.hijau),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
