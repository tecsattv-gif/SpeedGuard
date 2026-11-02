import 'package:flutter/material.dart';

import 'models.dart';

/// Camadas do painel "Opções do mapa": cada uma liga/desliga o que aparece
/// no mapa e o que gera aviso.
enum Layer {
  fixos('Radares fixos', 'Instalações permanentes (inclui os reportados)', Color(0xFFFF2846),
      Icons.photo_camera),
  semaforo('Radares de semáforo', 'Fiscalizam o sinal vermelho',
      Color(0xFFFFA000), Icons.traffic),
  moveis('Radares móveis', 'Controles móveis reportados pelos motoristas', Color(0xFF8C50FF),
      Icons.speed),
  fila('Filas', 'Trânsito parado ou lento', Color(0xFFFF7A2F),
      Icons.directions_car_filled),
  acidente('Acidentes', 'Acidente na via', Color(0xFFFF2846),
      Icons.car_crash),
  obra('Obras', 'Obras na pista', Color(0xFFFF7A2F), Icons.construction),
  perigo('Perigos', 'Obstáculo, avaria, pista escorregadia',
      Color(0xFFFF7A2F), Icons.warning_amber_rounded),
  policia('Polícia', 'Polícia na via', Color(0xFF3D7BFF), Icons.local_police);

  final String label;
  final String subtitle;
  final Color color;
  final IconData icon;
  const Layer(this.label, this.subtitle, this.color, this.icon);

  /// Avisos reportados pelos motoristas que somem sozinhos depois de 6 h.
  static const events = [fila, acidente, obra, perigo, policia];
  static const eventLife = Duration(hours: 6);

  bool get isEvent => events.contains(this);

  static Layer of(Radar r) {
    switch (r.type) {
      case 'semaforo':
        return semaforo;
      case 'movel':
      case 'usuario':
        return moveis;
      case 'fila':
        return fila;
      case 'acidente':
        return acidente;
      case 'obra':
        return obra;
      case 'perigo':
        return perigo;
      case 'policia':
        return policia;
      default:
        return fixos;
    }
  }
}
