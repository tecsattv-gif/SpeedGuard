import 'dart:convert';
import 'dart:io';

import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';

/// Rota gravada (1.29.35): o caminho feito numa viagem, guardado só no
/// aparelho como arquivo GPX (abre também no OsmAnd, Sygic, My Maps…).
class SavedTrack {
  final String id;
  String name;
  final DateTime start;
  final DateTime end;
  final double km;
  final int count;
  SavedTrack(this.id, this.name, this.start, this.end, this.km, this.count);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'start': start.millisecondsSinceEpoch,
        'end': end.millisecondsSinceEpoch,
        'km': km,
        'count': count,
      };

  static SavedTrack fromJson(Map j) => SavedTrack(
        j['id'] as String,
        j['name'] as String,
        DateTime.fromMillisecondsSinceEpoch((j['start'] as num).toInt()),
        DateTime.fromMillisecondsSinceEpoch((j['end'] as num).toInt()),
        (j['km'] as num).toDouble(),
        (j['count'] as num).toInt(),
      );

  Duration get duration => end.difference(start);
}

/// Grava o caminho (um ponto a cada ~30 m) e guarda as rotas.
class TrackRecorder {
  static const minStep = 30.0; // metros entre pontos

  bool recording = false;
  /// Continuando uma rota já salva (1.29.41): id dela; null = rota nova.
  String? appendTo;
  final List<(double, double, int)> _pts = [];
  double _km = 0;
  List<SavedTrack> tracks = [];
  Directory? _dir;

  int get points => _pts.length;
  List<(double, double)> get livePts => [for (final p in _pts) (p.$1, p.$2)];
  double get km => _km;

  Future<Directory> _folder() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/tracks');
    if (!await d.exists()) await d.create(recursive: true);
    return _dir = d;
  }

  File _file(Directory d, String id) => File('${d.path}/$id.gpx');

  Future<void> load() async {
    final d = await _folder();
    final idx = File('${d.path}/index.json');
    try {
      tracks = [
        for (final j in jsonDecode(await idx.readAsString()) as List)
          SavedTrack.fromJson(j as Map)
      ];
    } catch (_) {
      tracks = [];
    }
    // Gravação interrompida (app fechado): continua de onde parou.
    final rec = File('${d.path}/_rec.txt');
    if (await rec.exists()) {
      for (final line in await rec.readAsLines()) {
        final p = line.split(',');
        if (p.length < 3) continue;
        final la = double.tryParse(p[0]), lo = double.tryParse(p[1]);
        final t = int.tryParse(p[2]);
        if (la != null && lo != null && t != null) _addRaw(la, lo, t);
      }
      recording = _pts.isNotEmpty;
      final ap = File('${d.path}/_rec_append');
      if (recording && await ap.exists()) {
        final id = (await ap.readAsString()).trim();
        if (tracks.any((t) => t.id == id)) appendTo = id;
      }
    }
  }

  Future<void> _saveIndex() async {
    final d = await _folder();
    await File('${d.path}/index.json')
        .writeAsString(jsonEncode([for (final t in tracks) t.toJson()]));
  }

  Future<void> start() async {
    final d = await _folder();
    _pts.clear();
    _km = 0;
    recording = true;
    appendTo = null;
    await File('${d.path}/_rec.txt').writeAsString('');
    final ap = File('${d.path}/_rec_append');
    if (await ap.exists()) await ap.delete();
  }

  /// Continua gravando uma rota já salva: os pontos novos entram no fim
  /// dela (1.29.41).
  Future<void> resume(SavedTrack t) async {
    final d = await _folder();
    final old = await points0(t);
    _pts.clear();
    _km = 0;
    final t0 = t.end.millisecondsSinceEpoch;
    final b = StringBuffer();
    for (final p in old) {
      _addRaw(p.$1, p.$2, t0);
      b.write('${p.$1.toStringAsFixed(6)},${p.$2.toStringAsFixed(6)},$t0\n');
    }
    // Começo real da rota (para a duração) no primeiro ponto.
    if (_pts.isNotEmpty) {
      _pts[0] = (_pts[0].$1, _pts[0].$2, t.start.millisecondsSinceEpoch);
    }
    await File('${d.path}/_rec.txt').writeAsString(b.toString());
    await File('${d.path}/_rec_append').writeAsString(t.id);
    appendTo = t.id;
    recording = true;
  }

  void _addRaw(double lat, double lon, int t) {
    if (_pts.isNotEmpty) {
      _km += Geolocator.distanceBetween(
              _pts.last.$1, _pts.last.$2, lat, lon) /
          1000;
    }
    _pts.add((lat, lon, t));
  }

  /// Nova posição do GPS durante a gravação.
  Future<void> add(Position p) async {
    if (!recording || p.accuracy > 50) return;
    if (_pts.isNotEmpty &&
        Geolocator.distanceBetween(
                _pts.last.$1, _pts.last.$2, p.latitude, p.longitude) <
            minStep) {
      return;
    }
    final t = DateTime.now().millisecondsSinceEpoch;
    _addRaw(p.latitude, p.longitude, t);
    final d = await _folder();
    await File('${d.path}/_rec.txt').writeAsString(
        '${p.latitude.toStringAsFixed(6)},${p.longitude.toStringAsFixed(6)},$t\n',
        mode: FileMode.append);
  }

  /// Para e salva. Devolve a rota (null se tinha poucos pontos).
  Future<SavedTrack?> stop(String name) async {
    recording = false;
    final d = await _folder();
    final rec = File('${d.path}/_rec.txt');
    if (await rec.exists()) await rec.delete();
    final ap = File('${d.path}/_rec_append');
    if (await ap.exists()) await ap.delete();
    final into = appendTo;
    appendTo = null;
    if (_pts.length < 2) {
      _pts.clear();
      return null;
    }
    if (into != null) {
      // Continuação: regrava a mesma rota (mesmo id), agora maior.
      final i = tracks.indexWhere((t) => t.id == into);
      if (i >= 0) {
        final pts = [for (final p in _pts) (p.$1, p.$2)];
        await _file(d, into).writeAsString(toGpx(name, pts, null));
        final t = SavedTrack(
            into,
            name,
            tracks[i].start,
            DateTime.fromMillisecondsSinceEpoch(_pts.last.$3),
            _km,
            pts.length);
        tracks[i] = t;
        await _saveIndex();
        _pts.clear();
        _km = 0;
        return t;
      }
    }
    final t = await _store(name, [for (final p in _pts) (p.$1, p.$2)],
        DateTime.fromMillisecondsSinceEpoch(_pts.first.$3),
        DateTime.fromMillisecondsSinceEpoch(_pts.last.$3),
        times: [for (final p in _pts) p.$3]);
    _pts.clear();
    _km = 0;
    return t;
  }

  Future<SavedTrack> _store(String name, List<(double, double)> pts,
      DateTime start, DateTime end,
      {List<int>? times}) async {
    final d = await _folder();
    final id = 'r${DateTime.now().millisecondsSinceEpoch}';
    var km = 0.0;
    for (var i = 1; i < pts.length; i++) {
      km += Geolocator.distanceBetween(
              pts[i - 1].$1, pts[i - 1].$2, pts[i].$1, pts[i].$2) /
          1000;
    }
    await _file(d, id).writeAsString(toGpx(name, pts, times));
    final t = SavedTrack(id, name, start, end, km, pts.length);
    tracks.insert(0, t);
    await _saveIndex();
    return t;
  }

  Future<List<(double, double)>> points0(SavedTrack t) async {
    final d = await _folder();
    try {
      return parseGpx(await _file(d, t.id).readAsString()).$2;
    } catch (_) {
      return [];
    }
  }

  Future<File> fileOf(SavedTrack t) async => _file(await _folder(), t.id);

  Future<void> rename(SavedTrack t, String name) async {
    t.name = name;
    final d = await _folder();
    final pts = await points0(t);
    await _file(d, t.id).writeAsString(toGpx(name, pts, null));
    await _saveIndex();
  }

  Future<void> delete(SavedTrack t) async {
    final d = await _folder();
    final f = _file(d, t.id);
    if (await f.exists()) await f.delete();
    tracks.removeWhere((x) => x.id == t.id);
    await _saveIndex();
  }

  /// Importa um GPX (de outro motorista ou de outro app de GPS).
  Future<SavedTrack?> importGpx(String text, String fallbackName) async {
    final (name, pts) = parseGpx(text);
    if (pts.length < 2) return null;
    final now = DateTime.now();
    return _store(name.isNotEmpty ? name : fallbackName, pts, now, now);
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String toGpx(
      String name, List<(double, double)> pts, List<int>? times) {
    final b = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<gpx version="1.1" creator="SpeedGuard" '
          'xmlns="http://www.topografix.com/GPX/1/1">')
      ..writeln('<metadata><name>${_esc(name)}</name></metadata>')
      ..writeln('<trk><name>${_esc(name)}</name><trkseg>');
    for (var i = 0; i < pts.length; i++) {
      final t = times != null && i < times.length
          ? '<time>${DateTime.fromMillisecondsSinceEpoch(times[i]).toUtc().toIso8601String()}</time>'
          : '';
      b.writeln('<trkpt lat="${pts[i].$1.toStringAsFixed(6)}" '
          'lon="${pts[i].$2.toStringAsFixed(6)}">$t</trkpt>');
    }
    b.writeln('</trkseg></trk></gpx>');
    return b.toString();
  }

  /// Lê nome e pontos de um GPX (trilha, rota ou pontos soltos).
  static (String, List<(double, double)>) parseGpx(String text) {
    final nm = RegExp(r'<name>\s*(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?\s*</name>',
            dotAll: true)
        .firstMatch(text);
    final name = (nm?.group(1) ?? '')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .trim();
    List<(double, double)> grab(String tag) {
      final out = <(double, double)>[];
      for (final m in RegExp('<$tag\\b([^>]*)').allMatches(text)) {
        final a = m.group(1)!;
        final la = RegExp(r'''lat\s*=\s*["']([-0-9.]+)''').firstMatch(a);
        final lo = RegExp(r'''lon\s*=\s*["']([-0-9.]+)''').firstMatch(a);
        if (la == null || lo == null) continue;
        out.add((double.parse(la.group(1)!), double.parse(lo.group(1)!)));
      }
      return out;
    }

    var pts = grab('trkpt');
    if (pts.length < 2) pts = grab('rtept');
    if (pts.length < 2) pts = grab('wpt');
    return (name, pts);
  }

  /// Link do Google Maps seguindo a rota: destino = fim, até 9 pontos de
  /// passagem tirados da gravação (a partir do ponto mais perto de você).
  static String googleUrl(List<(double, double)> pts, {int from = 0}) {
    final rest = pts.sublist(from.clamp(0, pts.length - 1));
    final dest = rest.last;
    final way = <(double, double)>[];
    const n = 9;
    if (rest.length > 2) {
      for (var i = 1; i <= n; i++) {
        final k = (i * (rest.length - 1) / (n + 1)).round();
        if (k > 0 && k < rest.length - 1) way.add(rest[k]);
      }
    }
    String ll((double, double) p) =>
        '${p.$1.toStringAsFixed(5)},${p.$2.toStringAsFixed(5)}';
    return 'https://www.google.com/maps/dir/?api=1'
        '&destination=${ll(dest)}'
        '${way.isEmpty ? '' : '&waypoints=${Uri.encodeComponent(way.map(ll).join('|'))}'}'
        '&travelmode=driving';
  }
}
