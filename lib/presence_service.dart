import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_config.dart';

/// Quantas pessoas estão com o SpeedGuard conectado agora, no mundo e no
/// país onde você está. Cada aparelho grava um "estou online" na coleção
/// `presence` do Firestore a cada minuto (um documento por aparelho, sem
/// dados pessoais: só o código do país e o horário).
///
/// O tempo é dividido em janelas de 2 minutos ([bucket]). Quem mandou sinal
/// na janela atual ou na anterior conta como conectado; quem fechou o app
/// sai da contagem sozinho em no máximo 4 minutos. A contagem usa a
/// agregação COUNT do Firestore, que custa 1 leitura a cada 1000 aparelhos.
class PresenceService {
  static const beat = Duration(minutes: 1);
  static const _windowMs = 2 * 60 * 1000;

  String? _id;
  int? world; // conectados no mundo
  int? country; // conectados no seu país
  String? countryCode;

  String get _base =>
      'https://firestore.googleapis.com/v1/projects/$firebaseProjectId'
      '/databases/(default)/documents';

  static int _bucket(int ms) => ms ~/ _windowMs;

  Future<String> _deviceId() async {
    if (_id != null) return _id!;
    final p = await SharedPreferences.getInstance();
    var id = p.getString('deviceId');
    if (id == null) {
      const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
      final r = math.Random.secure();
      id = List.generate(20, (_) => chars[r.nextInt(chars.length)]).join();
      await p.setString('deviceId', id);
    }
    return _id = id;
  }

  /// Avisa que este aparelho está conectado (no país [code], se já souber).
  Future<void> ping(String? code) async {
    if (!communityEnabled) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final b = _bucket(now);
    final c = (code ?? '').toLowerCase();
    try {
      final id = await _deviceId();
      await http
          .patch(Uri.parse('$_base/presence/$id?key=$firebaseApiKey'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'fields': {
                  'country': {'stringValue': c},
                  'bucket': {'integerValue': '$b'},
                  'cbucket': {'stringValue': '${c}_$b'},
                  'lastSeen': {'integerValue': '$now'},
                }
              }))
          .timeout(const Duration(seconds: 20));
    } catch (_) {}
  }

  /// Atualiza [world] e [country]. Retorna false se não conseguiu
  /// (sem internet ou regras do Firestore ainda não publicadas).
  Future<bool> refresh(String? code) async {
    if (!communityEnabled) return false;
    final b = _bucket(DateTime.now().millisecondsSinceEpoch);
    final c = (code ?? '').toLowerCase();
    final w = await _count('bucket', [
      {'integerValue': '$b'},
      {'integerValue': '${b - 1}'},
    ]);
    if (w == null) return false;
    int? n;
    if (c.isNotEmpty) {
      n = await _count('cbucket', [
        {'stringValue': '${c}_$b'},
        {'stringValue': '${c}_${b - 1}'},
      ]);
    }
    // Você mesmo sempre conta (o sinal pode ainda estar a caminho).
    world = math.max(w, 1);
    country = n == null ? null : math.max(n, 1);
    countryCode = c.isEmpty ? null : c;
    return true;
  }

  Future<int?> _count(String field, List<Map<String, String>> values) async {
    try {
      final res = await http
          .post(Uri.parse('$_base:runAggregationQuery?key=$firebaseApiKey'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'structuredAggregationQuery': {
                  'structuredQuery': {
                    'from': [
                      {'collectionId': 'presence'}
                    ],
                    'where': {
                      'fieldFilter': {
                        'field': {'fieldPath': field},
                        'op': 'IN',
                        'value': {
                          'arrayValue': {'values': values}
                        }
                      }
                    }
                  },
                  'aggregations': [
                    {'alias': 'n', 'count': {}}
                  ]
                }
              }))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
      for (final item in list) {
        final f = ((item as Map)['result'] as Map?)?['aggregateFields'] as Map?;
        final raw = (f?['n'] as Map?)?['integerValue'];
        if (raw != null) return int.tryParse('$raw');
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Bandeira do país a partir do código ISO ("fr" → 🇫🇷).
  static String flag(String code) => String.fromCharCodes(
      code.toUpperCase().codeUnits.map((u) => u - 0x41 + 0x1F1E6));

  /// 12345 → "12.345".
  static String format(int n) => n
      .toString()
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => '.');
}
