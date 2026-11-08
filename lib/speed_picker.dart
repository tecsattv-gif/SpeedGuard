import 'package:flutter/material.dart';

import 'layers.dart';
import 'theme.dart';
import 'i18n.dart';

/// Limites prontos para reportar um radar (km/h).
const List<int> kPresetSpeeds = [30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130];

/// Resultado da escolha: tipo do radar e limite (null = "não sei").
class SpeedChoice {
  final bool mobile;
  final int? limit;
  const SpeedChoice(this.mobile, this.limit);
}

/// Janela de reportar radar: Móvel/Fixo + placas com as velocidades prontas.
/// Um toque numa placa já escolhe.
class SpeedPicker extends StatefulWidget {
  final ValueChanged<SpeedChoice> onSelected;
  final VoidCallback onCancel;
  final bool dark;
  const SpeedPicker({
    super.key,
    required this.onSelected,
    required this.onCancel,
    this.dark = true,
  });

  @override
  State<SpeedPicker> createState() => _SpeedPickerState();
}

class _SpeedPickerState extends State<SpeedPicker> {
  bool _mobile = true;

  Widget _typeButton(bool mobile, IconData icon, String label) {
    final sel = _mobile == mobile;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mobile = mobile),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            gradient: sel ? SG.hot : null,
            color: sel ? null : SG.surfaceHigh,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: sel ? Colors.white70 : SG.outline),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color.lerp(SG.palette.value.deepTop, SG.surfaceHigh, 0.5)!
                .withValues(alpha: 0.96),
            SG.bg.withValues(alpha: 0.96)
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SG.violet, width: 1.5),
        boxShadow: SG.glow(SG.violet, 16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(tr('Reportar radar'),
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
              ),
              IconButton(
                onPressed: widget.onCancel,
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ],
          ),
          Row(children: [
            _typeButton(true, Icons.camera_alt, tr('Móvel')),
            _typeButton(false, Icons.speed, tr('Fixo')),
          ]),
          const SizedBox(height: 10),
          Text(tr('Toque no limite de velocidade'),
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final v in kPresetSpeeds)
                SpeedSign(
                    label: '$v',
                    onTap: () => widget.onSelected(SpeedChoice(_mobile, v))),
              SpeedSign(
                  label: '?',
                  onTap: () => widget.onSelected(SpeedChoice(_mobile, null))),
            ],
          ),
        ],
      ),
    );
  }
}

/// Placa redonda de limite (branca com borda vermelha).
class SpeedSign extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final double size;
  /// Placa complementar com o caminhão embaixo (limite para caminhões).
  final bool truck;
  /// Foto embaixo da placa (1.29.37): portacarros, carro ou moto.
  final String? plateImage;
  const SpeedSign(
      {super.key,
      required this.label,
      this.onTap,
      this.size = 56,
      this.truck = false,
      this.plateImage});

  @override
  Widget build(BuildContext context) {
    final sign = _circle();
    final img = plateImage ?? (truck ? 'assets/portacarros.png' : null);
    if (img == null) return GestureDetector(onTap: onTap, child: sign);
    // 1.29.21: placa de caminhão embaixo, como nas estradas da Europa.
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        sign,
        Transform.translate(
          offset: Offset(0, -size * 0.08),
          // 1.29.37: placa mais larga com a foto do portacarros (sem fundo).
          child: Container(
            width: size * 1.5,
            height: size * 0.5,
            padding: EdgeInsets.symmetric(
                horizontal: size * 0.06, vertical: size * 0.04),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(size * 0.1),
              border: Border.all(color: Colors.black, width: size * 0.035),
            ),
            alignment: Alignment.center,
            child: Image.asset(img,
                fit: BoxFit.contain, filterQuality: FilterQuality.medium),
          ),
        ),
      ]),
    );
  }

  Widget _circle() {
    return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: SG.red, width: size / 10),
        ),
        alignment: Alignment.center,
        // 1.29.42: 3 algarismos (120, 130) sempre cabem — encolhe se
        // precisar e ignora o tamanho de letra grande do celular.
        padding: EdgeInsets.all(size * 0.06),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label,
              maxLines: 1,
              softWrap: false,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                  fontSize: size * 0.34,
                  fontWeight: FontWeight.w900,
                  color: Colors.black)),
        ),
    );
  }
}

/// Barra de avisos de trânsito (Filas, Acidentes, Obras, Perigos, Polícia).
/// Um toque já reporta. Usada no app e no painel flutuante.
class EventBar extends StatelessWidget {
  final ValueChanged<Layer> onSelected;
  const EventBar({super.key, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: SG.surfaceHigh.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SG.outline),
      ),
      child: Row(
        children: [
          for (final l in Layer.events)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onSelected(l),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: l.color,
                      child: Icon(l.icon, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(l.label,
                          maxLines: 1,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12)),
                    ),
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
