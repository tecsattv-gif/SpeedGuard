import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

/// Limpa as leituras do GPS antes de usar.
///
/// Problemas que resolve (vistos na estrada, nov/2026):
/// * leituras de antena/Wi-Fi (precisão ruim) que jogavam o veículo para
///   uma rua ao lado com velocidade 0 — o app perdia o radar da via certa;
/// * saltos impossíveis (centenas de metros em 1 s);
/// * velocidade/direção que às vezes vêm vazias (0 ou -1);
/// * buracos sem leitura (túnel, viaduto, celular atrasando o GPS): o app
///   continua andando o veículo pela última velocidade e direção por alguns
///   segundos, para não "pular" um radar.
class GpsFilter {
  /// Precisão pior que isto é descartada (se houver leitura boa recente).
  static const maxAccuracy = 35.0; // m
  /// Velocidade máxima plausível entre duas leituras.
  static const maxJumpSpeed = 75.0; // m/s ≈ 270 km/h
  /// Por quanto tempo seguir estimando sem leitura nova.
  static const maxPredict = Duration(seconds: 8);

  Position? _last; // última leitura real aceita
  DateTime? _lastAt; // quando ela chegou (relógio do celular)
  int _rejected = 0; // rejeitadas em sequência

  Position? get last => _last;

  void reset() {
    _last = null;
    _lastAt = null;
    _rejected = 0;
  }

  /// Devolve a leitura corrigida, ou null se ela deve ser ignorada.
  Position? accept(Position p) {
    final prev = _last;
    if (prev != null) {
      final dt = p.timestamp.difference(prev.timestamp).inMilliseconds / 1000;
      final fresh = dt < 20;
      // Leitura velha ou repetida.
      if (dt <= 0) return null;
      final dist = Geolocator.distanceBetween(
          prev.latitude, prev.longitude, p.latitude, p.longitude);
      final bad = (p.accuracy > maxAccuracy && fresh) ||
          (fresh && dist > 100 && dist / dt > maxJumpSpeed);
      // Muitas rejeitadas seguidas: aceita (o GPS pode ter se recuperado
      // num lugar distante de verdade).
      if (bad && _rejected < 5) {
        _rejected++;
        return null;
      }
      _rejected = 0;

      // Completa velocidade e direção que vierem vazias.
      var speed = p.speed;
      var heading = p.heading;
      final measured = dt <= 5 ? dist / dt : -1.0;
      if (speed <= 0.3 && measured > 2) speed = measured;
      if ((heading < 0 || (heading == 0 && p.headingAccuracy <= 0)) &&
          dist > 8 &&
          dt <= 5) {
        heading = (Geolocator.bearingBetween(prev.latitude, prev.longitude,
                    p.latitude, p.longitude) +
                360) %
            360;
      }
      if (speed < 2.5 && heading < 0 && prev.heading >= 0) {
        heading = prev.heading;
      }
      p = _copy(p, speed: speed, heading: heading);
    } else if (p.accuracy > 100) {
      // Primeira leitura muito ruim: espera uma melhor.
      return null;
    }
    _last = p;
    _lastAt = DateTime.now();
    return p;
  }

  /// Posição estimada agora, quando o GPS está atrasado (null se não precisa).
  Position? predict(DateTime now) {
    final p = _last;
    final at = _lastAt;
    if (p == null || at == null || p.speed < 3 || p.heading < 0) return null;
    final gap = now.difference(at);
    if (gap < const Duration(milliseconds: 1500) || gap > maxPredict) {
      return null;
    }
    final d = p.speed * gap.inMilliseconds / 1000;
    final ll = _move(p.latitude, p.longitude, p.heading, d);
    return _copy(p, lat: ll.$1, lon: ll.$2, time: now);
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

  static Position _copy(Position p,
          {double? lat,
          double? lon,
          DateTime? time,
          double? speed,
          double? heading}) =>
      Position(
        latitude: lat ?? p.latitude,
        longitude: lon ?? p.longitude,
        timestamp: time ?? p.timestamp,
        accuracy: p.accuracy,
        altitude: p.altitude,
        altitudeAccuracy: p.altitudeAccuracy,
        heading: heading ?? p.heading,
        headingAccuracy: p.headingAccuracy,
        speed: speed ?? p.speed,
        speedAccuracy: p.speedAccuracy,
        floor: p.floor,
        isMocked: p.isMocked,
      );
}
