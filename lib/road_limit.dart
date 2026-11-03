import 'dart:convert';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'overpass_gate.dart';

/// Uma via do OpenStreetMap com o limite de velocidade.
class _Way {
  final String type; // highway=*
  final Map<String, String> tags;
  final List<(double, double)> pts; // lat, lon
  _Way(this.type, this.tags, this.pts);
}

/// Descobre o limite de velocidade da via onde o veículo está,
/// pelas vias do OpenStreetMap em volta (baixadas aos poucos).
class RoadLimitService {
  static const _urls = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
    'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
  ];
  static const _ua = 'SpeedGuard/1.23 (Android; tecsattv-gif/SpeedGuard)';
  static const _radius = 2500.0; // baixa as vias num raio de 2,5 km
  static const _refetch = 1800.0; // e baixa de novo depois de 1,8 km

  List<_Way> _ways = [];
  double? _lat, _lon;
  DateTime? _lastFail;
  bool _busy = false;
  _Way? _current;

  /// Baixa as vias em volta, se precisar. Não trava o app.
  Future<void> update(double lat, double lon) async {
    if (_busy) return;
    if (_lastFail != null &&
        DateTime.now().difference(_lastFail!) < const Duration(seconds: 60)) {
      return;
    }
    if (_lat != null &&
        Geolocator.distanceBetween(lat, lon, _lat!, _lon!) < _refetch) {
      return;
    }
    _busy = true;
    final q = '[out:json][timeout:20];'
        'way(around:${_radius.toInt()},$lat,$lon)'
        '[highway~"^(motorway|trunk|primary|secondary|tertiary|unclassified|'
        'residential|motorway_link|trunk_link|primary_link|secondary_link|'
        'tertiary_link)\$"];out tags geom;';
    try {
      await OverpassGate.run(() => _load(q, lat, lon));
    } finally {
      _busy = false;
    }
  }

  Future<void> _load(String q, double lat, double lon) async {
    {
      for (final url in _urls) {
        try {
          final res = await http
              .post(Uri.parse(url),
                  headers: {'User-Agent': _ua}, body: {'data': q})
              .timeout(const Duration(seconds: 25));
          if (res.statusCode != 200) continue;
          final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
          final els = data['elements'];
          final remark = data['remark']?.toString().toLowerCase() ?? '';
          if (els is! List || remark.contains('error')) continue;
          final ways = <_Way>[];
          for (final e in els) {
            final raw = (e as Map)['tags'];
            final tags = <String, String>{
              if (raw is Map)
                for (final en in raw.entries)
                  en.key.toString(): en.value.toString()
            };
            final geom = e['geometry'];
            if (geom is! List || geom.length < 2) continue;
            ways.add(_Way(tags['highway'] ?? '', tags, [
              for (final g in geom)
                ((g['lat'] as num).toDouble(), (g['lon'] as num).toDouble())
            ]));
          }
          _ways = ways;
          _lat = lat;
          _lon = lon;
          _lastFail = null;
          _current = null;
          return;
        } catch (_) {
          // tenta o próximo servidor
        }
      }
      _lastFail = DateTime.now();
    }
  }

  static double _angleDiff(double a, double b) {
    final d = (a - b).abs() % 360;
    return d > 180 ? 360 - d : d;
  }

  /// Distância (m) do ponto até a via e o rumo do trecho mais próximo.
  static (double, double) _near(_Way w, double lat, double lon) {
    final kx = 111320 * math.cos(lat * math.pi / 180);
    const ky = 110540.0;
    var best = double.infinity, bearing = 0.0;
    for (var i = 0; i < w.pts.length - 1; i++) {
      final ax = (w.pts[i].$2 - lon) * kx, ay = (w.pts[i].$1 - lat) * ky;
      final bx = (w.pts[i + 1].$2 - lon) * kx,
          by = (w.pts[i + 1].$1 - lat) * ky;
      final dx = bx - ax, dy = by - ay;
      final len2 = dx * dx + dy * dy;
      var t = len2 == 0 ? 0.0 : -(ax * dx + ay * dy) / len2;
      t = t.clamp(0.0, 1.0);
      final px = ax + t * dx, py = ay + t * dy;
      final d = math.sqrt(px * px + py * py);
      if (d < best) {
        best = d;
        bearing = (math.atan2(dx, dy) * 180 / math.pi + 360) % 360;
      }
    }
    return (best, bearing);
  }

  /// "Identidade" de uma via: os números (ref, ex.: "E 40;A 2") ou, sem
  /// número, o nome. Vazio = via sem número nem nome.
  static Set<String> _ids(_Way w) {
    String norm(String v) => v.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    final ref = w.tags['ref'] ?? w.tags['int_ref'] ?? '';
    final out = <String>{
      for (final r in ref.split(';'))
        if (r.trim().isNotEmpty) 'R:${norm(r)}'
    };
    final intRef = w.tags['int_ref'];
    if (intRef != null) {
      for (final r in intRef.split(';')) {
        if (r.trim().isNotEmpty) out.add('R:${norm(r)}');
      }
    }
    if (out.isEmpty) {
      final name = w.tags['name'];
      if (name != null && name.trim().isNotEmpty) out.add('N:${norm(name)}');
    }
    return out;
  }

  final Map<String, bool?> _onRoadCache = {};
  _Way? _cacheWay;
  List<_Way>? _cacheWays;

  /// O radar está na via onde o veículo está? (1.28.0)
  /// true/false; null = não dá para saber (vias ainda não baixadas, via
  /// atual desconhecida ou sem número/nome, radar fora da área baixada) —
  /// aí o app avisa como antes.
  bool? onCurrentRoad(String id, double lat, double lon) {
    final cur = _current;
    if (cur == null || _ways.isEmpty) return null;
    if (!identical(cur, _cacheWay) || !identical(_ways, _cacheWays)) {
      _onRoadCache.clear();
      _cacheWay = cur;
      _cacheWays = _ways;
    }
    return _onRoadCache.putIfAbsent(id, () => _check(cur, lat, lon));
  }

  bool? _check(_Way cur, double lat, double lon) {
    final mine = _ids(cur);
    if (mine.isEmpty) return null;
    if (_lat != null &&
        Geolocator.distanceBetween(lat, lon, _lat!, _lon!) > _radius - 100) {
      return null; // radar perto da borda da área baixada
    }
    // Vias perto do radar (até 40 m).
    double? nearestAny, nearestMine;
    for (final w in _ways) {
      final (d, _) = _near(w, lat, lon);
      if (d > 40) continue;
      if (nearestAny == null || d < nearestAny) nearestAny = d;
      final same = identical(w, cur) || _ids(w).intersection(mine).isNotEmpty;
      if (same && (nearestMine == null || d < nearestMine)) nearestMine = d;
    }
    if (nearestAny == null) return null; // nenhuma via perto: não sabe
    if (nearestMine == null) return false; // só outras vias perto
    // A minha via é a mais perto do radar, ou está bem colada nele
    // (radar marcado ao lado da pista). Radar numa rua que cruza ou corre
    // ao lado fica mais perto da outra via e é ignorado.
    return nearestMine <= nearestAny + 3 || nearestMine <= 12;
  }

  /// Limite da via onde o veículo está, em km/h (null se não souber).
  /// [heading] < 0 quando o GPS não sabe a direção.
  int? limitAt(double lat, double lon, double heading,
      {required bool truck, String? country}) {
    if (_ways.isEmpty) return null;
    _Way? best;
    var bestScore = double.infinity;
    for (final w in _ways) {
      final (d, b) = _near(w, lat, lon);
      if (d > 30) continue;
      var score = d;
      if (heading >= 0) {
        final diff = _angleDiff(heading, b);
        final along = math.min(diff, 180 - diff); // a via vale nos 2 sentidos
        if (along > 40) continue; // via atravessada (viaduto, cruzamento)
        score += along * 0.3;
      }
      // Fica na via atual enquanto der (evita pular para a marginal).
      if (identical(w, _current)) score -= 8;
      if (score < bestScore) {
        bestScore = score;
        best = w;
      }
    }
    _current = best;
    if (best == null) return null;
    return _limit(best, truck, country);
  }

  static int? _num(String? v) {
    if (v == null) return null;
    final m = RegExp(r'^\s*(\d+)\s*(mph)?').firstMatch(v);
    if (m == null) return null;
    final n = int.parse(m.group(1)!);
    return m.group(2) != null ? (n * 1.609).round() : n;
  }

  static int? _limit(_Way w, bool truck, String? country) {
    final t = w.tags;
    final car = _num(t['maxspeed']) ??
        _num(t['maxspeed:forward']) ??
        _num(t['maxspeed:backward']);
    if (!truck) return car;
    final hgv = _num(t['maxspeed:hgv']) ??
        _num(t['maxspeed:hgv:forward']) ??
        _num(t['maxspeed:hgv:backward']);
    if (hgv != null) return car == null ? hgv : math.min(hgv, car);
    if (car == null) return null;
    return math.min(car, truckMax(country, w.type));
  }

  /// Velocidade máxima de caminhão (acima de 3,5 t) por país e tipo de via,
  /// quando a via não tem limite próprio para caminhão.
  /// Valores gerais da lei de cada país — confira antes de confiar.
  static int truckMax(String? country, String highway) {
    final fast = highway.startsWith('motorway') || highway.startsWith('trunk');
    switch (country?.toLowerCase()) {
      case 'nl':
        return 80;
      case 'de':
      case 'at':
      case 'dk':
      case 'se':
      case 'pl':
      case 'cz':
        return fast ? 80 : 60;
      case 'be':
        return fast ? 90 : 60;
      default:
        return fast ? 90 : 80;
    }
  }
}
