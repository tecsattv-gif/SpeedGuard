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

  /// Quanto tempo a "versão da base" (meta.json) vale antes de perguntar
  /// de novo ao GitHub.
  static const metaAge = Duration(hours: 3);

  static Directory? _dir;
  static final Map<String, List<dynamic>> _mem = {};

  /// Versão da base publicada (data + totais do meta.json). Um pedaço
  /// guardado com outra versão é baixado de novo, mesmo com menos de 7 dias
  /// (1.26.3: antes um pedaço baixado de uma base incompleta ficava 7 dias
  /// no celular — foi o que deixou a Alemanha sem radares).
  static String? _stamp;
  static DateTime? _stampTime;
  static Future<String?>? _stampLoading;

  /// Próximo download ignora a cópia guardada (Atualizar radares agora).
  static bool _force = false;

  /// Faz o próximo carregamento baixar tudo de novo do GitHub.
  static void forceRefresh() {
    _force = true;
    _mem.clear();
    _stampTime = null;
  }

  static Future<String?> _currentStamp() {
    if (_stamp != null &&
        _stampTime != null &&
        DateTime.now().difference(_stampTime!) < metaAge) {
      return Future.value(_stamp);
    }
    return _stampLoading ??= _loadStamp().whenComplete(() {
      _stampLoading = null;
    });
  }

  static Future<String?> _loadStamp() async {
    _dir ??= await getApplicationSupportDirectory();
    final f = File('${_dir!.path}/tiles/meta.stamp');
    try {
      final r = await http
          .get(Uri.parse('$_base/meta.json'))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) {
        final m = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
        final stamp = '${m['date']}_${m['parks']}_${m['radars']}';
        if (stamp != _stamp) {
          // Base nova: o que está na memória é da versão anterior.
          if (_stamp != null) _mem.clear();
          _stamp = stamp;
        }
        _stampTime = DateTime.now();
        await f.parent.create(recursive: true);
        await f.writeAsString(stamp);
        return stamp;
      }
    } catch (_) {}
    // Sem internet: usa a última versão conhecida.
    if (_stamp == null && await f.exists()) {
      try {
        _stamp = (await f.readAsString()).trim();
      } catch (_) {}
    }
    return _stamp;
  }
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
    final v = File('${_dir!.path}/tiles/$kind/$key.v');
    final stamp = await _currentStamp();
    List<dynamic>? cached;
    var fresh = false;
    if (await f.exists()) {
      try {
        cached = jsonDecode(await f.readAsString()) as List;
        final saved = await v.exists() ? (await v.readAsString()).trim() : '';
        fresh = !_force &&
            DateTime.now().difference(await f.lastModified()) < maxAge &&
            (stamp == null || saved == stamp);
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
        if (stamp != null) await v.writeAsString(stamp);
        return _mem[id] = list;
      }
    } catch (_) {
      // sem internet: usa a cópia antiga, se houver
    }
    if (cached != null) return _mem[id] = cached;
    return null;
  }

  /// Junta vários pedaços. Pedaço que não existe (mar, fora da base) conta
  /// como vazio; null só se nenhum pedaço veio (fora da base inteira, ou
  /// sem internet e sem cópia) — aí o app usa o Overpass.
  static Future<List<dynamic>?> getAll(String kind, List<String> keys) async {
    final parts = await Future.wait([for (final k in keys) get(kind, k)]);
    _force = false;
    if (parts.every((p) => p == null)) return null;
    return [for (final p in parts) ...?p];
  }
}
