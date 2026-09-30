import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../firebase_options.dart';

/// Realtime Database REST + SSE API biasa — dipakai di platform yang belum
/// ada implementasi native firebase_database (Linux desktop). Asumsinya
/// rules database public read (tanpa token auth, karena app ini juga
/// nggak ada login).
class RtdbRest {
  static String get _databaseUrl =>
      DefaultFirebaseOptions.currentPlatform.databaseURL!;

  /// Setara `ref.child(path).onValue` — stream nilai live di [path],
  /// gabungin event `put`/`patch` dari SSE jadi snapshot terbaru.
  /// Auto-reconnect kalau koneksi putus.
  static Stream<dynamic> watch(String path) {
    return Stream.multi((controller) async {
      var cancelled = false;
      http.Client? activeClient;
      controller.onCancel = () {
        cancelled = true;
        activeClient?.close();
      };

      dynamic root;
      while (!cancelled) {
        final client = http.Client();
        activeClient = client;
        try {
          final request = http.Request(
            'GET',
            Uri.parse('$_databaseUrl/$path.json'),
          );
          request.headers['Accept'] = 'text/event-stream';
          final response = await client.send(request);
          if (response.statusCode < 200 || response.statusCode >= 300) {
            final body = await response.stream.bytesToString();
            throw StateError(
              'Realtime Database REST gagal (${response.statusCode}): $body',
            );
          }
          var buffer = '';
          await for (final chunk in response.stream.transform(utf8.decoder)) {
            buffer += chunk;
            while (buffer.contains('\n\n')) {
              final splitIndex = buffer.indexOf('\n\n');
              final rawEvent = buffer.substring(0, splitIndex);
              buffer = buffer.substring(splitIndex + 2);

              String? eventType;
              String? dataLine;
              for (final line in rawEvent.split('\n')) {
                if (line.startsWith('event:')) {
                  eventType = line.substring(6).trim();
                }
                if (line.startsWith('data:')) {
                  dataLine = line.substring(5).trim();
                }
              }
              if (eventType != 'put' && eventType != 'patch') continue;
              if (dataLine == null) continue;
              try {
                final decoded = jsonDecode(dataLine) as Map<String, dynamic>;
                root = _applyEvent(
                  root,
                  eventType!,
                  decoded['path'] as String,
                  decoded['data'],
                );
                controller.add(root);
              } catch (_) {
                // keep-alive/chunk aneh dari SSE, abaikan
              }
            }
          }
        } catch (e) {
          controller.addError(e);
        } finally {
          client.close();
        }
        if (cancelled) break;
        await Future.delayed(const Duration(seconds: 2));
      }
    });
  }

  /// Setara `ref.child(path).set(value)` — nulis nilai ke [path] lewat REST
  /// biasa (dipakai di platform yang belum ada implementasi native
  /// firebase_database, misalnya Linux desktop). Cuma dipakai untuk
  /// preview lokal di mesin dev, bukan build produksi — lihat komentar di
  /// atas kelas ini.
  static Future<void> put(String path, dynamic value) async {
    final response = await http.put(
      Uri.parse('$_databaseUrl/$path.json'),
      body: jsonEncode(value),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Realtime Database REST PUT gagal (${response.statusCode}): '
        '${response.body}',
      );
    }
  }

  static dynamic _applyEvent(
    dynamic root,
    String eventType,
    String path,
    dynamic data,
  ) {
    final segments =
        path == '/' ? const <String>[] : path.substring(1).split('/');
    if (eventType == 'put') {
      return _setAtPath(root, segments, data);
    }
    final current = _getAtPath(root, segments);
    final merged = _shallowMerge(current, data as Map);
    return _setAtPath(root, segments, merged);
  }

  static dynamic _getAtPath(dynamic node, List<String> segments) {
    if (segments.isEmpty) return node;
    if (node is! Map) return null;
    return _getAtPath(node[segments.first], segments.sublist(1));
  }

  static dynamic _setAtPath(
    dynamic node,
    List<String> segments,
    dynamic value,
  ) {
    if (segments.isEmpty) return value;
    final map = Map<String, dynamic>.from(node is Map ? node : const {});
    final key = segments.first;
    final childValue = _setAtPath(map[key], segments.sublist(1), value);
    if (childValue == null) {
      map.remove(key);
    } else {
      map[key] = childValue;
    }
    return map;
  }

  static Map<String, dynamic> _shallowMerge(dynamic current, Map data) {
    final merged =
        Map<String, dynamic>.from(current is Map ? current : const {});
    data.forEach((k, v) {
      final key = k.toString();
      if (v == null) {
        merged.remove(key);
      } else {
        merged[key] = v;
      }
    });
    return merged;
  }
}
