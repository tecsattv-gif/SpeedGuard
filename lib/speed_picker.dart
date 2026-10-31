import 'package:flutter/material.dart';

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
            color: sel ? const Color(0xFF00695C) : Colors.white12,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: sel ? Colors.white70 : Colors.white24),
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
        color: const Color(0xF2202124),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white38, width: 1.5),
        boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black54)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Reportar radar',
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
            _typeButton(true, Icons.camera_alt, 'Móvel'),
            _typeButton(false, Icons.speed, 'Fixo'),
          ]),
          const SizedBox(height: 10),
          const Text('Toque no limite de velocidade',
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
  const SpeedSign({super.key, required this.label, this.onTap, this.size = 56});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFD32F2F), width: size / 10),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: TextStyle(
                fontSize: size * 0.34,
                fontWeight: FontWeight.w900,
                color: Colors.black)),
      ),
    );
  }
}
