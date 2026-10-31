import 'package:geolocator/geolocator.dart';

import 'country_rules.dart';
import 'models.dart';

/// Resultado do cálculo para a posição atual.
class AlertState {
  final Radar? radar; // radar à frente (null se nenhum)
  final double? distance; // metros
  final bool overLimit;
  final String? speak; // frase nova a falar agora (null = nada)
  /// Som a tocar agora: 1 a 5 = aviso de 500, 400, 300, 200 ou 100 m,
  /// 6 = acima do limite, 0 = nada.
  final int beeps;
  const AlertState(
      {this.radar,
      this.distance,
      this.overLimit = false,
      this.speak,
      this.beeps = 0});
}

/// Decide quando avisar sobre um radar à frente.
class AlertEngine {
  /// Distâncias dos avisos, em metros: um a cada 100 m, de 500 m até 100 m
  /// (cada um pinta mais uma faixa de vermelho na tela de alerta).
  static const stages = [500, 400, 300, 200, 100];

  /// Último aviso dado para cada radar (1 a 5).
  final Map<String, int> _stage = {};
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

    // Radar aparece na tela a partir de 600 m; avisos a 500, 300 e 100 m.
    final alertDist = mode == RadarMode.dangerZone ? 4000.0 : 600.0;

    Radar? best;
    double bestDist = double.infinity;

    for (final r in radars) {
      final d = Geolocator.distanceBetween(
          pos.latitude, pos.longitude, r.lat, r.lon);

      // Saiu da área: libera para avisar de novo numa próxima passagem.
      if (d > alertDist + 400) {
        _stage.remove(r.id);
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

    // Em qual aviso estamos: 1 (≤500 m) … 5 (≤100 m).
    var stage = 0;
    for (var i = 0; i < stages.length; i++) {
      if (bestDist <= stages[i] + 15) stage = i + 1;
    }
    var beeps = 0;
    final done = _stage[best.id] ?? 0;
    if (stage > done) {
      // Se já chegou perto (ex.: radar apareceu a 250 m), só dá o aviso atual.
      _stage[best.id] = stage;
      beeps = stage;
      final m = '${stages[stage - 1]} metros';
      final limit = best.maxSpeed != null ? ' Limite ${best.maxSpeed}.' : '';
      // 1º aviso completo; depois só a distância; o último repete o limite.
      speak = done == 0
          ? '${best.typeLabel} a $m.$limit'
          : stage == stages.length
              ? '$m.$limit'
              : '$m.';
    } else if (over && !_warnedSpeed.contains(best.id) && bestDist < 400) {
      _warnedSpeed.add(best.id);
      speak = 'Reduza a velocidade.';
      beeps = 6;
    }

    return AlertState(
        radar: best,
        distance: bestDist,
        overLimit: over,
        speak: speak,
        beeps: beeps);
  }
}
