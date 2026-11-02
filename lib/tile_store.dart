import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Base própria de parks e radares (gerada toda semana pelo GitHub a partir
/// dos mapas do Geofabrik — veja tools/build_data.py). Fica em pedaços de
/// 2° x 2° no ramo "data" do repositório; o app baixa só os pedaços perto
/// de onde está e guarda no celular, então funciona offline e não depende
/// dos servidores Overpass.
class TileStore {
  static const _base =
      'https://raw.githubusercontent.com/tecsattv-gif/SpeedGuard/data';
  static const tile = 2;
  /// Pedaço guardado há mais que isto é baixado de novo (se houver internet).
  static const maxAge = Duration(days: 7);

  static Directory? _dir;
  static final Map<String, List<dynamic>> _mem = {};
  static final Map<String, Future<List<dynamic>?>> _pending = {};

  static String keyOf(double lat, double lon) =>
      '${(lat / tile).floor() * tile}_${(lon / tile).floor() * tile}';

  /// Pedaços que cobrem o retângulo.
  static List<String> keysFor(double s, double w, double n, double e) {
    final out = <String>[];
    for (var la = (s / tile).floor() * tile; la <= n; la += tile) {
      for (var lo = (w / tile).floor() * tile; lo <= e; lo += tile) {
        out.add('${la}_$lo');
      }
    }
    return out;
  }

  /// Pedaços em volta de um ponto (raio em metros).
  static List<String> keysAround(double lat, double lon, double meters) {
    final dLat = meters / 111000;
    final dLon = meters / (111000 * math.cos(lat * math.pi / 180));
    return keysFor(lat - dLat, lon - dLon, lat + dLat, lon + dLon);
  }

  /// Itens de um pedaço ('parks' ou 'radars'). null = fora da base (404)
  /// ou sem internet e sem cópia guardada — aí o app usa o Overpass.
  static Future<List<dynamic>?> get(String kind, String key) {
    final id = '$kind/$key';
    final m = _mem[id];
    if (m != null) return Future.value(m);
    return _pending[id] ??= _load(kind, key).whenComplete(() {
      _pending.remove(id);
    });
  }

  static Future<List<dynamic>?> _load(String kind, String key) async {
    final id = '$kind/$key';
    _dir ??= await getApplicationSupportDirectory();
    final f = File('${_dir!.path}/tiles/$kind/$key.json');
    List<dynamic>? cached;
    var fresh = false;
    if (await f.exists()) {
      try {
        cached = jsonDecode(await f.readAsString()) as List;
        fresh = DateTime.now().difference(await f.lastModified()) < maxAge;
      } catch (_) {}
    }
    if (cached != null && fresh) return _mem[id] = cached;
    try {
      final r = await http
          .get(Uri.parse('$_base/$kind/$key.json'))
          .timeout(const Duration(seconds: 20));
      List<dynamic>? list;
      if (r.statusCode == 200) {
        list = jsonDecode(utf8.decode(r.bodyBytes)) as List;
      } else if (r.statusCode == 404) {
        return null; // região fora da base
      }
      if (list != null) {
        await f.parent.create(recursive: true);
        await f.writeAsString(jsonEncode(list));
        return _mem[id] = list;
      }
    } catch (_) {
      // sem internet: usa a cópia antiga, se houver
    }
    if (cached != null) return _mem[id] = cached;
    return null;
  }

  /// Junta vários pedaços. null se algum falhou (sem internet e sem cópia).
  static Future<List<dynamic>?> getAll(String kind, List<String> keys) async {
    final parts = await Future.wait([for (final k in keys) get(kind, k)]);
    if (parts.any((p) => p == null)) return null;
    return [for (final p in parts) ...p!];
  }
}
