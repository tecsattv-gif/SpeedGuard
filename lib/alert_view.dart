import 'package:flutter/material.dart';

import 'alert_engine.dart';
import 'country_rules.dart';
import 'theme.dart';

/// Tela de alerta (sem mapa), no estilo do CamSam: setas verdes grandes com
/// o caminho livre; com radar à frente mostra a placa, a distância e o tipo.
class AlertView extends StatelessWidget {
  final AlertState alert;
  final RadarMode mode;
  final bool running;
  final String status;

  const AlertView({
    super.key,
    required this.alert,
    required this.mode,
    required this.running,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2A1046), SG.bg],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Padding(
          // Espaço para o painel de velocidade que fica por cima.
          padding: const EdgeInsets.fromLTRB(24, 110, 24, 24),
          child: Center(child: _content()),
        ),
      ),
    );
  }

  Widget _content() {
    if (!running) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        const _Chevrons(color: Color(0x668C50FF)),
        const SizedBox(height: 24),
        Text(status,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, color: SG.violetLight)),
      ]);
    }
    final r = alert.radar;
    if (r == null) {
      return const _Chevrons(color: Color(0xFF4ED636));
    }
    final color = alert.overLimit ? SG.red : SG.orange;
    if (mode == RadarMode.dangerZone) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.warning_amber_rounded, color: color, size: 160),
        const Text('ZONA DE PERIGO',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Respeite o limite de velocidade',
            style: TextStyle(fontSize: 18)),
      ]);
    }
    final d = alert.distance ?? 0;
    final dist = d >= 1000
        ? '${(d / 1000).toStringAsFixed(1)} km'
        : '${(d / 10).round() * 10} m';
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _LimitSign(limit: r.maxSpeed, glow: color),
        const SizedBox(height: 24),
        Text(dist,
            style: TextStyle(
                fontSize: 72,
                fontWeight: FontWeight.bold,
                color: color,
                height: 1,
                shadows: [Shadow(color: color, blurRadius: 18)])),
        const SizedBox(height: 10),
        Text(r.typeLabel,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
        if (alert.overLimit) ...[
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: SG.red,
              borderRadius: BorderRadius.circular(12),
              boxShadow: SG.glow(SG.red, 16),
            ),
            child: const Text('REDUZA A VELOCIDADE',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          ),
        ],
      ]),
    );
  }
}

/// Placa de limite: círculo branco com borda vermelha.
class _LimitSign extends StatelessWidget {
  final int? limit;
  final Color glow;
  const _LimitSign({required this.limit, required this.glow});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 170,
      height: 170,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE0001B), width: 18),
        boxShadow: SG.glow(glow, 24),
      ),
      child: Text(
        limit?.toString() ?? '?',
        style: const TextStyle(
            color: Colors.black,
            fontSize: 64,
            fontWeight: FontWeight.bold,
            height: 1),
      ),
    );
  }
}

/// Três setas para cima, a de baixo maior.
class _Chevrons extends StatelessWidget {
  final Color color;
  const _Chevrons({required this.color});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300, maxHeight: 300),
      child: AspectRatio(
        aspectRatio: 1,
        child: CustomPaint(painter: _ChevronPainter(color)),
      ),
    );
  }
}

class _ChevronPainter extends CustomPainter {
  final Color color;
  _ChevronPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final paint = Paint()..color = color;
    // (topo, largura relativa, espessura) de cada seta, de cima para baixo.
    const rows = [(0.08, 0.58, 0.13), (0.30, 0.74, 0.16), (0.53, 0.92, 0.19)];
    for (final (top, width, thick) in rows) {
      final half = w * width / 2;
      final cx = w / 2;
      final tipY = h * top;
      final rise = half * 0.62; // inclinação dos braços
      final t = h * thick;
      final path = Path()
        ..moveTo(cx, tipY)
        ..lineTo(cx + half, tipY + rise)
        ..lineTo(cx + half - half * 0.06, tipY + rise + t * 0.8)
        ..lineTo(cx, tipY + t)
        ..lineTo(cx - half + half * 0.06, tipY + rise + t * 0.8)
        ..lineTo(cx - half, tipY + rise)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_ChevronPainter old) => old.color != color;
}
