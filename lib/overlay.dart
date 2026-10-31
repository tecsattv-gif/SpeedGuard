import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'speed_picker.dart';
import 'theme.dart';

/// Tamanho base do painel, em dp. "Médio" = mesmo tamanho do painel do CamSam.
const double kBaseW = 64, kBaseH = 250; // vertical (retrato)
const double kLandW = 240, kLandH = 72; // horizontal (paisagem)
const int kPickerW = 300;
const int kPickerH = 370;

/// Tamanhos que o usuário escolhe em Configurações.
const Map<String, double> kPanelScales = {
  'Pequeno': 0.8,
  'Médio': 1.0,
  'Grande': 1.3,
};

/// Tamanho do painel em dp para o formato e a escala escolhidos.
Size panelDp(bool landscape, double scale) => landscape
    ? Size(kLandW * scale, kLandH * scale)
    : Size(kBaseW * scale, kBaseH * scale);

/// Densidade da tela (pixels por dp).
double screenDpr() =>
    WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;

/// Valor a enviar ao plugin para obter [dp] na tela. A versão publicada do
/// plugin mede a janela em pixels, então o app envia dp × densidade; o painel
/// confere o tamanho real e corrige se o plugin usar dp.
int overlayUnits(num dp, [double? unitsPerDp]) =>
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
  bool _land = false; // formato horizontal
  double _scale = 1.0; // tamanho escolhido
  bool _gotConfig = false;
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
          if (m['scale'] is num) _scale = (m['scale'] as num).toDouble();
          if (m['land'] is bool) _land = m['land'] as bool;
          _gotConfig = true;
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
    final want = panelDp(_land, _scale);
    _unitsPerDp = overlayUnits(want.width) / windowWidthDp;
    if ((windowWidthDp - want.width).abs() > 3) _resizeToPanel();
  }

  Future<void> _resizeToPanel() {
    final want = panelDp(_land, _scale);
    return FlutterOverlayWindow.resizeOverlay(
        overlayUnits(want.width, _unitsPerDp),
        overlayUnits(want.height, _unitsPerDp),
        true);
  }

  /// Fecha o painel (o monitoramento continua no app).
  Future<void> _closeSelf() async {
    HapticFeedback.heavyImpact();
    try {
      await FlutterOverlayWindow.shareData(jsonEncode({'closed': true}));
    } catch (_) {}
    await FlutterOverlayWindow.closeOverlay();
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
    await _resizeToPanel();
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
    if (!_calibrated && _gotConfig) {
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
          : Align(
              alignment: Alignment.topLeft,
              child: SizedBox.fromSize(
                size: panelDp(_land, _scale),
                // Segurar o dedo no painel fecha a janela.
                child: GestureDetector(
                  onLongPress: _closeSelf,
                  child: FittedBox(child: _panel()),
                ),
              ),
            ),
    );
  }

  Widget _panel() {
    final alert = _dist != null;
    final border = _over
        ? SG.red
        : alert
            ? SG.orange
            : SG.violet;
    const line = Color(0x558C50FF);
    final speed = Padding(
      padding: const EdgeInsets.all(4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$_speed',
                style: TextStyle(
                    color: _over ? SG.red : Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    height: 1)),
            const Text('Km/h',
                style: TextStyle(
                    color: SG.violetLight,
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
    final middle = Padding(
      padding: const EdgeInsets.all(4),
      child: FittedBox(fit: BoxFit.scaleDown, child: _middle()),
    );
    final plus = InkWell(
      onTap: _openPicker,
      child: const Center(
        child: Icon(Icons.add_circle_outline, color: SG.violetLight, size: 40),
      ),
    );
    return Container(
      width: _land ? kLandW : kBaseW,
      height: _land ? kLandH : kBaseH,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: const [Color(0xF23C1460), Color(0xF214081F)],
          begin: _land ? Alignment.centerLeft : Alignment.topCenter,
          end: _land ? Alignment.centerRight : Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border, width: 3),
        boxShadow: SG.glow(border, 10),
      ),
      child: _land
          // Horizontal: velocidade | alerta | +
          ? Row(children: [
              Expanded(flex: 4, child: speed),
              const VerticalDivider(width: 1, thickness: 1, color: line),
              Expanded(flex: 5, child: middle),
              const VerticalDivider(width: 1, thickness: 1, color: line),
              Expanded(flex: 3, child: plus),
            ])
          // Vertical: velocidade / alerta / +
          : Column(children: [
              Expanded(flex: 5, child: speed),
              const Divider(height: 1, thickness: 1, color: line),
              Expanded(flex: 7, child: middle),
              const Divider(height: 1, thickness: 1, color: line),
              Expanded(flex: 4, child: plus),
            ]),
    );
  }

  /// Parte do meio: setas livres, radar à frente, pergunta ou "Enviado".
  /// No formato horizontal os itens ficam lado a lado.
  Widget _middle() {
    Widget flow(List<Widget> c) => _land
        ? Row(mainAxisSize: MainAxisSize.min, children: c)
        : Column(mainAxisSize: MainAxisSize.min, children: c);
    final gap = SizedBox(width: _land ? 6 : 0, height: _land ? 0 : 5);

    if (_ask) {
      return flow([
        Text(_land ? 'Ainda aí?' : 'Ainda\naí?',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                height: 1.1)),
        gap,
        _round(Icons.check, const Color(0xFF1FAA6B), () => _reply(true)),
        gap,
        _round(Icons.close, SG.red, () => _reply(false)),
      ]);
    }
    if (_sent) {
      return flow([
        const Icon(Icons.check_circle, color: Colors.lightGreenAccent, size: 34),
        gap,
        const Text('Enviado',
            style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold)),
      ]);
    }
    final d = _dist;
    if (d == null) {
      // Caminho livre: setas verdes
      return const Icon(Icons.keyboard_double_arrow_up,
          color: Colors.lightGreenAccent, size: 54);
    }
    final color = _over ? SG.red : SG.orange;
    return flow([
      _limit != null
          ? SpeedSign(label: '$_limit', size: 46)
          : Icon(Icons.camera_alt, color: color, size: 38),
      gap,
      Text(
        d >= 1000 ? '${(d / 1000).toStringAsFixed(1)} km' : '${d.round()} m',
        style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold),
      ),
    ]);
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
