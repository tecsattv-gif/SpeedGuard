import 'dart:convert';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'overpass_gate.dart';

/// Via onde fica uma cabine de pedágio (1.35.0).
class TollRoad {
  final String hw; // highway=*
  final Set<String> ids; // números (R:) ou nome (N:)
  final double? dir; // sentido do trânsito (mão única) ou null (mão dupla)
  const TollRoad(this.hw, this.ids, this.dir);
  bool get isLink => hw.endsWith('_link');
}

/// Uma cabine de pedágio e as vias em que ela está.
class Toll {
  final double lat, lon;
  final List<TollRoad> roads; // vazio = não se sabe a via
  /// Pórtico de pedágio eletrônico, sem cabine (highway=toll_gantry), 1.36.0.
  final bool gantry;
  const Toll(this.lat, this.lon, this.roads, {this.gantry = false});
}

/// Aviso a dar agora: [d] = distância; [passing] = passando por baixo do
/// pórtico (só pedágio eletrônico).
class TollHit {
  final double d;
  final bool gantry, passing;
  const TollHit(this.d, this.gantry, this.passing);
}

/// Aviso de pedágio (1.29.48): busca as cabines de pedágio
/// (barrier=toll_booth do OpenStreetMap) num raio de ~25 km e avisa uma
/// vez, a 1000 m, quando há uma à frente no seu caminho.
///
/// 1.35.0: cada cabine vem com a via onde ela está (way(bn) do Overpass).
/// Só avisa o pedágio da via e do sentido em que você está: o pedágio
/// dentro da saída (alça _link) não é avisado enquanto você segue na
/// rodovia — só se você entrar na saída.
///
/// 1.36.0: também os pórticos de pedágio eletrônico sem cabine
/// (highway=toll_gantry, ex.: antigas SCUT de Portugal, Via Verde). Avisa a
/// 1000 m e de novo na hora em que você passa por baixo.
class TollService {
  static const _urls = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
    'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
  ];
  static const _ua = 'SpeedGuard/1.36 (Android; tecsattv-gif/SpeedGuard)';
  static const warnAt = 1000.0;

  bool enabled = true;
  List<Toll> _tolls = [];
  double? _lat, _lon;
  DateTime? _lastFail;
  bool _busy = false;
  // Praças já avisadas (várias cabines juntas contam como uma).
  final List<(double, double)> _done = [];
  // Pórticos eletrônicos já avisados "passando agora".
  final List<(double, double)> _passed = [];
  static const passAt = 120.0;

  static Set<String> _ids(Map tags) {
    String norm(String v) => v.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    final out = <String>{};
    for (final k in ['ref', 'int_ref']) {
      final v = tags[k]?.toString() ?? '';
      for (final r in v.split(';')) {
        if (r.trim().isNotEmpty) out.add('R:${norm(r)}');
      }
    }
    if (out.isEmpty) {
      final n = tags['name']?.toString() ?? '';
      if (n.trim().isNotEmpty) out.add('N:${norm(n)}');
    }
    return out;
  }

  static int _oneway(Map tags, String hw) {
    final o = tags['oneway']?.toString();
    if (o == '-1') return -1;
    if (o == 'yes' || o == 'true' || o == '1') return 1;
    if (o == 'no') return 0;
    if (hw == 'motorway' || hw == 'motorway_link') return 1;
    if (tags['junction'] == 'roundabout') return 1;
    return 0;
  }

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
    // Cabines (pontos), as vias em que cada uma está e as cabines
    // desenhadas como linha/área (essas sem via conhecida).
    final q = '[out:json][timeout:20];'
        'node["barrier"="toll_booth"]($box)->.a;'
        'node["highway"="toll_gantry"]($box)->.g;'
        '(.a;.g;)->.t;'
        '.t out;'
        'way(bn.t)["highway"]["highway"!="toll_gantry"];out body geom;'
        'way["barrier"="toll_booth"]($box);out center;'
        'way["highway"="toll_gantry"]($box);out center;';
    try {
      final list = await OverpassGate.run(() async {
        for (final u in _urls) {
          try {
            final r = await http.post(Uri.parse(u),
                headers: {'User-Agent': _ua},
                body: {'data': q}).timeout(const Duration(seconds: 25));
            if (r.statusCode != 200) continue;
            final data = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
            final els = data['elements'];
            if (els is! List) continue;
            return _parse(els);
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

  static List<Toll> _parse(List els) {
    final booths = <int, (double, double)>{};
    final gantries = <int>{};
    final roadsOf = <int, List<TollRoad>>{};
    final out = <Toll>[];
    for (final e in els) {
      if (e is! Map) continue;
      final type = e['type'];
      if (type == 'node') {
        final la = (e['lat'] as num?)?.toDouble();
        final lo = (e['lon'] as num?)?.toDouble();
        final id = (e['id'] as num?)?.toInt();
        if (la != null && lo != null && id != null) {
          booths[id] = (la, lo);
          final nt = (e['tags'] as Map?) ?? const {};
          if (nt['highway'] == 'toll_gantry' && nt['barrier'] != 'toll_booth') {
            gantries.add(id);
          }
        }
        continue;
      }
      if (type != 'way') continue;
      final tags = (e['tags'] as Map?) ?? const {};
      if (tags['barrier'] == 'toll_booth' && e['center'] is Map) {
        final c = e['center'] as Map;
        final la = (c['lat'] as num?)?.toDouble();
        final lo = (c['lon'] as num?)?.toDouble();
        if (la != null && lo != null) out.add(Toll(la, lo, const []));
        continue;
      }
      if (tags['highway'] == 'toll_gantry') {
        final c = e['center'];
        if (c is Map) {
          final la = (c['lat'] as num?)?.toDouble();
          final lo = (c['lon'] as num?)?.toDouble();
          if (la != null && lo != null) {
            out.add(Toll(la, lo, const [], gantry: true));
          }
        }
        continue;
      }
      final hw = tags['highway']?.toString();
      final nodes = e['nodes'];
      final geom = e['geometry'];
      if (hw == null || nodes is! List || geom is! List) continue;
      final ow = _oneway(tags, hw);
      final ids = _ids(tags);
      for (var i = 0; i < nodes.length && i < geom.length; i++) {
        final nid = (nodes[i] as num).toInt();
        if (!booths.containsKey(nid)) continue;
        // Rumo do trecho no ponto da cabine (sentido dos pontos).
        final a = geom[i > 0 ? i - 1 : i] as Map;
        final b = geom[i < geom.length - 1 ? i + 1 : i] as Map;
        double? dir;
        if (ow != 0 && !identical(a, b)) {
          final br = (Geolocator.bearingBetween(
                      (a['lat'] as num).toDouble(),
                      (a['lon'] as num).toDouble(),
                      (b['lat'] as num).toDouble(),
                      (b['lon'] as num).toDouble()) +
                  360) %
              360;
          dir = ow == 1 ? br : (br + 180) % 360;
        }
        (roadsOf[nid] ??= []).add(TollRoad(hw, ids, dir));
      }
    }
    for (final en in booths.entries) {
      out.add(Toll(en.value.$1, en.value.$2, roadsOf[en.key] ?? const [],
          gantry: gantries.contains(en.key)));
    }
    return out;
  }

  static double _diff(double a, double b) {
    final d = (a - b).abs() % 360;
    return d > 180 ? 360 - d : d;
  }

  /// O pedágio está na via (e no sentido) onde o veículo está?
  /// [myType]/[myIds]: via atual do veículo (null = não se sabe).
  static bool _onMyRoad(Toll t, double heading, double kmh, String? myType,
      Set<String> myIds) {
    if (t.roads.isEmpty) return true; // sem via conhecida: avisa como antes
    bool ok(TollRoad x) {
      // Mão única no sentido contrário (pista do outro sentido): não.
      if (x.dir != null && _diff(x.dir!, heading) > 100) return false;
      if (myType == null) {
        // Via atual desconhecida: rápido, você não está numa alça de saída.
        return !(kmh > 60 && x.isLink);
      }
      // Pedágio dentro da saída (alça) com você na rodovia, e vice-versa.
      if (x.isLink != myType.endsWith('_link')) return false;
      if (myIds.isNotEmpty && x.ids.isNotEmpty) {
        return x.ids.intersection(myIds).isNotEmpty;
      }
      // Sem número/nome de um dos lados: o tipo da via decide.
      return x.hw == myType;
    }

    return t.roads.any(ok);
  }

  /// Aviso de pedágio à frente que deve ser dado agora (uma vez por praça;
  /// pórtico eletrônico: uma vez a 1000 m e outra ao passar por baixo).
  /// [sameRoad]: só pedágios da via onde você está ([myType]/[myIds] = via
  /// atual, null quando não se sabe).
  TollHit? check(double lat, double lon, double heading, double kmh,
      {bool sameRoad = true, String? myType, Set<String> myIds = const {}}) {
    if (!enabled || heading < 0 || kmh < 15 || _tolls.isEmpty) return null;
    bool near(List<(double, double)> l, Toll t, double r) =>
        l.any((x) => Geolocator.distanceBetween(x.$1, x.$2, t.lat, t.lon) < r);
    // 1º: passando agora por baixo de um pórtico eletrônico.
    for (final t in _tolls) {
      if (!t.gantry) continue;
      final d = Geolocator.distanceBetween(lat, lon, t.lat, t.lon);
      if (d > passAt) continue;
      final b = Geolocator.bearingBetween(lat, lon, t.lat, t.lon);
      // Perto, o rumo até o ponto varia mais: aceita até 45°.
      if (d > 25 && _diff((b + 360) % 360, heading) > 45) continue;
      if (near(_passed, t, 300)) continue;
      if (sameRoad && !_onMyRoad(t, heading, kmh, myType, myIds)) continue;
      _passed.add((t.lat, t.lon));
      _done.add((t.lat, t.lon)); // não avisa mais "a 1 km" depois de passar
      if (_passed.length > 200) _passed.removeAt(0);
      return TollHit(d, true, true);
    }
    // 2º: pedágio (cabine ou pórtico) a até 1000 m à frente.
    double? best;
    Toll? at;
    for (final t in _tolls) {
      final d = Geolocator.distanceBetween(lat, lon, t.lat, t.lon);
      if (d > warnAt || d < (t.gantry ? passAt : 80)) continue;
      final b = Geolocator.bearingBetween(lat, lon, t.lat, t.lon);
      if (_diff((b + 360) % 360, heading) > 25) continue;
      if (near(_done, t, t.gantry ? 300 : 600)) continue;
      if (sameRoad && !_onMyRoad(t, heading, kmh, myType, myIds)) continue;
      if (best == null || d < best) {
        best = d;
        at = t;
      }
    }
    if (at == null) return null;
    _done.add((at.lat, at.lon));
    if (_done.length > 200) _done.removeAt(0);
    return TollHit(best!, at.gantry, false);
  }
}
