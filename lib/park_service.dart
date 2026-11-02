import 'dart:convert';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'overpass_gate.dart';
import 'route_service.dart';
import 'tile_store.dart';

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
  static const _radius = 25000.0; // parks num raio de ~25 km
  static const _refetch = 12000.0; // baixa de novo a cada 12 km
  /// Pedaço da rota buscado de cada vez (o resto vem conforme anda).
  static const routeWindow = 80000.0;

  /// Busca leve (retângulo, só os filtros com índice no servidor).
  static String query(List<String> boxes) {
    final sb = StringBuffer('[out:json][timeout:15];(');
    for (final b in boxes) {
      sb
        ..write('nw["highway"="rest_area"]($b);')
        ..write('nw["highway"="services"]($b);')
        ..write('nw["amenity"="parking"]["hgv"~"^(yes|designated|only)\$"]($b);')
        ..write('nw["parking"="truck_stop"]($b);');
    }
    sb.write(');out center tags;');
    return sb.toString();
  }

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
    const dLat = 0.225; // ~25 km
    final dLon = dLat / math.cos(lat * math.pi / 180);
    final q = query(['${(lat - dLat).toStringAsFixed(4)},'
        '${(lon - dLon).toStringAsFixed(4)},'
        '${(lat + dLat).toStringAsFixed(4)},'
        '${(lon + dLon).toStringAsFixed(4)}']);
    try {
      // Base própria primeiro; Overpass só se ela não estiver disponível.
      final list = await _fromTiles(
              TileStore.keysAround(lat, lon, _radius)) ??
          await _fetch(q);
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

  /// Parks dos pedaços da base própria. null = pedaço indisponível.
  static Future<List<Park>?> _fromTiles(List<String> keys) async {
    final items = await TileStore.getAll('parks', keys);
    if (items == null) return null;
    final out = <Park>[];
    for (final e in items) {
      final m = e as Map;
      final raw = m['t'];
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
      out.add(Park(m['i'].toString(), tags['name'] ?? '',
          (m['a'] as num).toDouble(), (m['o'] as num).toDouble(), kind, tags));
    }
    return out;
  }

  /// Faz a busca no Overpass (tenta os 3 servidores). null = falhou.
  Future<List<Park>?> _fetch(String q, [int timeout = 30]) =>
      OverpassGate.run(() => _fetchNow(q, timeout));

  Future<List<Park>?> _fetchNow(String q, int timeout) async {
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
  /// Já tem pelo menos um trecho da rota buscado (mesmo sem parks).
  bool routeReady = false;
  bool get hasRoute => routeReady;
  /// Progresso da busca: trechos prontos / total.
  int routeChunks = 0, routeChunksDone = 0;
  /// Chamado a cada trecho buscado (para a tela se atualizar).
  void Function()? onRouteUpdate;
  Object? _routeOf; // rota que está sendo buscada
  List<Park> _found = []; // parks já baixados desta rota
  double _loadedUntil = 0; // até onde (m) a rota já foi buscada

  /// Precisa buscar o próximo pedaço da rota? (faltam < 40 km do buscado)
  bool needMore(RouteService route, double progress) =>
      routeReady &&
      !routeLoading &&
      _loadedUntil < route.total &&
      progress + 40000 > _loadedUntil;
  double get loadedUntil => _loadedUntil;
  int get routeCount => _route.length;

  void clearRoute() {
    _route = [];
    _found = [];
    _loadedUntil = 0;
    routeReady = false;
    _routeOf = null;
  }

  /// Busca os parks num corredor de 600 m em volta da rota (em trechos de
  /// ~200 km) e guarda os que ficam no seu sentido. Devolve quantos achou,
  /// ou null se a busca falhou.
  Future<int?> loadRoute(RouteService route,
      {String? country, double from = 0}) async {
    routeLoading = true;
    if (from == 0 || !identical(route.pts, _routeOf)) {
      routeReady = false;
      _route = [];
      _found = [];
      _routeOf = route.pts;
    }
    try {
      // A rota é dividida em trechos de ~15 km; cada trecho vira um
      // retângulo (com 700 m de folga) e a busca é por retângulos, que o
      // servidor responde rápido. (A busca em volta da linha da rota, da
      // 1.25.0, demorava demais e a lista nunca aparecia.)
      final pts = route.sampleRange(from, from + routeWindow);
      final boxes = <String>[];
      for (var i = 0; i < pts.length; i += 15) {
        final part = pts.sublist(i, math.min(i + 16, pts.length));
        var s0 = 90.0, w0 = 180.0, n0 = -90.0, e0 = -180.0;
        for (final p in part) {
          s0 = math.min(s0, p.$1);
          n0 = math.max(n0, p.$1);
          w0 = math.min(w0, p.$2);
          e0 = math.max(e0, p.$2);
        }
        const dLat = 0.0065;
        final dLon = 0.0065 / math.cos(s0 * math.pi / 180);
        boxes.add('${(s0 - dLat).toStringAsFixed(4)},'
            '${(w0 - dLon).toStringAsFixed(4)},'
            '${(n0 + dLat).toStringAsFixed(4)},'
            '${(e0 + dLon).toStringAsFixed(4)}');
      }
      // Busca trecho a trecho (4 retângulos, ~60 km por vez), começando
      // pelo mais perto. Cada trecho entra na fila do Overpass sozinho, então
      // radares e limite da via não ficam esperando a rota inteira, e a lista
      // já aparece com os primeiros parks enquanto o resto carrega.
      // Trecho que falhar é pulado (a rota não fica travada por causa dele).
      final leftHand =
          const {'gb', 'ie', 'mt', 'cy'}.contains(country?.toLowerCase());
      final found = _found;
      var ok = 0;
      routeChunks = (boxes.length + 3) ~/ 4;
      routeChunksDone = 0;
      for (var i = 0; i < boxes.length; i += 4) {
        if (!identical(route.pts, _routeOf)) return null; // rota trocada
        final part = boxes.sublist(i, math.min(i + 4, boxes.length));
        final keys = <String>{
          for (final b in part)
            ...() {
              final v = b.split(',').map(double.parse).toList();
              return TileStore.keysFor(v[0], v[1], v[2], v[3]);
            }()
        }.toList();
        final list = await _fromTiles(keys) ?? await _fetch(query(part), 20);
        routeChunksDone++;
        if (list == null) continue;
        ok++;
        found.addAll(list);
        // Mostra o que já tem.
        final out = <(Park, double, String)>[];
        for (final p in _dedupe([...found])) {
          final (k, d, side) = route.nearest(p.lat, p.lon);
          if (d > 600) continue;
          final right = side > 0;
          // Área de autoestrada do outro lado: é da pista contrária.
          final wrong = leftHand ? right : !right;
          if (wrong && p.kind != 'parking' && d < 500) continue;
          out.add((p, route.cum[k], right ? 'direita' : 'esquerda'));
        }
        out.sort((a, b) => a.$2.compareTo(b.$2));
        _route = out;
        routeReady = true;
        onRouteUpdate?.call();
      }
      if (ok == 0) return null;
      _loadedUntil = from + routeWindow;
      return _route.length;
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
