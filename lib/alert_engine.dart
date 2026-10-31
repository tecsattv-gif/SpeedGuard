import 'package:geolocator/geolocator.dart';

import 'country_rules.dart';
import 'models.dart';

/// Resultado do cálculo para a posição atual.
class AlertState {
  final Radar? radar; // radar à frente (null se nenhum)
  final double? distance; // metros
  final bool overLimit;
  final String? speak; // frase nova a falar agora (null = nada)
  const AlertState({this.radar, this.distance, this.overLimit = false, this.speak});
}

/// Decide quando avisar sobre um radar à frente.
class AlertEngine {
  final Set<String> _announced = {};
  final Set<String> _warnedSpeed = {};
  DateTime _lastZoneAlert = DateTime.fromMillisecondsSinceEpoch(0);

  static double _angleDiff(double a, double b) {
    final d = (a - b).abs() % 360;
    return d > 180 ? 360 - d : d;
  }

  AlertState update({
    required Position pos,
    required List<Radar> radars,
    required RadarMode mode,
  }) {
    if (mode == RadarMode.disabled) return const AlertState();

    final speedMs = pos.speed < 0 ? 0.0 : pos.speed;
    final speedKmh = speedMs * 3.6;
    final headingOk = speedMs > 2.5 && pos.heading >= 0;

    // Distância de aviso: ~25 s antes, entre 300 m e 1,2 km.
    final alertDist = mode == RadarMode.dangerZone
        ? 4000.0
        : (speedMs * 25).clamp(300.0, 1200.0);

    Radar? best;
    double bestDist = double.infinity;

    for (final r in radars) {
      final d = Geolocator.distanceBetween(
          pos.latitude, pos.longitude, r.lat, r.lon);

      // Saiu da área: libera para avisar de novo numa próxima passagem.
      if (d > alertDist + 400) {
        _announced.remove(r.id);
        _warnedSpeed.remove(r.id);
        continue;
      }
      if (d > alertDist) continue;

      if (headingOk) {
        final bearing = Geolocator.bearingBetween(
            pos.latitude, pos.longitude, r.lat, r.lon);
        // Precisa estar à frente (exceto bem perto, onde o GPS oscila).
        if (d > 60 && _angleDiff(pos.heading, (bearing + 360) % 360) > 50) {
          continue;
        }
        // Se o radar tem sentido conhecido, só vale para quem vai nesse sentido.
        if (r.direction != null &&
            _angleDiff(pos.heading, r.direction!) > 70) {
          continue;
        }
      }
      if (d < bestDist) {
        best = r;
        bestDist = d;
      }
    }

    if (best == null) return const AlertState();

    final over = best.maxSpeed != null && speedKmh > best.maxSpeed! + 3;
    String? speak;

    if (mode == RadarMode.dangerZone) {
      if (!_announced.contains(best.id) &&
          DateTime.now().difference(_lastZoneAlert).inMinutes >= 3) {
        speak = 'Atenção. Zona de perigo à frente.';
        _lastZoneAlert = DateTime.now();
      }
      _announced.add(best.id);
      return AlertState(radar: best, distance: null, speak: speak);
    }

    if (!_announced.contains(best.id)) {
      _announced.add(best.id);
      final m = bestDist >= 1000
          ? '1 quilômetro'
          : '${(bestDist / 50).round() * 50} metros';
      speak = best.maxSpeed != null
          ? '${best.typeLabel} a $m. Limite ${best.maxSpeed}.'
          : '${best.typeLabel} a $m.';
    } else if (over && !_warnedSpeed.contains(best.id) && bestDist < 400) {
      _warnedSpeed.add(best.id);
      speak = 'Reduza a velocidade.';
    }

    return AlertState(
        radar: best, distance: bestDist, overLimit: over, speak: speak);
  }
}
