import 'dart:async';
import 'dart:convert';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'alert_view.dart';
import 'layers.dart';
import 'speed_picker.dart';
import 'theme.dart';
import 'i18n.dart';

/// Tamanho base do painel, em dp. "Médio" = mesmo tamanho do painel do CamSam.
const double kBaseW = 64, kBaseH = 250; // vertical (retrato)
const double kLandW = 240, kLandH = 72; // horizontal (paisagem)
const int kPickerW = 300;
const int kPickerH = 470; // avisos de trânsito + placas

/// Pop-up "VELOCIDADE EXCEDIDA" (1.27.5).
const int kExcW = 260;
const int kExcH = 120;

/// Círculo da contagem dos 30 s ao lado do painel (1.29.4): ~2 cm.
const double kRingD = 120, kRingGap = 6;

/// Pop-up só com o círculo (bolha desligada): 50% maior (1.29.26).
const double kPopRingD = 180;

/// Pop-up do aviso de radar com o app minimizado e a bolha desligada
/// (1.31.0): o mesmo card laranja da tela do app ("883 m / Radar fixo •
/// limite 50"), no alto e no centro; o círculo da contagem fica embaixo dele.
const double kPopCardW = 320, kPopCardH = 92, kPopGap = 8;
const double kPopW = kPopCardW, kPopH = kPopCardH + kPopGap + kPopRingD;

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
  int? _road; // limite da via
  int? _overSecs; // segundos acima do limite (null = dentro)
  bool _excPopup = false; // pop-up "VELOCIDADE EXCEDIDA" aberto
  bool _excShown = false; // já mostrou neste excesso
  bool _ringOn = false; // janela com o círculo da contagem
  bool _only = false; // 1.29.15: janela só com o círculo (sem a bolha)
  bool _cardOn = false; // 1.31.0: card do radar no pop-up (sem a bolha)
  DateTime? _lastMsg;
  bool _clickThrough = false;
  Timer? _excTimer;
  String? _park; // distância do próximo park
  String? _sub; // tipo do radar e limite ("Radar fixo • limite 50")
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
    _olog('janela: iniciou');
    _sub = FlutterOverlayWindow.overlayListener.listen((event) {
      try {
        final m = jsonDecode(event.toString()) as Map;
        if (!mounted) return;
        // 1.29.23: o plugin devolve para a própria janela o que ela envia
        // ao app (resposta, reporte, aviso...). Isso não é atualização do
        // app: sem "speed", ignora — antes zerava a contagem e o modo "só o
        // círculo" e o círculo sumia.
        if (!m.containsKey('speed')) return;
        setState(() {
          _speed = (m['speed'] as num?)?.toInt() ?? 0;
          _dist = (m['dist'] as num?)?.toDouble();
          _limit = (m['limit'] as num?)?.toInt();
          _over = m['over'] == true;
          _road = (m['road'] as num?)?.toInt();
          _overSecs = (m['overSecs'] as num?)?.toInt();
          _park = m['park'] as String?;
          _sub = m['sub'] as String?;
          _ask = m['ask'] == true;
          _only = m['ringOnly'] == true;
          if (m['scale'] is num) _scale = (m['scale'] as num).toDouble();
          if (m['land'] is bool) _land = m['land'] as bool;
          if (m['palette'] is String) {
            SG.palette.value = AppPalette.byName(m['palette'] as String);
          }
          if (m['lang'] is String && kLangs.containsKey(m['lang'])) {
            appLang = m['lang'] as String;
          }
          _gotConfig = true;
        });
        // Círculo da contagem: aumenta/diminui a janela quando começa/acaba.
        final ring = _overSecs != null;
        if (_only) {
          final card = _dist != null;
          // Só o círculo (1.29.17): janela fixa do tamanho do círculo,
          // transparente e sem toque; o círculo só é desenhado na contagem.
          final now = DateTime.now();
          final gap = _lastMsg == null ||
              now.difference(_lastMsg!) > const Duration(seconds: 3);
          _lastMsg = now;
          if (gap) _clickThrough = false; // janela aberta de novo
          if (!_clickThrough) {
            _clickThrough = true;
            FlutterOverlayWindow.updateFlag(OverlayFlag.clickThrough)
                .then((v) => _olog('janela: toques passam ($v)'))
                .catchError((e) {
              _olog('janela: erro ao mudar toque $e');
              return null;
            });
          }
          if (ring != _ringOn || card != _cardOn || gap) {
            setState(() {
              _ringOn = ring;
              _cardOn = card;
            });
            // Registro do Diagnóstico (gravado pela janela).
            final what = [
              if (card) 'radar a ${_dist!.round()} m',
              if (ring) 'contagem ${_overSecs}s',
            ];
            _olog(what.isNotEmpty
                ? 'janela: ${what.join(' + ')} na tela '
                    '(${_windowWidthDp().round()} dp)'
                : 'janela: em espera (${_windowWidthDp().round()} dp)');
          }
          return;
        }
        if (ring != _ringOn) {
          setState(() => _ringOn = ring);
          if (!_excPopup && !_picker) _resizeToPanel();
        }
        // Passou dos 30 s acima do limite: pop-up uma vez por excesso.
        final secs = _overSecs;
        if (secs == null) {
          _excShown = false;
          if (_excPopup) _closeExc();
        } else if (secs >= 30 && !_excShown && !_picker) {
          _excShown = true;
          _openExc();
        }
      } catch (_) {}
    });
  }

  /// Registro da janela (1.29.23), lido em Configurações → Diagnóstico.
  static Future<void> _olog(String s) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload();
      final l = p.getStringList('overlay_log') ?? <String>[];
      l.add('${DateTime.now().toIso8601String().substring(11, 19)} $s');
      while (l.length > 15) {
        l.removeAt(0);
      }
      await p.setStringList('overlay_log', l);
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pickerTimer?.cancel();
    _sentTimer?.cancel();
    _excTimer?.cancel();
    super.dispose();
  }

  void _reply(bool v) {
    FlutterOverlayWindow.shareData(jsonEncode({'answer': v}));
    setState(() => _ask = false);
  }

  bool _calibrated = false;

  /// Mede a janela real e, se o plugin usar outra unidade, corrige o tamanho.
  void _calibrate(double windowWidthDp) {
    if (_calibrated || windowWidthDp <= 0) return;
    _calibrated = true;
    final want = _windowDp();
    if ((windowWidthDp - want.width).abs() > 3) _resizeToPanel();
  }

  /// Tamanho da janela: o painel e, durante a contagem, o círculo ao lado.
  Size _windowDp() {
    if (_only) return const Size(kPopW, kPopH);
    final p = panelDp(_land, _scale);
    if (!_ringOn) return p;
    return Size(p.width + kRingGap + kRingD,
        p.height > kRingD ? p.height : kRingD);
  }

  Future<void> _resizeToPanel() {
    final want = _windowDp();
    return _resize(want.width, want.height, true);
  }

  /// Unidade do resizeOverlay (1.29.3). No plugin publicado, o showOverlay
  /// mede em pixels, mas o resizeOverlay mede em dp. Usar a mesma conta nos
  /// dois deixava a janela ~2,5× maior que o painel depois do pop-up
  /// "VELOCIDADE EXCEDIDA" ou do menu "+": uma área invisível ia até o
  /// rodapé e roubava os toques. Agora o tamanho real é conferido depois de
  /// cada mudança e corrigido.
  double _resizeUnits = 1.0;
  int _resizeSeq = 0;

  double _windowWidthDp() {
    final v = WidgetsBinding.instance.platformDispatcher.views.first;
    return v.devicePixelRatio <= 0
        ? 0
        : v.physicalSize.width / v.devicePixelRatio;
  }

  /// Muda o tamanho da janela e, logo depois, confere o tamanho real em
  /// segundo plano (sem atrasar o desenho do painel).
  Future<void> _resize(double wDp, double hDp, bool drag) async {
    final seq = ++_resizeSeq;
    final sentW = overlayUnits(wDp, _resizeUnits);
    try {
      await FlutterOverlayWindow.resizeOverlay(
          sentW, overlayUnits(hDp, _resizeUnits), drag);
    } catch (_) {
      return;
    }
    unawaited(_checkSize(seq, sentW, wDp, hDp, drag));
  }

  Future<void> _checkSize(
      int seq, int sentW, double wDp, double hDp, bool drag) async {
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted || seq != _resizeSeq) return; // veio outra mudança depois
    if (wDp < 10) return; // janela minúscula (só o círculo, em espera)
    final got = _windowWidthDp();
    if (got <= 0 || (got - wDp).abs() <= 3) return;
    // Unidades que o plugin realmente usa por dp; corrige uma vez.
    _resizeUnits = sentW / got;
    try {
      await FlutterOverlayWindow.resizeOverlay(overlayUnits(wDp, _resizeUnits),
          overlayUnits(hDp, _resizeUnits), drag);
    } catch (_) {}
  }

  /// Abre o SpeedGuard em tela cheia (o app fecha o painel ao voltar).
  /// Usa a tela exata (MainActivity): só com o pacote, o Android não
  /// confirmava o destino e abria a janela "Completar ação usando".
  Future<void> _openApp() async {
    HapticFeedback.lightImpact();
    try {
      await const AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: 'com.tecsattv.speedguard',
        componentName: 'com.tecsattv.speedguard.MainActivity',
        flags: [
          Flag.FLAG_ACTIVITY_NEW_TASK,
          Flag.FLAG_ACTIVITY_REORDER_TO_FRONT,
        ],
      ).launch();
    } catch (_) {}
  }

  /// Fecha o painel (o monitoramento continua no app).
  /// Fecha primeiro e avisa o app depois, sem esperar resposta: com o app
  /// em segundo plano a resposta pode não chegar e o painel ficava aberto.
  Future<void> _closeSelf() async {
    HapticFeedback.heavyImpact();
    unawaited(FlutterOverlayWindow.shareData(jsonEncode({'closed': true}))
        .timeout(const Duration(seconds: 1), onTimeout: () => null)
        .catchError((_) => null));
    try {
      await FlutterOverlayWindow.closeOverlay();
    } catch (_) {}
  }

  Future<void> _openPicker() async {
    await _resize(kPickerW.toDouble(), kPickerH.toDouble(), false);
    if (!mounted) return;
    setState(() => _picker = true);
    // Dirigindo: se ninguém escolher em 20 s, fecha sozinho.
    _pickerTimer?.cancel();
    _pickerTimer = Timer(const Duration(seconds: 20), _closePicker);
  }

  Future<void> _openExc() async {
    await _resize(kExcW.toDouble(), kExcH.toDouble(), false);
    if (!mounted) return;
    setState(() => _excPopup = true);
    // Fecha sozinho em 6 s (ou com um toque); o painel continua vermelho
    // com "EXCEDIDA" até voltar ao limite.
    _excTimer?.cancel();
    _excTimer = Timer(const Duration(seconds: 6), _closeExc);
  }

  Future<void> _closeExc() async {
    _excTimer?.cancel();
    if (!_excPopup) return;
    if (mounted) setState(() => _excPopup = false);
    await _resizeToPanel();
  }

  Widget _excBox() => GestureDetector(
        onTap: _closeExc,
        child: Container(
          width: kExcW.toDouble(),
          height: kExcH.toDouble(),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [SG.red, SG.pink],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: SG.glow(SG.red, 16),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.warning_amber_rounded,
                color: Colors.white, size: 30),
            Text(tr('VELOCIDADE\nEXCEDIDA'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    height: 1.05,
                    fontWeight: FontWeight.w900)),
            Text('$_speed km/h',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
          ]),
        ),
      );

  Future<void> _closePicker() async {
    _pickerTimer?.cancel();
    if (mounted) setState(() => _picker = false);
    await _resizeToPanel();
  }

  Future<void> _choose(SpeedChoice c) => _send({
        'report': true,
        'mobile': c.mobile,
        'limit': c.limit,
      });

  /// Aviso de trânsito (fila, acidente, obra, perigo, polícia).
  Future<void> _chooseEvent(Layer l) => _send({'event': l.name});

  Future<void> _send(Map<String, Object?> data) async {
    FlutterOverlayWindow.shareData(jsonEncode(data));
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
    if (!_calibrated && _gotConfig && !_only) {
      final w = MediaQuery.sizeOf(context).width;
      WidgetsBinding.instance.addPostFrameCallback((_) => _calibrate(w));
    }
    // Antes do primeiro dado não sabe se é a bolha ou só o círculo.
    if (!_gotConfig) return const SizedBox.shrink();
    if (_only) {
      // 1.31.0: card do radar em cima e círculo da contagem embaixo; a
      // janela é transparente e deixa os toques passarem.
      return Material(
        color: Colors.transparent,
        child: Align(
          alignment: Alignment.topCenter,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_dist != null) _radarCard(_dist!),
            if (_dist != null && _overSecs != null)
              const SizedBox(height: kPopGap),
            if (_overSecs != null) _ring(_overSecs!, kPopRingD),
          ]),
        ),
      );
    }
    return Material(
      color: Colors.transparent,
      child: _excPopup && !_picker
          ? Align(alignment: Alignment.topLeft, child: _excBox())
          : _picker
          ? Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: kPickerW.toDouble(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    EventBar(onSelected: _chooseEvent),
                    SpeedPicker(onSelected: _choose, onCancel: _closePicker),
                  ],
                ),
              ),
            )
          : Align(
              alignment: Alignment.topLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox.fromSize(
                    size: panelDp(_land, _scale),
                    // Toque duplo abre o app; segurar o dedo fecha a janela.
                    child: GestureDetector(
                      onDoubleTap: _openApp,
                      onLongPress: _closeSelf,
                      child: FittedBox(child: _panel()),
                    ),
                  ),
                  if (_ringOn && _overSecs != null) ...[
                    const SizedBox(width: kRingGap),
                    _ring(_overSecs!),
                  ],
                ],
              ),
            ),
    );
  }

  /// Card do aviso de radar no pop-up (igual ao da tela do app): distância
  /// grande e embaixo o tipo do radar com o limite. Laranja; vermelho se
  /// estiver acima do limite.
  Widget _radarCard(double d) {
    final accent = _over ? SG.red : SG.orange;
    final title =
        d >= 1000 ? '${(d / 1000).toStringAsFixed(1)} km' : '${d.round()} m';
    return Container(
      width: kPopCardW,
      height: kPopCardH,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          accent.withValues(alpha: 0.97),
          (_over ? SG.pink : SG.red).withValues(alpha: 0.92),
        ]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 2),
        boxShadow: SG.glow(accent, 14),
      ),
      child: Row(children: [
        if (_limit != null) ...[
          SpeedSign(label: '$_limit', size: 52),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  maxLines: 1,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      height: 1.05,
                      fontWeight: FontWeight.w900)),
              if (_sub != null)
                Text(_sub!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ]),
    );
  }

  /// Círculo vermelho da contagem (fundo escuro desde a 1.29.5): o anel vai
  /// esvaziando e o número mostra os segundos que faltam; depois dos 30 s
  /// mostra "EXCEDIDA" até voltar ao limite.
  Widget _ring(int secs, [double d = kRingD]) {
    final left = (30 - secs).clamp(0, 30);
    final k = d / kRingD; // escala (pop-up sem a bolha: 1,5×)
    const shadow = [Shadow(color: Colors.black, blurRadius: 4)];
    return SizedBox(
      width: d,
      height: d,
      child: Stack(alignment: Alignment.center, children: [
        // 1.29.5: fundo escuro sólido, para o texto do app de baixo
        // (ex.: "WhatsApp") não aparecer atrás do número.
        Container(
            decoration:
                BoxDecoration(color: SG.bg, shape: BoxShape.circle)),
        SizedBox.expand(
          child: CircularProgressIndicator(
            value: left / 30,
            strokeWidth: 8 * k,
            color: SG.red,
            backgroundColor: SG.red.withValues(alpha: 0.25),
          ),
        ),
        left > 0
            ? Text('$left',
                style: TextStyle(
                    color: SG.red,
                    fontSize: 54 * k,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    shadows: shadow))
            : Text(tr('EXCEDIDA'),
                style: TextStyle(
                    color: SG.red,
                    fontSize: 17 * k,
                    fontWeight: FontWeight.w900,
                    shadows: shadow)),
      ]),
    );
  }

  Widget _panel() {
    final alert = _dist != null;
    final border = _over
        ? SG.red
        : alert
            ? SG.orange
            : SG.violet;
    final line = SG.line;
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
            Text(tr('Km/h'),
                style: TextStyle(
                    color: SG.violetLight,
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
            // Contagem dos 30 s acima do limite; depois "EXCEDIDA".
            if (_overSecs != null) ...[
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                    color: SG.red, borderRadius: BorderRadius.circular(8)),
                child: Text(
                    _overSecs! >= 30 ? tr('EXCEDIDA') : '${30 - _overSecs!} s',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ),
            ],
            if (_road != null) ...[
              const SizedBox(height: 2),
              SpeedSign(label: '$_road', size: 26),
            ],
            if (_park != null)
              Text('P $_park',
                  style: const TextStyle(
                      color: Color(0xFF64B5F6),
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
    // ✕ no canto: fecha o painel com um toque.
    final speedWithClose = Stack(children: [
      Positioned.fill(child: speed),
      Positioned(
        top: 0,
        right: 0,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _closeSelf,
          child: Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: SG.bg.withValues(alpha: 0.8),
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(8)),
            ),
            child: Icon(Icons.close, color: SG.violetLight, size: 14),
          ),
        ),
      ),
    ]);
    final middle = Padding(
      padding: const EdgeInsets.all(4),
      child: FittedBox(fit: BoxFit.scaleDown, child: _middle()),
    );
    final plus = InkWell(
      onTap: _openPicker,
      child: Center(
        child: Icon(Icons.add_circle_outline, color: SG.violetLight, size: 40),
      ),
    );
    return Container(
      width: _land ? kLandW : kBaseW,
      height: _land ? kLandH : kBaseH,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            SG.palette.value.deepTop,
            SG.bg
          ],
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
              Expanded(flex: 4, child: speedWithClose),
              VerticalDivider(width: 1, thickness: 1, color: line),
              Expanded(flex: 5, child: middle),
              VerticalDivider(width: 1, thickness: 1, color: line),
              Expanded(flex: 3, child: plus),
            ])
          // Vertical: velocidade / alerta / +
          : Column(children: [
              Expanded(flex: 5, child: speedWithClose),
              Divider(height: 1, thickness: 1, color: line),
              Expanded(flex: 7, child: middle),
              Divider(height: 1, thickness: 1, color: line),
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
        Text(_land ? tr('Ainda aí?') : tr('Ainda\naí?'),
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
        Text(tr('Enviado'),
            style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold)),
      ]);
    }
    final d = _dist;
    const green = Color(0xFF4ED636);
    if (d == null) {
      // Caminho livre (ou já passou do radar): todas as faixas verdes.
      return const RadarBands(green: green, size: 56);
    }
    // A cada aviso (1000, 800, 500, 400, 300 e 100 m) uma faixa fica vermelha,
    // de baixo para cima.
    final color = _over ? SG.red : SG.orange;
    final info = Column(mainAxisSize: MainAxisSize.min, children: [
      if (_limit != null) SpeedSign(label: '$_limit', size: 30),
      Text(
        d >= 1000 ? '${(d / 1000).toStringAsFixed(1)} km' : '${d.round()} m',
        style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold),
      ),
    ]);
    return flow([
      RadarBands(green: green, red: RadarBands.redFor(d), size: 50),
      gap,
      info,
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
