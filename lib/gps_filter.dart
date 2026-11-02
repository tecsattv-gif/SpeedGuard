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
    _last = null;
    _lastAt = null;
    _rejected = 0;
  }

  /// Devolve a leitura (igual à do GPS), ou null se ela deve ser ignorada.
  Position? accept(Position p) {
    final prev = _last, at = _lastAt;
    if (prev != null && at != null && _rejected < 3) {
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
      }
    }
    _rejected = 0;
    _last = p;
    _lastAt = DateTime.now();
    return p;
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
