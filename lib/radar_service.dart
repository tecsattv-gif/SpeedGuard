import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Busca radares no OpenStreetMap, guarda em cache e mantém os
/// radares reportados pelo usuário.
class RadarService {
  static const _overpassUrls = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];
  static const _userAgent = 'SpeedGuard/1.0 (Android)';
  static const double radiusMeters = 50000; // 50 km ao redor
  static const double refetchDistance = 30000; // rebaixa após 30 km

  List<Radar> _osm = [];
  List<Radar> _user = [];
  double? _cacheLat, _cacheLon;
  DateTime? _cacheTime;

  List<Radar> get all => [..._osm, ..._user];

  /// Radares da área que o usuário está olhando no mapa (só para exibir;
  /// os avisos usam [all], que é a região em volta dele).
  List<Radar> _area = [];
  List<Radar> get area {
    final ids = {for (final r in _osm) r.id};
    return [for (final r in _area) if (!ids.contains(r.id)) r];
  }

  /// Baixa os radares do retângulo visível no mapa.
  /// Retorna quantos encontrou, ou null se falhou.
  Future<int?> fetchArea(
      double south, double west, double north, double east) async {
    final box = '$south,$west,$north,$east';
    final query = '[out:json][timeout:25];('
        'node["highway"="speed_camera"]($box);'
        'node["enforcement"="maxspeed"]($box);'
        'node["enforcement"="traffic_signals"]($box);'
        ');out body;';
    for (final url in _overpassUrls) {
      try {
        final res = await http
            .post(Uri.parse(url),
                headers: {'User-Agent': _userAgent},
                body: {'data': query})
            .timeout(const Duration(seconds: 30));
        if (res.statusCode != 200) continue;
        final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
        final els = (data['elements'] as List?) ?? [];
        final seen = <String>{};
        _area = els
            .map((e) => Radar.fromOsm((e as Map).cast<String, dynamic>()))
            .whereType<Radar>()
            .where((r) => seen.add(r.id))
            .toList();
        return _area.length;
      } catch (_) {
        // tenta o próximo servidor
      }
    }
    return null;
  }
  List<Radar> get userRadars => List.unmodifiable(_user);

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _osm = _decode(p.getString('osm_radars'));
    _user = _decode(p.getString('user_radars'));
    _cacheLat = p.getDouble('cache_lat');
    _cacheLon = p.getDouble('cache_lon');
    final t = p.getInt('cache_time');
    _cacheTime = t == null ? null : DateTime.fromMillisecondsSinceEpoch(t);
  }

  List<Radar> _decode(String? s) {
    if (s == null) return [];
    try {
      return (jsonDecode(s) as List)
          .map((e) => Radar.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  bool needsRefresh(double lat, double lon) {
    if (_cacheLat == null || _cacheTime == null) return true;
    if (DateTime.now().difference(_cacheTime!).inHours >= 24) return true;
    return Geolocator.distanceBetween(lat, lon, _cacheLat!, _cacheLon!) >
        refetchDistance;
  }

  /// Baixa os radares ao redor. Retorna quantos encontrou, ou null se falhou.
  Future<int?> refresh(double lat, double lon) async {
    final r = radiusMeters.toInt();
    final query = '[out:json][timeout:25];('
        'node["highway"="speed_camera"](around:$r,$lat,$lon);'
        'node["enforcement"="maxspeed"](around:$r,$lat,$lon);'
        'node["enforcement"="traffic_signals"](around:$r,$lat,$lon);'
        ');out body;';
    for (final url in _overpassUrls) {
      try {
        final res = await http
            .post(Uri.parse(url),
                headers: {'User-Agent': _userAgent},
                body: {'data': query})
            .timeout(const Duration(seconds: 30));
        if (res.statusCode != 200) continue;
        final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
        final els = (data['elements'] as List?) ?? [];
        final seen = <String>{};
        _osm = els
            .map((e) => Radar.fromOsm((e as Map).cast<String, dynamic>()))
            .whereType<Radar>()
            .where((r) => seen.add(r.id))
            .toList();
        _cacheLat = lat;
        _cacheLon = lon;
        _cacheTime = DateTime.now();
        final p = await SharedPreferences.getInstance();
        await p.setString(
            'osm_radars', jsonEncode(_osm.map((e) => e.toJson()).toList()));
        await p.setDouble('cache_lat', lat);
        await p.setDouble('cache_lon', lon);
        await p.setInt('cache_time', _cacheTime!.millisecondsSinceEpoch);
        return _osm.length;
      } catch (_) {
        // tenta o próximo servidor
      }
    }
    return null;
  }

  Future<void> addUserRadar(double lat, double lon, int? maxSpeed,
      double? direction) async {
    _user.add(Radar(
      id: 'user_${DateTime.now().millisecondsSinceEpoch}',
      lat: lat,
      lon: lon,
      maxSpeed: maxSpeed,
      type: 'usuario',
      direction: direction,
    ));
    await _saveUser();
  }

  Future<void> removeUserRadar(String id) async {
    _user.removeWhere((r) => r.id == id);
    await _saveUser();
  }

  Future<void> _saveUser() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        'user_radars', jsonEncode(_user.map((e) => e.toJson()).toList()));
  }

  /// Descobre o código do país (ex.: "br", "fr") pela posição.
  static Future<String?> detectCountry(double lat, double lon) async {
    try {
      final uri = Uri.parse('https://nominatim.openstreetmap.org/reverse'
          '?format=json&zoom=3&lat=$lat&lon=$lon');
      final res = await http.get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
      return (data['address'] as Map?)?['country_code']?.toString();
    } catch (_) {
      return null;
    }
  }
}
