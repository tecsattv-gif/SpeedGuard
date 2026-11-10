import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Radares que não existem mais (1.29.7).
///
/// No mapa, toque no radar → "Este radar não existe mais". Ele some na hora
/// para você (fica guardado no aparelho) e o aviso vai para o Firebase.
/// Para os outros motoristas, o radar some quando 2 pessoas avisarem
/// (até 60 m um do outro). O aviso vale 90 dias: se o radar voltar e
/// continuar no mapa, ele reaparece.
class RemovedRadars {
  static const _key = 'removed_radars';
  static const sharedVotes = 2;
  static const sameMeters = 60.0;

  final Set<String> _mine = {};
  List<(double, double)> _shared = [];

  /// "Radar da outra pista" (1.29.28): id → sentido (graus) em que você
  /// andava quando marcou. Nesse sentido o radar não avisa mais; no
  /// sentido contrário (a pista dele) continua avisando.
  final Map<String, double> _wrong = {};
  static const _wrongKey = 'wrong_side';

  int get mineCount => _mine.length + _wrong.length;

  /// Muda quando a lista baixada do Firebase é trocada (cache 1.41.1).
  int get sharedStamp => identityHashCode(_shared);

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _mine
      ..clear()
      ..addAll(p.getStringList(_key) ?? const []);
    _wrong.clear();
    for (final e in p.getStringList(_wrongKey) ?? const <String>[]) {
      final i = e.lastIndexOf('|');
      final h = i > 0 ? double.tryParse(e.substring(i + 1)) : null;
      if (h != null) _wrong[e.substring(0, i)] = h;
    }
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_key, _mine.toList());
    await p.setStringList(_wrongKey,
        [for (final e in _wrong.entries) '${e.key}|${e.value.round()}']);
  }

  Future<void> markWrongSide(Radar r, double heading) async {
    _wrong[r.id] = heading;
    await _save();
  }

  /// Radar marcado como "da outra pista" para quem anda no sentido [heading].
  bool wrongSide(Radar r, double heading) {
    final h = _wrong[r.id];
    if (h == null || heading < 0) return false;
    var d = (h - heading).abs() % 360;
    if (d > 180) d = 360 - d;
    return d <= 60;
  }

  Future<void> hide(Radar r) async {
    _mine.add(r.id);
    await _save();
  }

  /// Mostra de novo todos os radares que você escondeu.
  Future<void> clearMine() async {
    _mine.clear();
    _wrong.clear();
    await _save();
  }

  /// Avisos "não existe mais" baixados do Firebase (lat, lon).
  set shared(List<(double, double)> v) => _shared = v;

  bool hidden(Radar r) {
    if (_mine.contains(r.id)) return true;
    if (_shared.length < sharedVotes || r.isEvent || r.type == 'movel') {
      return false;
    }
    // Rápido: descarta pela latitude antes de medir a distância.
    var n = 0;
    for (final (lat, lon) in _shared) {
      if ((lat - r.lat).abs() > 0.001) continue;
      if (Geolocator.distanceBetween(lat, lon, r.lat, r.lon) <= sameMeters) {
        if (++n >= sharedVotes) return true;
      }
    }
    return false;
  }
}
