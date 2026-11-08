import 'package:flutter/material.dart';

import 'alert_engine.dart';
import 'country_rules.dart';
import 'layers.dart';
import 'theme.dart';
import 'i18n.dart';

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
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: SG.dark
              ? [Color.lerp(SG.palette.value.deepTop, SG.bg, 0.3)!, SG.bg]
              : const [Color(0xFFE9DEFA), Color(0xFFF5F0FC)],
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
        RadarBands(green: SG.accent.withValues(alpha: 0.4)),
        const SizedBox(height: 24),
        Text(status,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, color: SG.accent)),
      ]);
    }
    final r = alert.radar;
    if (r == null) {
      return RadarBands(green: _green);
    }
    final color = alert.overLimit ? SG.red : SG.orange;
    if (mode == RadarMode.dangerZone) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.warning_amber_rounded, color: color, size: 160),
        Text(tr('ZONA DE PERIGO'),
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(tr('Respeite o limite de velocidade'),
            style: TextStyle(fontSize: 18)),
      ]);
    }
    final d = alert.distance ?? 0;
    final dist = d >= 1000
        ? '${(d / 1000).toStringAsFixed(1)} km'
        : '${(d / 10).round() * 10} m';
    // Uma faixa fica vermelha a cada aviso: 1000 m = 1 … 100 m = 6.
    final red = RadarBands.redFor(d);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          r.isEvent
              ? Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: Layer.of(r).color,
                    shape: BoxShape.circle,
                    boxShadow: SG.glow(Layer.of(r).color, 24),
                  ),
                  child: Icon(Layer.of(r).icon, color: Colors.white, size: 56),
                )
              : _LimitSign(limit: r.maxSpeed, glow: color, size: 96),
          const SizedBox(width: 18),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(dist,
                  style: TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.bold,
                      color: color,
                      height: 1,
                      shadows: [Shadow(color: color, blurRadius: 18)])),
              const SizedBox(height: 6),
              Text(r.typeLabel,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w600)),
            ],
          ),
        ]),
      ),
      const SizedBox(height: 20),
      Flexible(child: RadarBands(green: _green, red: red)),
      if (alert.overLimit) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: SG.red,
              borderRadius: BorderRadius.circular(12),
              boxShadow: SG.glow(SG.red, 16),
            ),
            child: Text(tr('REDUZA A VELOCIDADE'),
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          ),
        ],
    ]);
  }

  Color get _green =>
      SG.dark ? const Color(0xFF4ED636) : const Color(0xFF2EAA1E);
}

/// Placa de limite: círculo branco com borda vermelha.
class _LimitSign extends StatelessWidget {
  final int? limit;
  final Color glow;
  final double size;
  const _LimitSign({required this.limit, required this.glow, this.size = 170});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE0001B), width: size * 0.1),
        boxShadow: SG.glow(glow, 24),
      ),
      child: Text(
        limit?.toString() ?? '?',
        style: TextStyle(
            color: Colors.black,
            fontSize: size * 0.38,
            fontWeight: FontWeight.bold,
            height: 1),
      ),
    );
  }
}

/// Cinco faixas (setas) para cima, a de baixo maior. [red] faixas de
/// baixo para cima ficam vermelhas (uma a cada 100 m do radar).
class RadarBands extends StatelessWidget {
  final Color green;
  final int red;

  /// Tamanho fixo (painel flutuante); sem ele ocupa até 300 px.
  final double? size;
  const RadarBands({super.key, required this.green, this.red = 0, this.size});

  /// Quantas faixas ficam vermelhas a esta distância do radar:
  /// 1000 m = 1, 800 m = 2, 500 m = 3, 400 m = 4, 300 m = 5, 100 m = 6.
  static int redFor(double d) =>
      AlertEngine.stages.where((s) => d <= s + 15).length;

  @override
  Widget build(BuildContext context) {
    if (size != null) {
      return SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _ChevronPainter(green, red)),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300, maxHeight: 300),
      child: AspectRatio(
        aspectRatio: 1,
        child: CustomPaint(painter: _ChevronPainter(green, red)),
      ),
    );
  }
}

class _ChevronPainter extends CustomPainter {
  static const bands = 6;
  static const redColor = Color(0xFFFF2846);
  final Color green;
  final int red;
  _ChevronPainter(this.green, this.red);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final cx = w / 2;
    for (var i = 0; i < bands; i++) {
      // i = 0 é a de cima (menor); a de baixo (i = 5) é a primeira a ficar
      // vermelha.
      final isRed = i >= bands - red;
      final paint = Paint()..color = isRed ? redColor : green;
      final half = w * (0.45 + 0.11 * i) / 2;
      final tipY = h * (0.02 + 0.125 * i);
      final rise = half * 0.45; // inclinação dos braços
      final t = h * (0.08 + 0.01 * i); // espessura
      final path = Path()
        ..moveTo(cx, tipY)
        ..lineTo(cx + half, tipY + rise)
        ..lineTo(cx + half - half * 0.05, tipY + rise + t * 0.85)
        ..lineTo(cx, tipY + t)
        ..lineTo(cx - half + half * 0.05, tipY + rise + t * 0.85)
        ..lineTo(cx - half, tipY + rise)
        ..close();
      if (isRed) {
        canvas.drawPath(
            path,
            Paint()
              ..color = redColor.withValues(alpha: 0.6)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_ChevronPainter old) =>
      old.green != green || old.red != red;
}
