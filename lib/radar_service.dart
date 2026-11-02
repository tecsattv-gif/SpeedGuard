import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Busca radares no OpenStreetMap, guarda em cache e mantém os
/// radares reportados pelo usuário.
class RadarService {
  /// Servidores Overpass, testados em ordem. Se um falhar, ocupado (429)
  /// ou estourar o tempo, tenta o próximo.
  static const _overpassUrls = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
    'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
  ];
  static const _userAgent = 'SpeedGuard/1.20 (Android; tecsattv-gif/SpeedGuard)';
  static const double radiusMeters = 30000; // 30 km ao redor
  static const double refetchDistance = 15000; // rebaixa após 15 km
  static const Duration cacheLife = Duration(hours: 6);
  static const Duration retryAfterFail = Duration(seconds: 90);
  static const _queryVersion = 2;

  List<Radar> _osm = [];
  List<Radar> _user = [];
  double? _cacheLat, _cacheLon;
  DateTime? _cacheTime;
  DateTime? _lastFail;

  List<Radar> get all => [..._osm, ..._user];

  /// Radares da área que o usuário está olhando no mapa (só para exibir;
  /// os avisos usam [all], que é a região em volta dele).
  List<Radar> _area = [];
  List<Radar> get area {
    final ids = {for (final r in _osm) r.id};
    return [for (final r in _area) if (!ids.contains(r.id)) r];
  }

  /// Pergunta ao Overpass. Devolve a lista de radares ou null se todos os
  /// servidores falharem. Resposta 200 com erro interno ("remark" de
  /// timeout/memória) conta como falha, para não gravar uma lista vazia.
  Future<List<Radar>?> _query(String area) async {
    // Radares em nós soltos e também nas relações de fiscalização
    // (type=enforcement), que é como a maioria dos radares de semáforo e
    // muitos de velocidade estão marcados: a câmera é o membro "device"
    // (ou "from", se não houver device) e o tipo fica na relação.
    final query = '[out:json][timeout:25];'
        '(node["highway"="speed_camera"]($area);'
        'node["enforcement"]($area);)->.n;'
        'relation["type"="enforcement"]($area)->.r;'
        '(node(r.r:"device");node(r.r:"from");)->.d;'
        '(.n;.d;.r;);out body;';
    for (final url in _overpassUrls) {
      try {
        final res = await http
            .post(Uri.parse(url),
                headers: {'User-Agent': _userAgent},
                body: {'data': query})
            .timeout(const Duration(seconds: 25));
        if (res.statusCode != 200) continue;
        final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
        final remark = data['remark']?.toString().toLowerCase() ?? '';
        if (remark.contains('error') ||
            remark.contains('timed out') ||
            remark.contains('out of memory')) {
          continue;
        }
        final els = data['elements'];
        if (els is! List) continue;
        return _fromElements(els);
      } catch (_) {
        // tenta o próximo servidor
      }
    }
    return null;
  }

  /// Junta nós e relações de fiscalização numa lista de radares.
  static List<Radar> _fromElements(List els) {
    final nodes = <int, Map<String, dynamic>>{};
    final direct = <int>{}; // nós que já são radar por si
    final fromRel = <int, Map<String, dynamic>>{}; // nó -> tags da relação
    for (final e in els) {
      final m = (e as Map).cast<String, dynamic>();
      final id = (m['id'] as num).toInt();
      final tags = (m['tags'] as Map?)?.cast<String, dynamic>() ?? {};
      if (m['type'] == 'node') {
        nodes[id] = m;
        if (tags['highway'] == 'speed_camera' || tags['enforcement'] != null) {
          direct.add(id);
        }
      } else if (m['type'] == 'relation') {
        final enf = tags['enforcement']?.toString() ?? '';
        if (!const {'maxspeed', 'traffic_signals', 'average_speed'}
            .contains(enf)) {
          continue;
        }
        final members = (m['members'] as List?) ?? [];
        int? pick(String role) {
          for (final mm in members) {
            final x = (mm as Map);
            if (x['type'] == 'node' && x['role'] == role) {
              return (x['ref'] as num).toInt();
            }
          }
          return null;
        }
        final node = pick('device') ?? pick('from');
        if (node != null) fromRel[node] = tags;
      }
    }
    final out = <Radar>[];
    final seen = <String>{};
    for (final id in {...direct, ...fromRel.keys}) {
      final n = nodes[id];
      if (n == null) continue;
      final own = (n['tags'] as Map?)?.cast<String, dynamic>() ?? {};
      final rel = fromRel[id];
      final tags = <String, dynamic>{
        if (rel != null) ...rel,
        ...own,
        // O tipo e o limite da relação valem mais que os do nó.
        if (rel?['enforcement'] != null) 'enforcement': rel!['enforcement'],
        if (own['maxspeed'] == null && rel?['maxspeed'] != null)
          'maxspeed': rel!['maxspeed'],
      };
      tags.remove('type');
      final r = Radar.fromOsm({...n, 'tags': tags});
      if (r != null && seen.add(r.id)) out.add(r);
    }
    return out;
  }

  /// Baixa os radares do retângulo visível no mapa.
  /// Retorna quantos encontrou, ou null se falhou.
  Future<int?> fetchArea(
      double south, double west, double north, double east) async {
    final list = await _query('$south,$west,$north,$east');
    if (list == null) return null;
    _area = list;
    return _area.length;
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
    // Busca mudou (1.23.1: radares de semáforo das relações): baixa de novo.
    if (p.getInt('osm_query_v') != _queryVersion) {
      _cacheTime = null;
      await p.setInt('osm_query_v', _queryVersion);
    }
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
    // Falhou há pouco: espera antes de tentar de novo, senão o app pede a
    // cada leitura do GPS e o servidor bloqueia (429).
    if (_lastFail != null &&
        DateTime.now().difference(_lastFail!) < retryAfterFail) {
      return false;
    }
    if (_cacheLat == null || _cacheTime == null) return true;
    if (DateTime.now().difference(_cacheTime!) >= cacheLife) return true;
    return Geolocator.distanceBetween(lat, lon, _cacheLat!, _cacheLon!) >
        refetchDistance;
  }

  /// Baixa os radares ao redor. Retorna quantos encontrou, ou null se falhou.
  Future<int?> refresh(double lat, double lon) async {
    final list =
        await _query('around:${radiusMeters.toInt()},$lat,$lon');
    if (list == null) {
      _lastFail = DateTime.now();
      return null;
    }
    _lastFail = null;
    _osm = list;
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
