import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'speed_picker.dart';

/// Tamanhos da janela flutuante (em dp, como o plugin espera).
const int kPanelW = 88;
const int kPanelH = 240;
const int kPickerW = 300;
const int kPickerH = 370;

/// Painel flutuante por cima do Google Maps / Waze (estilo CamSam):
/// velocidade em cima, alerta do radar no meio e botão "+" embaixo.
/// Recebe do app principal: velocidade, distância, limite, excesso e pergunta.
/// Envia ao app: resposta da confirmação e radares reportados.
class OverlayBubble extends StatefulWidget {
  const OverlayBubble({super.key});
  @override
  State<OverlayBubble> createState() => _OverlayBubbleState();
}

class _OverlayBubbleState extends State<OverlayBubble> {
  int _speed = 0;
  double? _dist;
  int? _limit;
  bool _over = false;
  bool _ask = false;
  bool _picker = false;
  bool _sent = false;
  Timer? _pickerTimer;
  Timer? _sentTimer;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = FlutterOverlayWindow.overlayListener.listen((event) {
      try {
        final m = jsonDecode(event.toString()) as Map;
        if (!mounted) return;
        setState(() {
          _speed = (m['speed'] as num?)?.toInt() ?? 0;
          _dist = (m['dist'] as num?)?.toDouble();
          _limit = (m['limit'] as num?)?.toInt();
          _over = m['over'] == true;
          _ask = m['ask'] == true;
        });
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pickerTimer?.cancel();
    _sentTimer?.cancel();
    super.dispose();
  }

  void _reply(bool v) {
    FlutterOverlayWindow.shareData(jsonEncode({'answer': v}));
    setState(() => _ask = false);
  }

  Future<void> _openPicker() async {
    await FlutterOverlayWindow.resizeOverlay(kPickerW, kPickerH, false);
    if (!mounted) return;
    setState(() => _picker = true);
    // Dirigindo: se ninguém escolher em 20 s, fecha sozinho.
    _pickerTimer?.cancel();
    _pickerTimer = Timer(const Duration(seconds: 20), _closePicker);
  }

  Future<void> _closePicker() async {
    _pickerTimer?.cancel();
    if (mounted) setState(() => _picker = false);
    await FlutterOverlayWindow.resizeOverlay(kPanelW, kPanelH, true);
  }

  Future<void> _choose(SpeedChoice c) async {
    FlutterOverlayWindow.shareData(jsonEncode({
      'report': true,
      'mobile': c.mobile,
      'limit': c.limit,
    }));
    await _closePicker();
    if (!mounted) return;
    setState(() => _sent = true);
    _sentTimer?.cancel();
    _sentTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _sent = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: _picker
          ? Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: kPickerW.toDouble(),
                child: SpeedPicker(onSelected: _choose, onCancel: _closePicker),
              ),
            )
          : Align(alignment: Alignment.topLeft, child: _panel()),
    );
  }

  Widget _panel() {
    final alert = _dist != null;
    final border = _over
        ? Colors.red
        : alert
            ? Colors.orange
            : Colors.white;
    return Container(
      width: kPanelW.toDouble(),
      height: kPanelH.toDouble(),
      decoration: BoxDecoration(
        color: const Color(0xF22B2D31),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border, width: 3),
        boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black45)],
      ),
      child: Column(
        children: [
          // Velocidade atual
          Expanded(
            flex: 5,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('$_speed',
                    style: TextStyle(
                        color: _over ? Colors.redAccent : Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        height: 1)),
                const Text('Km/h',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Colors.black54),
          // Alerta / pergunta / confirmação de envio
          Expanded(flex: 7, child: _middle()),
          const Divider(height: 1, thickness: 1, color: Colors.black54),
          // Botão reportar radar
          Expanded(
            flex: 4,
            child: InkWell(
              onTap: _openPicker,
              child: const Center(
                child: Icon(Icons.add_circle_outline,
                    color: Colors.white60, size: 44),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _middle() {
    if (_ask) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Radar\nainda aí?',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _round(Icons.check, Colors.green.shade700, () => _reply(true)),
              const SizedBox(width: 6),
              _round(Icons.close, Colors.red.shade700, () => _reply(false)),
            ],
          ),
        ],
      );
    }
    if (_sent) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, color: Colors.lightGreenAccent, size: 40),
          Text('Enviado',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ],
      );
    }
    final d = _dist;
    if (d == null) {
      // Caminho livre: setas verdes
      return const Center(
        child: Icon(Icons.keyboard_double_arrow_up,
            color: Colors.lightGreenAccent, size: 64),
      );
    }
    final color = _over ? Colors.redAccent : Colors.orangeAccent;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _limit != null
            ? SpeedSign(label: '$_limit', size: 54)
            : Icon(Icons.camera_alt, color: color, size: 44),
        const SizedBox(height: 6),
        Text(
          d >= 1000 ? '${(d / 1000).toStringAsFixed(1)} km' : '${d.round()} m',
          style: TextStyle(
              color: color, fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _round(IconData icon, Color c, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      );
}
