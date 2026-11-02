import 'dart:convert';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

/// Rota até o destino digitado em "Navegar", calculada pelo OSRM
/// (OpenStreetMap). O Google Maps não deixa outros apps lerem a rota dele,
/// então o SpeedGuard calcula a mesma rota para saber os parks no caminho.
class RouteService {
  static const _ua = 'SpeedGuard/1.25 (Android; tecsattv-gif/SpeedGuard)';

  /// Pontos da rota (lat, lon) e distância acumulada até cada um (m).
  List<(double, double)> pts = [];
  List<double> cum = [];
  String destName = '';
  int _idx = 0; // ponto da rota mais perto do veículo (só anda para frente)
  int _offCount = 0; // leituras seguidas fora da rota

  bool get active => pts.length > 1;
  double get total => cum.isEmpty ? 0 : cum.last;

  void clear() {
    pts = [];
    cum = [];
    destName = '';
    _idx = 0;
    _offCount = 0;
  }

  /// Procura o destino e calcula a rota. Devolve null se deu certo, ou a
  /// mensagem de erro.
  Future<String?> plan(double lat, double lon, String dest) async {
    try {
      final g = await http.get(
          Uri.parse('https://nominatim.openstreetmap.org/search'
              '?format=json&limit=1&q=${Uri.encodeComponent(dest)}'),
          headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 15));
      if (g.statusCode != 200) return 'Não achei o destino.';
      final found = jsonDecode(utf8.decode(g.bodyBytes)) as List;
      if (found.isEmpty) return 'Não achei "$dest" no mapa.';
      final dLat = double.parse(found.first['lat'].toString());
      final dLon = double.parse(found.first['lon'].toString());
      final r = await http.get(
          Uri.parse('https://router.project-osrm.org/route/v1/driving/'
              '$lon,$lat;$dLon,$dLat?overview=full&geometries=geojson'),
          headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return 'Não consegui calcular a rota.';
      final data = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return 'Sem rota até o destino.';
      final coords = routes.first['geometry']['coordinates'] as List;
      final p = <(double, double)>[
        for (final c in coords)
          ((c[1] as num).toDouble(), (c[0] as num).toDouble())
      ];
      final c = <double>[0];
      for (var i = 1; i < p.length; i++) {
        c.add(c.last +
            Geolocator.distanceBetween(
                p[i - 1].$1, p[i - 1].$2, p[i].$1, p[i].$2));
      }
      pts = p;
      cum = c;
      destName = found.first['display_name']?.toString().split(',').first ??
          dest;
      _idx = 0;
      _offCount = 0;
      return null;
    } catch (_) {
      return 'Sem conexão para calcular a rota.';
    }
  }

  /// Ponto da rota mais perto de (lat, lon): índice, distância até a rota
  /// (m) e lado (+1 direita, -1 esquerda), procurando de [from] até [to].
  (int, double, int) nearest(double lat, double lon,
      [int from = 0, int? to]) {
    final kx = 111320 * math.cos(lat * math.pi / 180);
    const ky = 110540.0;
    var best = double.infinity, bi = from, side = 1;
    final end = math.min(to ?? pts.length - 1, pts.length - 1);
    for (var i = math.max(from, 0); i < end; i++) {
      final ax = (pts[i].$2 - lon) * kx, ay = (pts[i].$1 - lat) * ky;
      final bx = (pts[i + 1].$2 - lon) * kx, by = (pts[i + 1].$1 - lat) * ky;
      final dx = bx - ax, dy = by - ay;
      final len2 = dx * dx + dy * dy;
      var t = len2 == 0 ? 0.0 : -(ax * dx + ay * dy) / len2;
      t = t.clamp(0.0, 1.0);
      final px = ax + t * dx, py = ay + t * dy;
      final d = math.sqrt(px * px + py * py);
      if (d < best) {
        best = d;
        bi = i;
        // Ponto (origem) em relação ao trecho A→B: cruz < 0 = à direita.
        final cross = dx * (-ay) - dy * (-ax);
        side = cross < 0 ? 1 : -1;
      }
    }
    return (bi, best, side);
  }

  /// Distância percorrida na rota até o veículo (m), ou null se ele saiu
  /// da rota (aí a lista volta para "à frente" pelo rumo).
  double? progress(double lat, double lon) {
    if (!active) return null;
    // Procura perto do último ponto (rota pode passar 2 vezes no lugar).
    final from = math.max(0, _idx - 20);
    var (i, d, _) = nearest(lat, lon, from, _idx + 400);
    if (d > 150) {
      final all = nearest(lat, lon);
      if (all.$2 < d) (i, d, _) = all;
    }
    if (d > 300) {
      _offCount++;
      return _offCount >= 5 ? null : cum[_idx];
    }
    _offCount = 0;
    _idx = i;
    return cum[i];
  }

  /// Pontos da rota entre [from] e [to] metros, um a cada ~[step] m.
  List<(double, double)> sampleRange(double from, double to,
      [double step = 1000]) {
    if (!active) return [];
    final out = <(double, double)>[];
    var last = -1e9;
    for (var i = 0; i < pts.length; i++) {
      if (cum[i] < from) continue;
      if (cum[i] > to) {
        out.add(pts[i]);
        break;
      }
      if (cum[i] - last >= step || out.isEmpty) {
        out.add(pts[i]);
        last = cum[i];
      }
    }
    return out;
  }

  /// Rota simplificada (um ponto a cada ~[step] m) para a busca dos parks.
  List<(double, double)> sample([double step = 1500]) {
    if (!active) return [];
    final out = <(double, double)>[pts.first];
    var last = 0.0;
    for (var i = 1; i < pts.length; i++) {
      if (cum[i] - last >= step || i == pts.length - 1) {
        out.add(pts[i]);
        last = cum[i];
      }
    }
    return out;
  }
}
