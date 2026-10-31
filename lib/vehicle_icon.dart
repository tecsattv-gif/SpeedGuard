import 'package:flutter/material.dart';

import 'theme.dart';

/// Ícone da sua posição no mapa, escolhido em Configurações.
enum VehicleIcon {
  arrow('Seta', Icons.navigation),
  car('Carro', Icons.directions_car),
  truck('Caminhão', Icons.local_shipping),
  moto('Moto', Icons.two_wheeler);

  final String label;
  final IconData icon;
  const VehicleIcon(this.label, this.icon);

  static VehicleIcon fromName(String? n) =>
      values.firstWhere((v) => v.name == n, orElse: () => arrow);
}

/// Desenho visto de cima, com a frente para cima (o mapa gira pelo rumo).
class VehicleMarker extends StatelessWidget {
  final VehicleIcon type;
  final double size;
  const VehicleMarker({super.key, required this.type, this.size = 64});

  @override
  Widget build(BuildContext context) {
    if (type == VehicleIcon.arrow) {
      return Icon(Icons.navigation,
          color: SG.pink,
          size: size * 0.6,
          shadows: const [Shadow(color: Colors.black54, blurRadius: 6)]);
    }
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _VehiclePainter(type)),
    );
  }
}

class _VehiclePainter extends CustomPainter {
  final VehicleIcon type;
  _VehiclePainter(this.type);

  static const body = SG.pink;
  static const dark = Color(0xFF14081F);
  static const glass = Color(0xFFBFE6FF);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final fill = Paint()..color = body;
    final edge = Paint()
      ..color = dark
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.03;
    final win = Paint()..color = glass;
    final shadow = Paint()
      ..color = Colors.black45
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    void box(Rect r, double radius, Paint p, {bool outline = true}) {
      final rr = RRect.fromRectAndRadius(r, Radius.circular(radius));
      canvas.drawRRect(rr.shift(Offset(0, w * 0.02)), shadow);
      canvas.drawRRect(rr, p);
      if (outline) canvas.drawRRect(rr, edge);
    }

    switch (type) {
      case VehicleIcon.car:
        // Carroceria, para-brisa, vidro traseiro e retrovisores.
        final r = Rect.fromCenter(
            center: Offset(w / 2, h / 2), width: w * 0.36, height: h * 0.72);
        box(r, w * 0.09, fill);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(r.left + w * 0.04, r.top + h * 0.15,
                    r.width - w * 0.08, h * 0.12),
                Radius.circular(w * 0.03)),
            win);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(r.left + w * 0.05, r.bottom - h * 0.17,
                    r.width - w * 0.10, h * 0.08),
                Radius.circular(w * 0.03)),
            win);
        for (final dx in [-1.0, 1.0]) {
          canvas.drawOval(
              Rect.fromCenter(
                  center: Offset(w / 2 + dx * r.width * 0.58, r.top + h * 0.2),
                  width: w * 0.08,
                  height: h * 0.05),
              fill..color = body);
        }
      case VehicleIcon.truck:
        // Cavalo (cabine) na frente e carreta longa atrás.
        final cab = Rect.fromLTWH(w * 0.36, h * 0.02, w * 0.28, h * 0.2);
        final trailer = Rect.fromLTWH(w * 0.33, h * 0.25, w * 0.34, h * 0.73);
        box(trailer, w * 0.03, Paint()..color = const Color(0xFFEDE4FB));
        canvas.drawLine(Offset(w / 2, h * 0.30), Offset(w / 2, h * 0.94),
            Paint()
              ..color = const Color(0x558C50FF)
              ..strokeWidth = w * 0.02);
        box(cab, w * 0.05, fill);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(cab.left + w * 0.03, cab.top + h * 0.025,
                    cab.width - w * 0.06, h * 0.05),
                Radius.circular(w * 0.02)),
            win);
      case VehicleIcon.moto:
        // Pneu dianteiro, guidão, piloto (capacete) e pneu traseiro.
        final tyre = Paint()..color = dark;
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(
                    center: Offset(w / 2, h * 0.17),
                    width: w * 0.08,
                    height: h * 0.16),
                Radius.circular(w * 0.04)),
            tyre);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(
                    center: Offset(w / 2, h * 0.84),
                    width: w * 0.1,
                    height: h * 0.18),
                Radius.circular(w * 0.05)),
            tyre);
        box(
            Rect.fromCenter(
                center: Offset(w / 2, h * 0.52),
                width: w * 0.16,
                height: h * 0.56),
            w * 0.08,
            fill);
        canvas.drawLine(
            Offset(w * 0.30, h * 0.30),
            Offset(w * 0.70, h * 0.30),
            Paint()
              ..color = dark
              ..strokeWidth = w * 0.04
              ..strokeCap = StrokeCap.round);
        canvas.drawCircle(Offset(w / 2, h * 0.47), w * 0.1,
            Paint()..color = Colors.white);
        canvas.drawCircle(Offset(w / 2, h * 0.47), w * 0.1, edge);
      case VehicleIcon.arrow:
        break;
    }
  }

  @override
  bool shouldRepaint(_VehiclePainter old) => old.type != type;
}
