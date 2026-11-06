import 'dart:convert';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'overpass_gate.dart';

/// Aviso de pedágio (1.29.48): busca as cabines de pedágio
/// (barrier=toll_booth do OpenStreetMap) num raio de ~25 km e avisa uma
/// vez, a 1000 m, quando há uma à frente no seu caminho.
class TollService {
  static const _urls = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
    'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
  ];
  static const _ua = 'SpeedGuard/1.29 (Android; tecsattv-gif/SpeedGuard)';
  static const warnAt = 1000.0;

  bool enabled = true;
  List<(double, double)> _tolls = [];
  double? _lat, _lon;
  DateTime? _lastFail;
  bool _busy = false;
  // Praças já avisadas (várias cabines juntas contam como uma).
  final List<(double, double)> _done = [];

  Future<void> update(double lat, double lon) async {
    if (!enabled || _busy) return;
    if (_lastFail != null &&
        DateTime.now().difference(_lastFail!) < const Duration(minutes: 2)) {
      return;
    }
    if (_lat != null &&
        Geolocator.distanceBetween(lat, lon, _lat!, _lon!) < 12000) {
      return;
    }
    _busy = true;
    const d = 0.225; // ~25 km
    final dl = d / math.cos(lat * math.pi / 180);
    final box = '${(lat - d).toStringAsFixed(4)},${(lon - dl).toStringAsFixed(4)},'
        '${(lat + d).toStringAsFixed(4)},${(lon + dl).toStringAsFixed(4)}';
    final q = '[out:json][timeout:15];('
        'node["barrier"="toll_booth"]($box);'
        'way["barrier"="toll_booth"]($box);'
        ');out center;';
    try {
      final list = await OverpassGate.run(() async {
        for (final u in _urls) {
          try {
            final r = await http.post(Uri.parse(u),
                headers: {'User-Agent': _ua},
                body: {'data': q}).timeout(const Duration(seconds: 20));
            if (r.statusCode != 200) continue;
            final out = <(double, double)>[];
            for (final e in (jsonDecode(r.body) as Map)['elements'] as List) {
              final m = e as Map;
              final c = (m['center'] as Map?) ?? m;
              final la = (c['lat'] as num?)?.toDouble();
              final lo = (c['lon'] as num?)?.toDouble();
              if (la != null && lo != null) out.add((la, lo));
            }
            return out;
          } catch (_) {}
        }
        return null;
      });
      if (list == null) {
        _lastFail = DateTime.now();
      } else {
        _tolls = list;
        _lat = lat;
        _lon = lon;
      }
    } finally {
      _busy = false;
    }
  }

  static double _diff(double a, double b) {
    final d = (a - b).abs() % 360;
    return d > 180 ? 360 - d : d;
  }

  /// Distância do pedágio à frente que deve ser avisado agora (uma vez).
  double? check(double lat, double lon, double heading, double kmh) {
    if (!enabled || heading < 0 || kmh < 15 || _tolls.isEmpty) return null;
    double? best;
    (double, double)? at;
    for (final t in _tolls) {
      final d = Geolocator.distanceBetween(lat, lon, t.$1, t.$2);
      if (d > warnAt || d < 80) continue;
      final b = Geolocator.bearingBetween(lat, lon, t.$1, t.$2);
      if (_diff((b + 360) % 360, heading) > 25) continue;
      if (_done.any((x) =>
          Geolocator.distanceBetween(x.$1, x.$2, t.$1, t.$2) < 600)) {
        continue;
      }
      if (best == null || d < best) {
        best = d;
        at = t;
      }
    }
    if (at == null) return null;
    _done.add(at);
    if (_done.length > 200) _done.removeAt(0);
    return best;
  }
}
