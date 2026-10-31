import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'speed_picker.dart';
import 'theme.dart';

/// Tamanhos da janela flutuante, em dp (mesmo tamanho do painel do CamSam).
const int kPanelW = 64;
const int kPanelH = 250;
const int kPickerW = 300;
const int kPickerH = 370;

/// Densidade da tela (pixels por dp).
double screenDpr() =>
    WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;

/// Valor a enviar ao plugin para obter [dp] na tela. A versão publicada do
/// plugin mede a janela em pixels, então o app envia dp × densidade; o painel
/// confere o tamanho real e corrige se o plugin usar dp.
int overlayUnits(int dp, [double? unitsPerDp]) =>
    (dp * (unitsPerDp ?? screenDpr())).round();

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

  /// Quantas unidades do plugin valem 1 dp (calibrado no 1º desenho).
  double? _unitsPerDp;
  bool _calibrated = false;

  /// Mede a janela real e, se o plugin usar outra unidade, corrige o tamanho.
  void _calibrate(double windowWidthDp) {
    if (_calibrated || windowWidthDp <= 0) return;
    _calibrated = true;
    final sent = overlayUnits(kPanelW);
    _unitsPerDp = sent / windowWidthDp;
    if ((windowWidthDp - kPanelW).abs() > 3) {
      FlutterOverlayWindow.resizeOverlay(overlayUnits(kPanelW, _unitsPerDp),
          overlayUnits(kPanelH, _unitsPerDp), true);
    }
  }

  Future<void> _openPicker() async {
    await FlutterOverlayWindow.resizeOverlay(overlayUnits(kPickerW, _unitsPerDp),
        overlayUnits(kPickerH, _unitsPerDp), false);
    if (!mounted) return;
    setState(() => _picker = true);
    // Dirigindo: se ninguém escolher em 20 s, fecha sozinho.
    _pickerTimer?.cancel();
    _pickerTimer = Timer(const Duration(seconds: 20), _closePicker);
  }

  Future<void> _closePicker() async {
    _pickerTimer?.cancel();
    if (mounted) setState(() => _picker = false);
    await FlutterOverlayWindow.resizeOverlay(overlayUnits(kPanelW, _unitsPerDp),
        overlayUnits(kPanelH, _unitsPerDp), true);
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
    if (!_calibrated) {
      final w = MediaQuery.sizeOf(context).width;
      WidgetsBinding.instance.addPostFrameCallback((_) => _calibrate(w));
    }
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
        ? SG.red
        : alert
            ? SG.orange
            : SG.violet;
    return Container(
      width: kPanelW.toDouble(),
      height: kPanelH.toDouble(),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xF23C1460), Color(0xF214081F)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border, width: 3),
        boxShadow: SG.glow(border, 10),
      ),
      child: Column(
        children: [
          // Velocidade atual
          Expanded(
            flex: 5,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('$_speed',
                    style: TextStyle(
                        color: _over ? SG.red : Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        height: 1)),
                  ),
                ),
                const Text('Km/h',
                    style: TextStyle(
                        color: SG.violetLight,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0x558C50FF)),
          // Alerta / pergunta / confirmação de envio
          Expanded(flex: 7, child: _middle()),
          const Divider(height: 1, thickness: 1, color: Color(0x558C50FF)),
          // Botão reportar radar
          Expanded(
            flex: 4,
            child: InkWell(
              onTap: _openPicker,
              child: const Center(
                child: Icon(Icons.add_circle_outline,
                    color: SG.violetLight, size: 40),
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
          const Text('Ainda\naí?',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold, height: 1.1)),
          const SizedBox(height: 3),
          _round(Icons.check, const Color(0xFF1FAA6B), () => _reply(true)),
          const SizedBox(height: 4),
          _round(Icons.close, SG.red, () => _reply(false)),
        ],
      );
    }
    if (_sent) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, color: Colors.lightGreenAccent, size: 34),
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
            color: Colors.lightGreenAccent, size: 54),
      );
    }
    final color = _over ? SG.red : SG.orange;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _limit != null
            ? SpeedSign(label: '$_limit', size: 46)
            : Icon(Icons.camera_alt, color: color, size: 38),
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
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      );
}
