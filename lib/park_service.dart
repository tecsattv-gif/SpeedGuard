import 'dart:convert';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'route_service.dart';

/// Park (área de descanso, área de serviço ou estacionamento de caminhão).
class Park {
  final String id;
  final String name;
  final double lat, lon;
  final String kind; // rest_area, services, parking
  final Map<String, String> tags;
  const Park(this.id, this.name, this.lat, this.lon, this.kind, this.tags);

  String get kindLabel => switch (kind) {
        'services' => 'Área de serviço',
        'rest_area' => 'Área de descanso',
        _ => 'Estacionamento de caminhão',
      };

  bool _yes(String k) {
    final v = tags[k];
    return v != null && v != 'no';
  }

  /// O que o park oferece (só o que está marcado no mapa).
  List<String> get features => [
        if (_yes('toilets') || tags['toilets:wheelchair'] != null) 'WC',
        if (_yes('shower')) 'Chuveiro',
        if (kind == 'services' || _yes('fuel')) 'Combustível',
        if (_yes('restaurant') || _yes('food')) 'Restaurante',
        if (tags['capacity:hgv'] != null) '${tags['capacity:hgv']} vagas',
        if (tags['fee'] == 'yes') 'Pago',
        if (tags['fee'] == 'no') 'Grátis',
      ];
}

/// Park à frente, com a distância (m) e o lado da via.
class ParkAhead {
  final Park park;
  final double distance;
  final String? side; // 'direita' / 'esquerda'
  /// true = distância pela estrada (rota); false = em linha reta.
  final bool road;
  const ParkAhead(this.park, this.distance, this.side, {this.road = false});
}

/// Busca os parks em volta no OpenStreetMap e diz quais estão à frente.
class ParkService {
  static const _urls = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
    'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
  ];
  static const _ua = 'SpeedGuard/1.24 (Android; tecsattv-gif/SpeedGuard)';
  static const _radius = 60000.0; // parks num raio de 60 km
  static const _refetch = 25000.0; // baixa de novo a cada 25 km

  List<Park> _parks = [];
  double? _lat, _lon;
  DateTime? _lastFail;
  bool _busy = false;
  final Set<String> _announced = {};
  double _lastHeading = -1;

  int get count => _parks.length;

  Future<void> update(double lat, double lon) async {
    if (_busy) return;
    if (_lastFail != null &&
        DateTime.now().difference(_lastFail!) < const Duration(seconds: 90)) {
      return;
    }
    if (_lat != null &&
        Geolocator.distanceBetween(lat, lon, _lat!, _lon!) < _refetch) {
      return;
    }
    _busy = true;
    final a = 'around:${_radius.toInt()},$lat,$lon';
    final q = '[out:json][timeout:25];('
        'nwr["highway"~"^(rest_area|services)\$"]($a);'
        'nwr["amenity"="parking"]["hgv"~"^(yes|designated)\$"]($a);'
        'nwr["amenity"="parking"]["parking"="truck_stop"]($a);'
        ');out center tags;';
    try {
      final list = await _fetch(q);
      if (list == null) {
        _lastFail = DateTime.now();
        return;
      }
      _parks = _dedupe(list);
      _lat = lat;
      _lon = lon;
      _lastFail = null;
    } finally {
      _busy = false;
    }
  }

  /// Faz a busca no Overpass (tenta os 3 servidores). null = falhou.
  Future<List<Park>?> _fetch(String q, [int timeout = 30]) async {
    for (final url in _urls) {
      try {
        final res = await http
            .post(Uri.parse(url), headers: {'User-Agent': _ua}, body: {'data': q})
            .timeout(Duration(seconds: timeout));
        if (res.statusCode != 200) continue;
        final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
        final els = data['elements'];
        final remark = data['remark']?.toString().toLowerCase() ?? '';
        if (els is! List || remark.contains('error')) continue;
        final list = <Park>[];
        for (final e in els) {
          final m = e as Map;
          final c = m['center'] as Map?;
          final la = ((m['lat'] ?? c?['lat']) as num?)?.toDouble();
          final lo = ((m['lon'] ?? c?['lon']) as num?)?.toDouble();
          if (la == null || lo == null) continue;
          final raw = m['tags'];
          final tags = <String, String>{
            if (raw is Map)
              for (final en in raw.entries) en.key.toString(): en.value.toString()
          };
          final hw = tags['highway'];
          final kind = hw == 'services'
              ? 'services'
              : hw == 'rest_area'
                  ? 'rest_area'
                  : 'parking';
          list.add(Park('${m['type']}${m['id']}', tags['name'] ?? '', la, lo,
              kind, tags));
        }
        return list;
      } catch (_) {
        // tenta o próximo servidor
      }
    }
    return null;
  }

  // ---------- Parks ao longo da rota (destino digitado em Navegar) ----------

  /// Parks da rota com a distância pela estrada desde a partida (m) e o lado.
  List<(Park, double, String)> _route = [];
  bool routeLoading = false;
  bool get hasRoute => _route.isNotEmpty;
  int get routeCount => _route.length;

  void clearRoute() => _route = [];

  /// Busca os parks num corredor de 600 m em volta da rota (em trechos de
  /// ~200 km) e guarda os que ficam no seu sentido. Devolve quantos achou,
  /// ou null se a busca falhou.
  Future<int?> loadRoute(RouteService route, {String? country}) async {
    routeLoading = true;
    try {
      final pts = route.sample(1000);
      final found = <Park>[];
      for (var i = 0; i < pts.length - 1; i += 200) {
        final part = pts.sublist(i, math.min(i + 201, pts.length));
        final line = part
            .map((p) => '${p.$1.toStringAsFixed(5)},${p.$2.toStringAsFixed(5)}')
            .join(',');
        final a = 'around:600,$line';
        final q = '[out:json][timeout:60];('
            'nwr["highway"~"^(rest_area|services)\$"]($a);'
            'nwr["amenity"="parking"]["hgv"~"^(yes|designated)\$"]($a);'
            'nwr["amenity"="parking"]["parking"="truck_stop"]($a);'
            ');out center tags;';
        final list = await _fetch(q, 70);
        if (list == null) return null;
        found.addAll(list);
      }
      final leftHand =
          const {'gb', 'ie', 'mt', 'cy'}.contains(country?.toLowerCase());
      final out = <(Park, double, String)>[];
      for (final p in _dedupe(found)) {
        final (i, d, side) = route.nearest(p.lat, p.lon);
        if (d > 600) continue;
        final right = side > 0;
        // Área de autoestrada do outro lado: é da pista contrária.
        final wrong = leftHand ? right : !right;
        if (wrong && p.kind != 'parking' && d < 500) continue;
        out.add((p, route.cum[i], right ? 'direita' : 'esquerda'));
      }
      out.sort((a, b) => a.$2.compareTo(b.$2));
      _route = out;
      return out.length;
    } finally {
      routeLoading = false;
    }
  }

  /// Parks da rota que ainda estão à frente, com a distância pela estrada.
  /// [max] = 0 devolve todos.
  List<ParkAhead> alongRoute(double progress, {int max = 3}) {
    final out = [
      for (final (p, at, side) in _route)
        if (at > progress + 100) ParkAhead(p, at - progress, side, road: true)
    ];
    return max <= 0 ? out : out.take(max).toList();
  }

  /// O mesmo park às vezes vem como área + estacionamento: junta os que
  /// estão a menos de 250 m, ficando com o mais completo.
  static List<Park> _dedupe(List<Park> list) {
    const rank = {'services': 0, 'rest_area': 1, 'parking': 2};
    list.sort((a, b) => rank[a.kind]!.compareTo(rank[b.kind]!));
    final out = <Park>[];
    for (final p in list) {
      final i = out.indexWhere((o) =>
          Geolocator.distanceBetween(o.lat, o.lon, p.lat, p.lon) < 250);
      if (i < 0) {
        out.add(p);
      } else if (out[i].name.isEmpty && p.name.isNotEmpty) {
        final o = out[i];
        out[i] = Park(o.id, p.name, o.lat, o.lon, o.kind, {...p.tags, ...o.tags});
      }
    }
    return out;
  }

  static double _angleDiff(double a, double b) {
    final d = (a - b).abs() % 360;
    return d > 180 ? 360 - d : d;
  }

  /// Os próximos parks à frente (até [max]), do mais perto ao mais longe.
  /// [heading] < 0 quando o GPS não sabe a direção (usa a última).
  List<ParkAhead> ahead(double lat, double lon, double heading,
      {int max = 3, String? country}) {
    if (heading >= 0) _lastHeading = heading;
    final h = _lastHeading;
    if (h < 0 || _parks.isEmpty) return const [];
    // Mão inglesa: o park do seu sentido fica à esquerda.
    final leftHand =
        const {'gb', 'ie', 'mt', 'cy'}.contains(country?.toLowerCase());
    final out = <ParkAhead>[];
    for (final p in _parks) {
      final d = Geolocator.distanceBetween(lat, lon, p.lat, p.lon);
      if (d < 150 || d > _radius) continue;
      final b =
          (Geolocator.bearingBetween(lat, lon, p.lat, p.lon) + 360) % 360;
      final diff = _angleDiff(h, b);
      // Longe a estrada faz curvas: aceita um cone maior.
      if (diff > (d > 10000 ? 50 : 40)) continue;
      String? side;
      if (d < 3000) {
        final rel = ((b - h) + 360) % 360; // 0..360, à direita < 180
        final lateral = d * math.sin(diff * math.pi / 180);
        side = rel < 180 ? 'direita' : 'esquerda';
        // Área de autoestrada do lado contrário (perto do eixo): é da outra
        // pista, não serve para quem vai neste sentido.
        final wrong = leftHand ? side == 'direita' : side == 'esquerda';
        if (wrong && p.kind != 'parking' && lateral < 400) continue;
      }
      out.add(ParkAhead(p, d, side));
    }
    out.sort((a, b) => a.distance.compareTo(b.distance));
    return out.take(max).toList();
  }

  /// Os parks mais perto em qualquer direção (quando ainda não há rumo).
  List<ParkAhead> nearest(double lat, double lon, {int max = 3}) {
    final out = [
      for (final p in _parks)
        ParkAhead(p, Geolocator.distanceBetween(lat, lon, p.lat, p.lon), null)
    ]..sort((a, b) => a.distance.compareTo(b.distance));
    return out.take(max).toList();
  }

  /// Já sabe para onde o veículo vai (teve rumo do GPS)?
  bool get hasHeading => _lastHeading >= 0;

  /// Frase de aviso quando o próximo park fica a 2 km (uma vez por park).
  String? announce(List<ParkAhead> list) {
    if (list.isEmpty) return null;
    final p = list.first;
    if (p.distance > 2100 || _announced.contains(p.park.id)) return null;
    _announced.add(p.park.id);
    final side = p.side != null ? ', à ${p.side}' : '';
    final what = p.park.kind == 'parking' ? 'Estacionamento de caminhão' : 'Park';
    return '$what a 2 quilômetros$side.';
  }
}
