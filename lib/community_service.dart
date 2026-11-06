import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'firebase_config.dart';
import 'models.dart';

/// Radares reportados pelos usuários, compartilhados via Firestore (REST).
/// Radares móveis não expiram sozinhos: a cada 48 h os motoristas que
/// passam pelo local confirmam se ainda está lá (sim = +48 h, não = apaga).
class CommunityService {
  static const checkInterval = Duration(hours: 48);

  /// Filas, acidentes, obras, perigos e polícia somem sozinhos depois de 6 h.
  static const eventLife = Duration(hours: 6);

  List<Radar> _radars = [];

  /// Avisos "este radar não existe mais" da região (1.29.7). Ficam na mesma
  /// coleção, mas com a célula "x…": versões antigas do app não buscam
  /// essas células, então não confundem o aviso com um radar.
  List<(double, double)> removed = [];
  static const removedLife = Duration(days: 90);
  DateTime? _lastFetch;
  double? _lastLat, _lastLon;

  List<Radar> get radars {
    // Tira os avisos que expiraram desde o último download.
    final now = DateTime.now().millisecondsSinceEpoch;
    return List.unmodifiable(_radars.where(
        (r) => !r.isEvent || (r.checkAfter ?? 0) > now));
  }

  /// Radar móvel que já passou do prazo e precisa de confirmação.
  static bool needsCheck(Radar r) =>
      r.type == 'movel' &&
      r.checkAfter != null &&
      r.checkAfter! <= DateTime.now().millisecondsSinceEpoch;

  /// Resposta do motorista: ainda está (mantém +48 h) ou não está (apaga).
  Future<bool> confirm(Radar r, bool stillThere) async {
    if (!communityEnabled || !r.id.startsWith('cm_')) return false;
    final docId = r.id.substring(3);
    final url = '$_base/radars/$docId';
    try {
      if (stillThere) {
        final next = DateTime.now()
            .add(r.isEvent ? eventLife : checkInterval)
            .millisecondsSinceEpoch;
        final res = await http
            .patch(
                Uri.parse('$url?updateMask.fieldPaths=checkAfter'
                    '&key=$firebaseApiKey'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'fields': {
                    'checkAfter': {'integerValue': '$next'}
                  }
                }))
            .timeout(const Duration(seconds: 20));
        if (res.statusCode != 200) return false;
        final i = _radars.indexWhere((x) => x.id == r.id);
        if (i >= 0) {
          _radars[i] = Radar(
            id: r.id,
            lat: r.lat,
            lon: r.lon,
            maxSpeed: r.maxSpeed,
            type: r.type,
            direction: r.direction,
            checkAfter: next,
          );
        }
      } else {
        final res = await http
            .delete(Uri.parse('$url?key=$firebaseApiKey'))
            .timeout(const Duration(seconds: 20));
        if (res.statusCode != 200) return false;
        _radars.removeWhere((x) => x.id == r.id);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  String get _base =>
      'https://firestore.googleapis.com/v1/projects/$firebaseProjectId'
      '/databases/(default)/documents';

  /// Célula de ~11 km usada para buscar só os radares da região.
  static String cellOf(double lat, double lon) =>
      '${(lat * 10).floor()}_${(lon * 10).floor()}';

  static List<String> _cellsAround(double lat, double lon) {
    final la = (lat * 10).floor(), lo = (lon * 10).floor();
    return [
      for (var i = -1; i <= 1; i++)
        for (var j = -1; j <= 1; j++) '${la + i}_${lo + j}'
    ];
  }

  bool needsRefresh(double lat, double lon) {
    if (!communityEnabled) return false;
    if (_lastFetch == null) return true;
    if (DateTime.now().difference(_lastFetch!).inMinutes >= 2) return true;
    return cellOf(lat, lon) != cellOf(_lastLat!, _lastLon!);
  }

  Future<bool> refresh(double lat, double lon) async {
    if (!communityEnabled) return false;
    _lastFetch = DateTime.now();
    _lastLat = lat;
    _lastLon = lon;
    try {
      final body = {
        'structuredQuery': {
          'from': [
            {'collectionId': 'radars'}
          ],
          'where': {
            'fieldFilter': {
              'field': {'fieldPath': 'cell'},
              'op': 'IN',
              'value': {
                'arrayValue': {
                  'values': [
                    for (final c in _cellsAround(lat, lon)) {'stringValue': c},
                    for (final c in _cellsAround(lat, lon)) {'stringValue': 'x$c'},
                  ]
                }
              }
            }
          },
          'limit': 1000,
        }
      };
      final res = await http
          .post(Uri.parse('$_base:runQuery?key=$firebaseApiKey'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return false;
      final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
      _deleteExpired(list);
      final docs = [
        for (final item in list)
          if ((item as Map)['document'] != null)
            _fromDoc((item['document'] as Map).cast<String, dynamic>())
      ].whereType<Radar>();
      final now = DateTime.now().millisecondsSinceEpoch;
      removed = [
        for (final r in docs)
          if (r.type == 'removido' && (r.checkAfter ?? 0) > now) (r.lat, r.lon)
      ];
      _radars = docs.where((r) => r.type != 'removido').toList();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Distância máxima para considerar que é o mesmo radar.
  static const sameRadarMeters = 150.0;

  static double _meters(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final p1 = lat1 * math.pi / 180, p2 = lat2 * math.pi / 180;
    final dp = (lat2 - lat1) * math.pi / 180;
    final dl = (lon2 - lon1) * math.pi / 180;
    final h = math.sin(dp / 2) * math.sin(dp / 2) +
        math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
    return 2 * r * math.asin(math.sqrt(h));
  }

  /// Radar compartilhado já existente a menos de 150 m, no mesmo sentido
  /// (se os dois tiverem sentido conhecido). Serve para não duplicar.
  /// Com [type] de aviso (fila, obra…), só compara com avisos do mesmo tipo;
  /// sem ele, só com radares.
  Radar? nearby(double lat, double lon, double? direction, {String? type}) {
    Radar? best;
    var bestD = sameRadarMeters;
    for (final r in _radars) {
      if (type != null ? r.type != type : r.isEvent) continue;
      final d = _meters(lat, lon, r.lat, r.lon);
      if (d > bestD) continue;
      if (direction != null && r.direction != null) {
        final diff = (direction - r.direction!).abs() % 360;
        if ((diff > 180 ? 360 - diff : diff) > 60) continue;
      }
      best = r;
      bestD = d;
    }
    return best;
  }

  Future<bool> report({
    required double lat,
    required double lon,
    required bool mobile,
    int? maxSpeed,
    double? direction,
    String? event,
  }) async {
    if (!communityEnabled) return false;
    final now = DateTime.now();
    // Radar móvel: data da próxima confirmação. Aviso: quando ele some.
    final checkAfter = event != null
        ? now.add(eventLife).millisecondsSinceEpoch
        : mobile
            ? now.add(checkInterval).millisecondsSinceEpoch
            : 0;
    final fields = <String, dynamic>{
      'lat': {'doubleValue': lat},
      'lon': {'doubleValue': lon},
      'cell': {'stringValue': cellOf(lat, lon)},
      'type': {'stringValue': event ?? (mobile ? 'movel' : 'comunidade')},
      'createdAt': {'integerValue': '${now.millisecondsSinceEpoch}'},
      'checkAfter': {'integerValue': '$checkAfter'},
      if (maxSpeed != null) 'maxSpeed': {'integerValue': '$maxSpeed'},
      if (direction != null) 'direction': {'doubleValue': direction},
    };
    try {
      final res = await http
          .post(Uri.parse('$_base/radars?key=$firebaseApiKey'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'fields': fields}))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return false;
      final doc = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
      final r = _fromDoc(doc.cast<String, dynamic>());
      if (r != null) _radars.add(r);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------- Parks adicionados pelos motoristas (1.29.30) ----------
  //
  // Ficam na mesma coleção `radars` (as regras já publicadas aceitam), com
  // type "park_privado", "park_free" ou "park_zona". O nome vai no campo
  // cell como "p|Nome" (as regras publicadas não aceitam um campo novo, e
  // cell de park não é usado na busca de radares). Valem 2 anos.

  static const parkTypes = ['park_privado', 'park_free', 'park_zona'];
  static const parkLife = Duration(days: 730);

  /// Todos os parks dos motoristas (são poucos: baixa todos de uma vez).
  Future<List<(String, double, double, String, String)>?> fetchParks() async {
    if (!communityEnabled) return null;
    try {
      final body = {
        'structuredQuery': {
          'from': [
            {'collectionId': 'radars'}
          ],
          'where': {
            'fieldFilter': {
              'field': {'fieldPath': 'type'},
              'op': 'IN',
              'value': {
                'arrayValue': {
                  'values': [for (final t in parkTypes) {'stringValue': t}]
                }
              }
            }
          },
          'limit': 5000,
        }
      };
      final res = await http
          .post(Uri.parse('$_base:runQuery?key=$firebaseApiKey'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) return null;
      final out = <(String, double, double, String, String)>[];
      for (final item in jsonDecode(utf8.decode(res.bodyBytes)) as List) {
        final doc = (item as Map)['document'] as Map?;
        if (doc == null) continue;
        final r = _fromDoc(doc.cast<String, dynamic>());
        if (r == null) continue;
        final cell = ((doc['fields'] as Map?)?['cell'] as Map?)?['stringValue']
                ?.toString() ??
            '';
        final name = cell.startsWith('p|') ? cell.substring(2).trim() : '';
        out.add((r.id, r.lat, r.lon, r.type, name));
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  /// Adiciona um park onde você está. [type]: park_privado/park_free/park_zona.
  Future<String?> reportPark(
      double lat, double lon, String type, String name, double? heading) async {
    final n = name.trim();
    if (!communityEnabled) return null;
    final now = DateTime.now();
    final fields = <String, dynamic>{
      'lat': {'doubleValue': lat},
      'lon': {'doubleValue': lon},
      'cell': {
        'stringValue': 'p|${n.length > 60 ? n.substring(0, 60) : n}'
      },
      'type': {'stringValue': type},
      if (heading != null && heading >= 0)
        'direction': {'doubleValue': heading},
      'createdAt': {'integerValue': '${now.millisecondsSinceEpoch}'},
      'checkAfter': {
        'integerValue': '${now.add(parkLife).millisecondsSinceEpoch}'
      },
    };
    try {
      final res = await http
          .post(Uri.parse('$_base/radars?key=$firebaseApiKey'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'fields': fields}))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final name = (jsonDecode(res.body) as Map)['name']?.toString() ?? '';
      return 'cm_${name.split('/').last}';
    } catch (_) {
      return null;
    }
  }

  /// Avisa que o radar [r] não existe mais (vale 90 dias).
  Future<bool> reportRemoved(Radar r) async {
    if (!communityEnabled) return false;
    final now = DateTime.now();
    final fields = <String, dynamic>{
      'lat': {'doubleValue': r.lat},
      'lon': {'doubleValue': r.lon},
      'cell': {'stringValue': 'x${cellOf(r.lat, r.lon)}'},
      'type': {'stringValue': 'removido'},
      'createdAt': {'integerValue': '${now.millisecondsSinceEpoch}'},
      'checkAfter': {
        'integerValue': '${now.add(removedLife).millisecondsSinceEpoch}'
      },
    };
    try {
      final res = await http
          .post(Uri.parse('$_base/radars?key=$firebaseApiKey'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'fields': fields}))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return false;
      removed = [...removed, (r.lat, r.lon)];
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Apaga do Firebase os avisos (fila, acidente, obra, perigo, polícia) com mais
  /// de 6 h. Qualquer celular que baixar a região faz a limpeza; as regras
  /// do Firestore só permitem apagar aviso já vencido.
  void _deleteExpired(List items) {
    const events = {'fila', 'acidente', 'obra', 'perigo', 'policia'};
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final item in items) {
      final doc = (item as Map)['document'] as Map?;
      final f = (doc?['fields'] as Map?);
      if (doc == null || f == null) continue;
      final type = (f['type'] as Map?)?['stringValue']?.toString();
      final raw = (f['checkAfter'] as Map?)?['integerValue'];
      final check = int.tryParse('$raw') ?? 0;
      if (!events.contains(type) || check >= now) continue;
      final name = doc['name']?.toString() ?? '';
      final id = name.split('/').last;
      if (id.isEmpty) continue;
      http
          .delete(Uri.parse('$_base/radars/$id?key=$firebaseApiKey'))
          .timeout(const Duration(seconds: 20))
          .catchError((_) => http.Response('', 0));
    }
  }

  static Radar? _fromDoc(Map<String, dynamic> doc) {
    final f = (doc['fields'] as Map?)?.cast<String, dynamic>();
    if (f == null) return null;
    num? n(String k) {
      final v = f[k] as Map?;
      if (v == null) return null;
      final raw = v['doubleValue'] ?? v['integerValue'];
      return raw is num ? raw : num.tryParse('$raw');
    }

    final lat = n('lat'), lon = n('lon');
    if (lat == null || lon == null) return null;
    final check = n('checkAfter')?.toInt() ?? 0;
    final name = doc['name']?.toString() ?? '';
    final type =
        (f['type'] as Map?)?['stringValue']?.toString() ?? 'comunidade';
    // Aviso de trânsito com mais de 6 h: já expirou, não mostra.
    const events = {'fila', 'acidente', 'obra', 'perigo', 'policia'};
    if (events.contains(type) &&
        check < DateTime.now().millisecondsSinceEpoch) {
      return null;
    }
    return Radar(
      id: 'cm_${name.split('/').last}',
      lat: lat.toDouble(),
      lon: lon.toDouble(),
      maxSpeed: n('maxSpeed')?.toInt(),
      type: type,
      direction: n('direction')?.toDouble(),
      checkAfter: check == 0 ? null : check,
    );
  }
}
