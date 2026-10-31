import 'dart:convert';

import 'package:http/http.dart' as http;

import 'firebase_config.dart';
import 'models.dart';

/// Radares reportados pelos usuários, compartilhados via Firestore (REST).
/// Radares móveis expiram em 3 horas; fixos ficam permanentes.
class CommunityService {
  static const mobileLifetime = Duration(hours: 3);

  List<Radar> _radars = [];
  DateTime? _lastFetch;
  double? _lastLat, _lastLon;

  List<Radar> get radars {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _radars
        .where((r) => r.expiresAt == null || r.expiresAt! > now)
        .toList();
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
                    for (final c in _cellsAround(lat, lon)) {'stringValue': c}
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
      _radars = [
        for (final item in list)
          if ((item as Map)['document'] != null)
            _fromDoc((item['document'] as Map).cast<String, dynamic>())
      ].whereType<Radar>().toList();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> report({
    required double lat,
    required double lon,
    required bool mobile,
    int? maxSpeed,
    double? direction,
  }) async {
    if (!communityEnabled) return false;
    final now = DateTime.now();
    final expires =
        mobile ? now.add(mobileLifetime).millisecondsSinceEpoch : 0;
    final fields = <String, dynamic>{
      'lat': {'doubleValue': lat},
      'lon': {'doubleValue': lon},
      'cell': {'stringValue': cellOf(lat, lon)},
      'type': {'stringValue': mobile ? 'movel' : 'comunidade'},
      'createdAt': {'integerValue': '${now.millisecondsSinceEpoch}'},
      'expiresAt': {'integerValue': '$expires'},
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
    final exp = n('expiresAt')?.toInt() ?? 0;
    final name = doc['name']?.toString() ?? '';
    return Radar(
      id: 'cm_${name.split('/').last}',
      lat: lat.toDouble(),
      lon: lon.toDouble(),
      maxSpeed: n('maxSpeed')?.toInt(),
      type: (f['type'] as Map?)?['stringValue']?.toString() ?? 'comunidade',
      direction: n('direction')?.toDouble(),
      expiresAt: exp == 0 ? null : exp,
    );
  }
}
