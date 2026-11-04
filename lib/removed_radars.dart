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

  int get mineCount => _mine.length;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _mine
      ..clear()
      ..addAll(p.getStringList(_key) ?? const []);
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_key, _mine.toList());
  }

  Future<void> hide(Radar r) async {
    _mine.add(r.id);
    await _save();
  }

  /// Mostra de novo todos os radares que você escondeu.
  Future<void> clearMine() async {
    _mine.clear();
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
