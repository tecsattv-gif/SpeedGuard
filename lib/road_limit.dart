import 'dart:convert';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'overpass_gate.dart';

/// Uma via do OpenStreetMap com o limite de velocidade.
class _Way {
  final String type; // highway=*
  final Map<String, String> tags;
  final List<(double, double)> pts; // lat, lon
  late final double minLat, maxLat, minLon, maxLon; // caixa da via
  late final Set<String> ids = RoadLimitService._ids(this);
  _Way(this.type, this.tags, this.pts) {
    var a = 90.0, b = -90.0, c = 180.0, d = -180.0;
    for (final p in pts) {
      if (p.$1 < a) a = p.$1;
      if (p.$1 > b) b = p.$1;
      if (p.$2 < c) c = p.$2;
      if (p.$2 > d) d = p.$2;
    }
    minLat = a;
    maxLat = b;
    minLon = c;
    maxLon = d;
  }

  /// O ponto pode estar a menos de [m] metros da via? (teste rápido)
  bool near(double lat, double lon, double m) {
    final dLat = m / 110540;
    final dLon = m / (111320 * math.cos(lat * math.pi / 180));
    return lat >= minLat - dLat &&
        lat <= maxLat + dLat &&
        lon >= minLon - dLon &&
        lon <= maxLon + dLon;
  }
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
  // 1.29.0: busca mais leve (responde mais rápido e falha menos); a via de
  // cada radar agora vem da base própria.
  static const _radius = 1500.0; // baixa as vias num raio de 1,5 km
  static const _refetch = 1000.0; // e baixa de novo depois de 1 km

  List<_Way> _ways = [];
  double? _lat, _lon;
  // Última via conhecida do veículo (1.29.11): se o Overpass falhar, vale
  // por mais 800 m — antes, sem a via atual, quase nada era filtrado.
  Set<String> _lastIds = const {};
  String? _lastType;
  double? _lastAtLat, _lastAtLon, _posLat, _posLon;

  /// Países de mão inglesa (dirige-se pela esquerda).
  static const leftHand = {
    'gb', 'uk', 'ie', 'im', 'je', 'gg', 'cy', 'mt', 'jm', 'bs', 'bb', 'tt',
    'gy', 'sr', 'ag', 'dm', 'gd', 'kn', 'lc', 'vc', 'fk', 'vg', 'vi', 'ky',
    'ai', 'ms', 'tc', 'bm',
  };
  bool _left = false;
  DateTime? _lastFail;
  bool _busy = false;
  _Way? _current;

  /// Baixa as vias em volta, se precisar. Não trava o app.
  Future<void> update(double lat, double lon) async {
    if (_busy) return;
    if (_lastFail != null &&
        DateTime.now().difference(_lastFail!) < const Duration(seconds: 20)) {
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

  /// Vias a até 40 m de cada radar (distância e rumo do trecho), calculadas
  /// uma vez por radar a cada nova leva de vias (1.28.2: antes recalculava
  /// tudo a cada leitura do GPS e atrasava o velocímetro).
  final Map<String, List<(_Way, double, double)>> _radarNear = {};
  List<_Way>? _nearFor;

  /// Sentido único: 1 = na ordem dos pontos, -1 = ao contrário, 0 = mão
  /// dupla. Autoestrada e alças são sentido único mesmo sem a tag.
  static int _oneway(_Way w) {
    final o = w.tags['oneway'];
    if (o == '-1') return -1;
    if (o == 'yes' || o == 'true' || o == '1') return 1;
    if (o == 'no') return 0;
    if (w.type == 'motorway' || w.type == 'motorway_link') return 1;
    if (w.tags['junction'] == 'roundabout') return 1;
    return 0;
  }

  /// A via (sentido único) vai no sentido contrário ao do veículo?
  static bool _against(_Way w, double segBearing, double heading) {
    final o = _oneway(w);
    if (o == 0) return false;
    final dir = o == 1 ? segBearing : (segBearing + 180) % 360;
    return _angleDiff(heading, dir) > 110;
  }

  /// O radar está na via (e no sentido) onde o veículo está? (1.28.0/1.28.1)
  /// true/false; null = não dá para saber (vias ainda não baixadas, radar
  /// fora da área baixada) — aí o app avisa como antes.
  bool? onCurrentRoad(String id, double lat, double lon, double heading) {
    if (_ways.isEmpty) return null;
    if (!identical(_ways, _nearFor)) {
      _radarNear.clear();
      _nearFor = _ways;
    }
    if (_lat != null &&
        Geolocator.distanceBetween(lat, lon, _lat!, _lon!) > _radius - 100) {
      return null; // radar perto da borda da área baixada
    }
    final near = _radarNear.putIfAbsent(id, () {
      final out = <(_Way, double, double)>[];
      for (final w in _ways) {
        if (!w.near(lat, lon, 40)) continue;
        final (d, b) = _near(w, lat, lon);
        if (d <= 40) out.add((w, d, b));
      }
      return out;
    });
    return _check(_current, near, heading);
  }

  static bool? _check(
      _Way? cur, List<(_Way, double, double)> near, double heading) {
    final mine = cur == null ? <String>{} : cur.ids;
    // "Boa" = a minha via, no meu sentido.
    double? nearestAny, nearestGood;
    _Way? nearestWay;
    var nearestAgainst = false;
    for (final (w, d, b) in near) {
      final against = _against(w, b, heading);
      if (nearestAny == null || d < nearestAny) {
        nearestAny = d;
        nearestWay = w;
        nearestAgainst = against;
      }
      // Alça de entrada/saída (_link) não é a rodovia, mesmo com o mesmo
      // número — e vice-versa.
      final same = mine.isEmpty ||
          identical(w, cur) ||
          (w.ids.intersection(mine).isNotEmpty &&
              w.type.endsWith('_link') == cur!.type.endsWith('_link'));
      if (same && !against && (nearestGood == null || d < nearestGood)) {
        nearestGood = d;
      }
    }
    if (nearestAny == null) return null; // nenhuma via perto: não sabe
    // Radar na pista do outro sentido (autoestrada/via de mão única).
    if (nearestAgainst && (nearestGood == null || nearestGood > nearestAny + 4)) {
      return false;
    }
    if (mine.isEmpty) {
      // Via atual sem número/nome ou desconhecida: só o sentido decide.
      return nearestAgainst ? false : null;
    }
    if (nearestGood == null) return false; // só outras vias perto (alça, rua)
    // A minha via (no meu sentido) tem de ser a mais perto do radar.
    return nearestGood <= nearestAny + 4 || identical(nearestWay, cur);
  }

  static double _axisDiff(double a, double b) {
    final d = _angleDiff(a, b);
    return math.min(d, 180 - d);
  }

  /// Ruas de bairro: com o veículo rápido, ele não está nelas.
  static const _minor = {'residential', 'living_street', 'unclassified'};

  /// O radar está na via e no sentido do veículo? (1.29.0)
  /// Usa a via gravada na base própria para cada radar ([Radar.roads]):
  /// * via de mão única no sentido contrário (pista do outro sentido) → não;
  /// * via de mão dupla atravessada (rua que cruza) → não;
  /// * via com outro número/nome que a do veículo (paralela, marginal) → não;
  /// * alça de entrada/saída quando o veículo está na rodovia (e vice-versa) → não;
  /// * sem saber a via do veículo: rápido (> 70 km/h) não avisa radar de rua
  ///   de bairro.
  /// Radar sem via na base (reportado, Overpass): usa [onCurrentRoad].
  bool? radarOnMyRoad(Radar r, double heading, double bearing, double kmh) {
    bool against(double t) =>
        _angleDiff(t, heading) > 100 && _angleDiff(t, bearing) > 100;
    // Sentido exato do radar (relação de fiscalização / forward-backward).
    if (r.travel != null && !r.both && against(r.travel!)) return false;
    if (r.roads.isEmpty) return onCurrentRoad(r.id, r.lat, r.lon, heading);
    // Via do veículo: a atual ou, sem ela, a última conhecida (até 800 m).
    var curType = _current?.type;
    var mine = _current?.ids ?? const <String>{};
    if (_current == null &&
        _lastType != null &&
        _posLat != null &&
        Geolocator.distanceBetween(
                _posLat!, _posLon!, _lastAtLat!, _lastAtLon!) <
            800) {
      curType = _lastType;
      mine = _lastIds;
    }
    final near = r.roads.first.d;
    // Rua que cruza (1.29.29): vale também para mão única — antes só para
    // mão dupla, e radar de avenida com pistas separadas que passa por
    // cima/baixo da rodovia avisava. Acima de 60 km/h (rodovia, poucas
    // curvas) basta 40° de diferença; abaixo, 55°.
    final cross = kmh > 60 ? 40.0 : 55.0;
    bool ok(RoadRef x) {
      final dir = x.dir;
      if (_axisDiff(x.b, heading) > cross && _axisDiff(x.b, bearing) > cross) {
        return false; // rua que cruza
      }
      if (dir != null) {
        // Mão única: o trânsito tem de ir no meu sentido.
        if (against(dir)) return false;
      } else if (r.travel == null && !r.both && x.s != 0 && x.d >= 3 &&
          x.d <= 25) {
        // Mão dupla (1.29.11): o radar ao lado da via fiscaliza a pista do
        // lado dele — à direita do sentido do trânsito (à esquerda nos
        // países de mão inglesa). Do outro lado = pista contrária.
        final right = x.s == 1;
        final t = right != _left ? x.b : (x.b + 180) % 360;
        // 1.29.14: direção em graus marcada no mapa que contradiz o lado
        // (na base: ~2/3 dos radares apontam para o trânsito que vem, o
        // que bate com o lado; o resto contradiz) — na dúvida avisa os dois
        // sentidos, para não perder radar de verdade.
        final dg = r.direction;
        final doubt = dg != null && _angleDiff(dg, t) <= 45;
        if (!doubt && against(t)) return false;
      }
      if (curType != null) {
        if (x.isLink != curType.endsWith('_link')) return false;
        if (mine.isNotEmpty) {
          final ids = x.ids;
          if (ids.isNotEmpty && ids.intersection(mine).isEmpty) return false;
          if (ids.isEmpty && x.hw != curType) return false;
        } else if (x.hw != curType) {
          return false;
        }
      } else if (kmh > 70 && _minor.contains(x.hw)) {
        return false;
      }
      return true;
    }

    // Vale qualquer via praticamente à mesma distância (cruzamento, pista dupla).
    for (final x in r.roads) {
      if (x.d > near + 6) break;
      if (ok(x)) return true;
    }
    return false;
  }

  /// Limite da via onde o veículo está, em km/h (null se não souber).
  /// [heading] < 0 quando o GPS não sabe a direção.
  int? limitAt(double lat, double lon, double heading,
      {required bool truck, String? country}) {
    _posLat = lat;
    _posLon = lon;
    _left = leftHand.contains(country?.toLowerCase());
    if (_ways.isEmpty) {
      _current = null;
      return null;
    }
    _Way? best;
    var bestScore = double.infinity;
    for (final w in _ways) {
      if (!w.near(lat, lon, 30)) continue; // longe: nem calcula
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
    _lastIds = best.ids;
    _lastType = best.type;
    _lastAtLat = lat;
    _lastAtLon = lon;
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
