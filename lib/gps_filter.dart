import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

/// Filtro leve das leituras do GPS.
///
/// A velocidade e a posição mostradas na tela são as do próprio GPS, sem
/// mexer (na 1.22.0 o filtro mexia nelas e a velocidade ficou atrasada).
/// Ele só:
/// * descarta leituras de antena/Wi-Fi (precisão ruim) que chegam no meio de
///   leituras boas e jogam o veículo para uma rua ao lado com 0 km/h;
/// * descarta saltos impossíveis (centenas de metros em 1 s);
/// * estima a posição, **só para os avisos de radar**, quando o GPS fica
///   alguns segundos sem mandar leitura.
class GpsFilter {
  /// Leitura com precisão pior que isto é considerada de antena/Wi-Fi.
  static const badAccuracy = 50.0; // m
  /// Velocidade máxima plausível entre duas leituras.
  static const maxJumpSpeed = 75.0; // m/s ≈ 270 km/h

  Position? _last; // última leitura aceita
  DateTime? _lastAt; // quando ela chegou (relógio do celular)
  int _rejected = 0; // rejeitadas em sequência

  void reset() {
    _hist.clear();
    _last = null;
    _lastAt = null;
    _rejected = 0;
  }

  /// Posições recentes (para saber se o veículo está parado).
  final List<(DateTime, double, double)> _hist = [];

  /// Parado = 0 km/h (1.28.5). Parado, o GPS do celular "anda" sozinho e
  /// marcava 1, 3 e até 11 km/h. Considera parado quando o GPS diz menos de
  /// 4 km/h, ou quando em 3 s ou mais o veículo andou menos de 6 m
  /// (menos de ~7 km/h de verdade).
  Position _still(Position p) {
    final now = DateTime.now();
    _hist.add((now, p.latitude, p.longitude));
    _hist.removeWhere((h) => now.difference(h.$1).inMilliseconds > 6000);
    var stopped = p.speed * 3.6 < 4;
    if (!stopped) {
      final old = _hist.first;
      final secs = now.difference(old.$1).inMilliseconds / 1000;
      if (secs >= 3) {
        final moved = Geolocator.distanceBetween(
            old.$2, old.$3, p.latitude, p.longitude);
        stopped = moved < 6;
      }
    }
    if (!stopped) return p;
    return Position(
      latitude: p.latitude,
      longitude: p.longitude,
      timestamp: p.timestamp,
      accuracy: p.accuracy,
      altitude: p.altitude,
      altitudeAccuracy: p.altitudeAccuracy,
      heading: p.heading,
      headingAccuracy: p.headingAccuracy,
      speed: 0,
      speedAccuracy: p.speedAccuracy,
      floor: p.floor,
      isMocked: p.isMocked,
    );
  }

  /// Desaceleração máxima plausível (m/s²). Um caminhão freando forte fica
  /// em ~5 m/s²; de 90 a 0 km/h leva 4 s ou mais.
  static const maxDecel = 7.0;

  /// Devolve a leitura (igual à do GPS), ou null se ela deve ser ignorada.
  Position? accept(Position p) {
    final prev = _last, at = _lastAt;
    // 1.41.1: leitura velha (o provedor "fused" às vezes repete uma posição
    // guardada de segundos atrás) — jogava o veículo para trás e com 0 km/h.
    if (prev != null && !p.timestamp.isAfter(prev.timestamp)) return null;
    if (prev != null && at != null && _rejected < 5) {
      final age = DateTime.now().difference(at).inMilliseconds / 1000;
      if (age < 10) {
        // Leitura ruim no meio de leituras boas.
        if (p.accuracy > badAccuracy && prev.accuracy <= badAccuracy) {
          _rejected++;
          return null;
        }
        final dist = Geolocator.distanceBetween(
            prev.latitude, prev.longitude, p.latitude, p.longitude);
        if (dist > 150 && dist / math.max(age, 0.5) > maxJumpSpeed) {
          _rejected++;
          return null;
        }
        if (prev.speed > 8) {
          // 1.41.1: de 90 para 0 km/h em 1 s não existe — é leitura sem
          // velocidade (antena/Wi-Fi ou repetida). Ignora.
          final drop = prev.speed - p.speed;
          if (drop > maxDecel * math.max(age, 1.0) + 2) {
            _rejected++;
            return null;
          }
          // 1.41.1: andando rápido, ponto atrás do veículo = posição velha.
          if (prev.heading >= 0 && dist > 15) {
            final b = Geolocator.bearingBetween(
                prev.latitude, prev.longitude, p.latitude, p.longitude);
            var d = (b - prev.heading).abs() % 360;
            if (d > 180) d = 360 - d;
            if (d > 120) {
              _rejected++;
              return null;
            }
          }
        }
      }
    }
    _rejected = 0;
    final out = _still(p);
    _last = out;
    _lastAt = DateTime.now();
    return out;
  }

  /// Posição estimada agora, só para os avisos de radar, quando o GPS está
  /// 2 a 6 s sem mandar leitura e o veículo andava a mais de 30 km/h.
  Position? predict(DateTime now) {
    final p = _last, at = _lastAt;
    if (p == null || at == null || p.speed < 8 || p.heading < 0) return null;
    final gap = now.difference(at).inMilliseconds;
    if (gap < 2000 || gap > 6000) return null;
    final ll = _move(p.latitude, p.longitude, p.heading, p.speed * gap / 1000);
    return Position(
      latitude: ll.$1,
      longitude: ll.$2,
      timestamp: now,
      accuracy: p.accuracy,
      altitude: p.altitude,
      altitudeAccuracy: p.altitudeAccuracy,
      heading: p.heading,
      headingAccuracy: p.headingAccuracy,
      speed: p.speed,
      speedAccuracy: p.speedAccuracy,
      floor: p.floor,
      isMocked: p.isMocked,
    );
  }

  static (double, double) _move(
      double lat, double lon, double bearingDeg, double meters) {
    const r = 6371000.0;
    final b = bearingDeg * math.pi / 180;
    final la1 = lat * math.pi / 180, lo1 = lon * math.pi / 180;
    final dr = meters / r;
    final la2 = math.asin(math.sin(la1) * math.cos(dr) +
        math.cos(la1) * math.sin(dr) * math.cos(b));
    final lo2 = lo1 +
        math.atan2(math.sin(b) * math.sin(dr) * math.cos(la1),
            math.cos(dr) - math.sin(la1) * math.sin(la2));
    return (la2 * 180 / math.pi, lo2 * 180 / math.pi);
  }
}
