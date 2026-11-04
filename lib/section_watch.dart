import 'package:geolocator/geolocator.dart';

import 'models.dart';

/// Controle de velocidade média (1.29.1).
///
/// Ao passar pelo início de um trecho (radar de velocidade média marcado
/// como início), começa a medir a distância e o tempo e mostra a média.
/// Termina no radar de fim do trecho, ou depois de 40 km / 40 min sem
/// achar o fim (trecho sem fim marcado no mapa).
class SectionWatch {
  Radar? _start;
  DateTime? _since;
  double _dist = 0;
  double? _lastLat, _lastLon;
  DateTime? _lastWarn;

  bool get active => _start != null;
  int? get limit => _start?.maxSpeed;

  /// Média do trecho em km/h (null se não está num trecho ou é cedo demais).
  int? get average {
    final s = _since;
    if (s == null) return null;
    final secs = DateTime.now().difference(s).inMilliseconds / 1000;
    if (secs < 5 || _dist < 50) return null;
    return (_dist / secs * 3.6).round();
  }

  void reset() {
    _start = null;
    _since = null;
    _dist = 0;
    _lastLat = _lastLon = null;
  }

  /// Chamado a cada leitura do GPS. Devolve a frase a falar (ou null).
  String? update(Position pos, List<Radar> radars) {
    final lat = pos.latitude, lon = pos.longitude;
    if (_start != null && _lastLat != null) {
      _dist += Geolocator.distanceBetween(_lastLat!, _lastLon!, lat, lon);
    }
    _lastLat = lat;
    _lastLon = lon;

    for (final r in radars) {
      if (r.type != 'media') continue;
      final d = Geolocator.distanceBetween(lat, lon, r.lat, r.lon);
      if (d > 40) continue;
      if (r.section == 'end' && _start != null) {
        final avg = average;
        reset();
        return avg == null
            ? 'Fim do controle de velocidade média.'
            : 'Fim do controle de velocidade média. Média $avg.';
      }
      if (r.section != 'end' && (_start == null || _start!.id != r.id) &&
          pos.speed > 3) {
        _start = r;
        _since = DateTime.now();
        _dist = 0;
        final l = r.maxSpeed;
        return l == null
            ? 'Controle de velocidade média iniciado.'
            : 'Controle de velocidade média iniciado. Limite $l.';
      }
    }

    if (_start != null) {
      final secs = DateTime.now().difference(_since!).inSeconds;
      if (_dist > 40000 || secs > 2400) {
        reset();
        return null;
      }
      // Média acima do limite: avisa no máximo a cada 60 s.
      final avg = average, l = limit;
      if (avg != null && l != null && avg > l + 2) {
        final w = _lastWarn;
        if (w == null || DateTime.now().difference(w).inSeconds >= 60) {
          _lastWarn = DateTime.now();
          return 'Média $avg. Acima do limite. Reduza.';
        }
      }
    }
    return null;
  }
}
