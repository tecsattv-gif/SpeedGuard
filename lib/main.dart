import 'dart:async';
import 'dart:convert';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'alert_engine.dart';
import 'alert_view.dart';
import 'community_service.dart';
import 'country_rules.dart';
import 'firebase_config.dart';
import 'models.dart';
import 'overlay.dart';
import 'radar_service.dart';
import 'splash_screen.dart';
import 'layers.dart';
import 'theme.dart';
import 'vehicle_icon.dart';
import 'speed_picker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Tema escolhido em Configurações (padrão: automático, segue o celular).
  try {
    final p = await SharedPreferences.getInstance();
    SG.mode.value = ThemeMode.values.firstWhere(
        (m) => m.name == p.getString('themeMode'),
        orElse: () => ThemeMode.system);
    SG.palette.value = AppPalette.byName(p.getString('palette'));
  } catch (_) {}
  runApp(const SpeedGuardApp());
}

/// Ponto de entrada da bolha flutuante (roda separado do app).
@pragma('vm:entry-point')
Future<void> overlayMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Mesmas cores do app (a paleta também chega pelos dados do painel).
  try {
    final p = await SharedPreferences.getInstance();
    SG.palette.value = AppPalette.byName(p.getString('palette'));
  } catch (_) {}
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: OverlayBubble(),
  ));
}

class SpeedGuardApp extends StatelessWidget {
  const SpeedGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Reconstrói o app quando muda o modo (claro/escuro) ou a paleta.
    return ListenableBuilder(
      listenable: Listenable.merge([SG.mode, SG.palette]),
      builder: (context, _) => MaterialApp(
        title: 'SpeedGuard',
        debugShowCheckedModeBanner: false,
        theme: SG.lightTheme(),
        darkTheme: SG.theme(),
        themeMode: SG.mode.value,
        builder: (context, child) {
          SG.dark = Theme.of(context).brightness == Brightness.dark;
          return child!;
        },
        home: const SplashScreen(next: HomePage()),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _map = MapController();
  final _service = RadarService();
  final _engine = AlertEngine();
  final _tts = FlutterTts();
  final _community = CommunityService();

  StreamSubscription<Position>? _sub;
  Position? _pos;
  bool _running = false;
  bool _follow = true;
  /// Tela cheia: true = mapa, false = tela de alerta (setas grandes).
  bool _mapView = true;
  /// Ícone da sua posição no mapa (seta, carro, caminhão ou moto).
  VehicleIcon _vehicle = VehicleIcon.arrow;
  /// Camadas ligadas no painel "Opções do mapa".
  Set<Layer> _layers = Layer.values.toSet();
  bool _voice = true;
  /// Tipo de aviso sonoro: 'voice' (fala a distância) ou 'beep' (bipes).
  String _sound = 'voice';
  /// Mostra o card "N radares carregados" só alguns segundos após atualizar.
  bool _showCount = false;
  Timer? _countTimer;
  /// Radares da área vista no mapa (ao arrastar para outra região).
  Timer? _areaTimer;
  bool _areaLoading = false;
  LatLngBounds? _areaBounds;
  bool _zoomHintShown = false;
  final _player = AudioPlayer();
  bool _discreet = false;
  bool _bubble = false;
  double _bubbleScale = 1.0; // tamanho do painel flutuante
  bool _bubbleLand = false; // formato horizontal (paisagem)
  bool _overlayShown = false;
  bool _opening = false;
  bool _inFront = true;
  bool _bubbleNoPermission = false;
  bool _loading = false;
  String? _country;
  double? _countryLat, _countryLon;
  final Set<String> _noticeShown = {};
  AlertState _alert = const AlertState();
  Radar? _ask; // radar móvel aguardando confirmação
  Timer? _askTimer;
  final Set<String> _asked = {};
  StreamSubscription? _overlaySub;
  String _status = 'Toque em INICIAR para monitorar radares';

  CountryRule get _rule => ruleFor(_country);

  /// Radares e avisos das camadas ligadas (mapa e alertas usam esta lista).
  List<Radar> get _allRadars => [
        for (final r in [..._service.all, ..._community.radars])
          if (_layers.contains(Layer.of(r))) r
      ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Respostas vindas da bolha flutuante.
    _overlaySub = FlutterOverlayWindow.overlayListener.listen((event) {
      try {
        final m = jsonDecode(event.toString()) as Map;
        if (m['answer'] is bool) _answer(m['answer'] as bool);
        // Usuário fechou o painel segurando o dedo nele.
        if (m['closed'] == true) _overlayShown = false;
        if (m['report'] == true) {
          _submitReport(
            mobile: m['mobile'] != false,
            limit: (m['limit'] as num?)?.toInt(),
            fromBubble: true,
          );
        }
      } catch (_) {}
    });
    _init();
  }

  Future<void> _init() async {
    final p = await SharedPreferences.getInstance();
    _voice = p.getBool('voice') ?? true;
    _sound = p.getString('sound') ?? 'voice';
    try {
      // Bipes abaixam a música/navegação por um instante, sem pausar.
      await _player.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.assistanceNavigationGuidance,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
      ));
    } catch (_) {}
    _discreet = p.getBool('discreet') ?? false;
    _bubble = p.getBool('bubble') ?? false;
    _bubbleScale = p.getDouble('bubbleScale') ?? 1.0;
    _bubbleLand = p.getBool('bubbleLand') ?? false;
    _mapView = p.getBool('mapView') ?? true;
    _vehicle = VehicleIcon.fromName(p.getString('vehicle'));
    final saved = p.getStringList('layers');
    if (saved != null) {
      _layers = {
        for (final l in Layer.values)
          if (saved.contains(l.name)) l
      };
    }
    _country = p.getString('country');
    await _service.load();
    await _tts.setLanguage('pt-BR');
    await _tts.setSpeechRate(0.5);
    await _tts.awaitSpeakCompletion(false);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _closeBubble();
    _overlaySub?.cancel();
    _askTimer?.cancel();
    _sub?.cancel();
    _tts.stop();
    _player.dispose();
    _countTimer?.cancel();
    _areaTimer?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // O painel é aberto já em "inactive", enquanto o app ainda está visível:
    // no Android 15+ o serviço da janela flutuante é bloqueado se for iniciado
    // com o app já em segundo plano (paused).
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _inFront = false;
      if (_running && _bubble) _showBubble();
    } else if (state == AppLifecycleState.resumed) {
      _inFront = true;
      _closeBubble();
      if (_bubbleNoPermission) {
        _bubbleNoPermission = false;
        _snack('Painel flutuante sem permissão: ative "Sobrepor a outros apps" para o SpeedGuard.');
        FlutterOverlayWindow.requestPermission();
      }
    }
  }

  Future<void> _showBubble() async {
    if (_overlayShown || _opening) return;
    _opening = true;
    try {
      if (!await FlutterOverlayWindow.isPermissionGranted()) {
        _bubbleNoPermission = true;
        return;
      }
      await FlutterOverlayWindow.showOverlay(
        height: overlayUnits(panelDp(_bubbleLand, _bubbleScale).height),
        width: overlayUnits(panelDp(_bubbleLand, _bubbleScale).width),
        alignment: OverlayAlignment.topLeft,
        enableDrag: true,
        positionGravity: PositionGravity.none,
        overlayTitle: 'SpeedGuard',
        overlayContent: 'Bolha de radares ativa',
      );
      _overlayShown = true;
      // Voltou para o app enquanto o painel abria: fecha de novo.
      if (_inFront) {
        await _closeBubble();
        return;
      }
      _sendBubble();
    } catch (_) {
    } finally {
      _opening = false;
    }
  }

  Future<void> _closeBubble() async {
    if (!_overlayShown) return;
    _overlayShown = false;
    try {
      await FlutterOverlayWindow.closeOverlay();
    } catch (_) {}
  }

  void _sendBubble() {
    if (!_overlayShown) return;
    final pos = _pos;
    final a = _alert;
    final show = a.radar != null;
    FlutterOverlayWindow.shareData(jsonEncode({
      'speed': pos == null ? 0 : (pos.speed.clamp(0, 400) * 3.6).round(),
      'dist': show ? a.distance : null,
      'limit': show ? a.radar!.maxSpeed : null,
      'over': a.overLimit,
      'ask': _ask != null,
      'scale': _bubbleScale,
      'land': _bubbleLand,
      'palette': SG.palette.value.name,
    })).catchError((_) => false);
  }

  Future<bool> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      _snack('Ative o GPS do celular.');
      await Geolocator.openLocationSettings();
      return false;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      _snack('Permissão de localização negada. Libere nas configurações.');
      await Geolocator.openAppSettings();
      return false;
    }
    return perm == LocationPermission.whileInUse ||
        perm == LocationPermission.always;
  }

  Future<void> _start() async {
    if (!await _ensurePermission()) return;
    final settings = AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
      intervalDuration: const Duration(seconds: 1),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'SpeedGuard ativo',
        notificationText: 'Monitorando radares no caminho',
        enableWakeLock: true,
      ),
    );
    _sub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_onPosition, onError: (e) => _snack('Erro no GPS: $e'));
    await WakelockPlus.enable();
    setState(() {
      _running = true;
      _status = 'Procurando sinal de GPS…';
    });
  }

  /// Zoom mínimo para baixar a área vista (evita pedir um país inteiro).
  static const _areaMinZoom = 9.0;

  Future<void> _loadArea(MapCamera camera) async {
    if (!mounted || _rule.mode != RadarMode.full) return;
    if (camera.zoom < _areaMinZoom) {
      if (!_zoomHintShown) {
        _zoomHintShown = true;
        _snack('Aproxime o mapa para ver os radares desta região.');
      }
      return;
    }
    final b = camera.visibleBounds;
    // Já baixou uma área que cobre esta? Não baixa de novo.
    final last = _areaBounds;
    if (last != null &&
        last.contains(b.northWest) &&
        last.contains(b.southEast)) {
      return;
    }
    // Pede um pouco além da tela, para arrastar sem recarregar toda hora.
    final dLat = (b.north - b.south) * 0.25;
    final dLon = (b.east - b.west) * 0.25;
    final want = LatLngBounds(LatLng(b.south - dLat, b.west - dLon),
        LatLng(b.north + dLat, b.east + dLon));
    setState(() => _areaLoading = true);
    final n = await _service.fetchArea(
        want.south, want.west, want.north, want.east);
    if (!mounted) return;
    setState(() {
      _areaLoading = false;
      if (n != null) _areaBounds = want;
    });
    if (n == null) _snack('Sem conexão para baixar os radares desta região.');
  }

  /// Fala avisos gerais (só no modo voz).
  void _say(String text) {
    if (_voice && _sound == 'voice') _tts.speak(text);
  }

  /// Bipe de cada aviso: 1 a 5 = 500 a 100 m (cada vez mais agudo),
  /// 6 = acima do limite.
  Future<void> _beep(int n) async {
    final file = n >= 6 ? 'beep_fast' : 'step$n';
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/$file.wav'));
    } catch (_) {}
  }

  Future<void> _stop() async {
    await _sub?.cancel();
    _sub = null;
    // Parou o monitoramento: o painel flutuante sai da tela.
    await _closeBubble();
    await WakelockPlus.disable();
    setState(() {
      _running = false;
      _alert = const AlertState();
      _status = 'Monitoramento parado';
    });
  }

  Future<void> _onPosition(Position pos) async {
    _pos = pos;
    if (_follow) {
      _map.move(LatLng(pos.latitude, pos.longitude), _map.camera.zoom);
    }
    _checkCountry(pos);
    if (!_loading && _service.needsRefresh(pos.latitude, pos.longitude)) {
      _refresh(pos);
    }
    if (_community.needsRefresh(pos.latitude, pos.longitude)) {
      _community.refresh(pos.latitude, pos.longitude).then((_) {
        if (mounted) setState(() {});
      });
    }
    final st = _engine.update(
        pos: pos, radars: _allRadars, mode: _rule.mode);
    if (st.speak != null || st.beeps > 0) {
      HapticFeedback.heavyImpact();
      if (_voice) {
        if (_sound == 'beep' && st.beeps > 0) {
          _beep(st.beeps);
        } else if (st.speak != null) {
          _tts.speak(!_discreet
              ? st.speak!
              : st.beeps == 6
                  ? 'Reduza.'
                  : st.beeps > 0
                      ? '${AlertEngine.stages[st.beeps - 1]} metros.'
                      : 'Radar.');
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _alert = st;
      if (_rule.mode == RadarMode.disabled) {
        _status = 'Alertas desligados neste país';
      } else if (st.radar == null) {
        _status = '${_allRadars.length} radares carregados na região';
      }
    });
    _checkAsk(pos);
    _sendBubble();
  }

  /// Ao passar perto de um radar móvel com mais de 48 h, pergunta se
  /// ele ainda está lá.
  void _checkAsk(Position pos) {
    if (_ask != null || !communityEnabled) return;
    for (final r in _community.radars) {
      if (!CommunityService.needsCheck(r) || _asked.contains(r.id)) continue;
      final d = Geolocator.distanceBetween(
          pos.latitude, pos.longitude, r.lat, r.lon);
      if (d > 150) continue;
      _asked.add(r.id);
      HapticFeedback.heavyImpact();
      _say('O radar móvel ainda está aí? Responda na tela.');
      setState(() => _ask = r);
      _askTimer?.cancel();
      _askTimer = Timer(const Duration(seconds: 40), () {
        if (mounted) setState(() => _ask = null);
        _sendBubble();
      });
      return;
    }
  }

  Future<void> _answer(bool stillThere) async {
    final r = _ask;
    if (r == null) return;
    _askTimer?.cancel();
    setState(() => _ask = null);
    _sendBubble();
    final ok = await _community.confirm(r, stillThere);
    if (!mounted) return;
    setState(() {});
    _snack(!ok
        ? 'Sem conexão: resposta não enviada.'
        : stillThere
            ? 'Obrigado! Radar mantido por mais 48 horas.'
            : 'Obrigado! Radar removido.');
  }

  Future<void> _checkCountry(Position pos) async {
    if (_countryLat != null &&
        Geolocator.distanceBetween(
                pos.latitude, pos.longitude, _countryLat!, _countryLon!) <
            20000) {
      return;
    }
    _countryLat = pos.latitude;
    _countryLon = pos.longitude;
    final code = await RadarService.detectCountry(pos.latitude, pos.longitude);
    if (code == null) return;
    if (code != _country) {
      final p = await SharedPreferences.getInstance();
      await p.setString('country', code);
      setState(() => _country = code);
    }
    final notice = _rule.notice;
    if (notice != null && _noticeShown.add(code) && mounted) {
      _say('Você entrou em ${_rule.name}.');
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(_rule.name),
          content: Text(notice),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Entendi')),
          ],
        ),
      );
    }
  }

  Future<void> _refresh(Position pos) async {
    setState(() => _loading = true);
    final n = await _service.refresh(pos.latitude, pos.longitude);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _showCount = true;
    });
    _countTimer?.cancel();
    _countTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showCount = false);
    });
    if (n == null) {
      _snack('Sem conexão para baixar radares. Usando os já salvos.');
    }
  }

  Widget _pill(IconData icon, String label, VoidCallback onTap) => Material(
        color: SG.cardHigh,
        shape: StadiumBorder(side: BorderSide(color: SG.outline, width: 1.5)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: SG.accent, size: 20),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      color: SG.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );

  /// Abre o Google Maps ou o Waze já navegando para o destino digitado
  /// (ou só abre o app, se o campo ficar vazio). O SpeedGuard continua
  /// monitorando e o painel flutuante avisa os radares por cima.
  Future<void> _navigate() async {
    final ctrl = TextEditingController();
    final app = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 0, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Navegar',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              textInputAction: TextInputAction.go,
              decoration: const InputDecoration(
                hintText: 'Para onde? (endereço, cidade ou lugar)',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => Navigator.pop(ctx, 'google'),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1A73E8),
                      minimumSize: const Size.fromHeight(52)),
                  onPressed: () => Navigator.pop(ctx, 'google'),
                  icon: const Icon(Icons.map),
                  label: const Text('Google Maps'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF33CCFF),
                      foregroundColor: Colors.black,
                      minimumSize: const Size.fromHeight(52)),
                  onPressed: () => Navigator.pop(ctx, 'waze'),
                  icon: const Icon(Icons.directions_car),
                  label: const Text('Waze'),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Text(
              _bubble
                  ? 'O SpeedGuard continua avisando os radares no painel flutuante.'
                  : 'Dica: ligue a Bolha flutuante em Configurações para ver os radares por cima do mapa.',
              textAlign: TextAlign.center,
              style: TextStyle(color: SG.textSoft, fontSize: 12),
            ),
          ],
        ),
      ),
    );
    final dest = ctrl.text.trim();
    ctrl.dispose();
    if (app == null) return;
    // Liga o monitoramento antes de sair, para avisar os radares no caminho.
    if (!_running) await _start();
    final q = Uri.encodeComponent(dest);
    final AndroidIntent intent;
    if (app == 'waze') {
      intent = AndroidIntent(
        action: 'action_view',
        data: dest.isEmpty
            ? 'https://waze.com/ul'
            : 'https://waze.com/ul?q=$q&navigate=yes',
        package: 'com.waze',
        flags: const [Flag.FLAG_ACTIVITY_NEW_TASK],
      );
    } else {
      intent = AndroidIntent(
        action: 'action_view',
        data: dest.isEmpty ? 'geo:0,0' : 'google.navigation:q=$q',
        package: 'com.google.android.apps.maps',
        flags: const [Flag.FLAG_ACTIVITY_NEW_TASK],
      );
    }
    try {
      await intent.launch();
    } catch (_) {
      _snack(app == 'waze'
          ? 'Não foi possível abrir o Waze. Ele está instalado?'
          : 'Não foi possível abrir o Google Maps. Ele está instalado?');
    }
  }

  /// Painel "Opções do mapa", como no CamSam: liga/desliga cada camada.
  Future<void> _mapOptions() async {
    Future<void> save() async {
      final p = await SharedPreferences.getInstance();
      await p.setStringList('layers', [for (final l in _layers) l.name]);
    }

    Widget item(Layer l, StateSetter setSheet) => SwitchListTile(
          secondary: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: l.color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: l.color.withValues(alpha: 0.6), blurRadius: 6)
              ],
            ),
          ),
          title: Text(l.label,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(l.isEvent
              ? '${l.subtitle} · some após 6 h'
              : l.subtitle),
          value: _layers.contains(l),
          onChanged: (v) {
            setSheet(() => v ? _layers.add(l) : _layers.remove(l));
            setState(() {});
            save();
          },
        );

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text('Opções do mapa',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ),
                for (final l in Layer.values.where((l) => !l.isEvent))
                  item(l, setSheet),
                const Divider(indent: 16, endIndent: 16),
                for (final l in Layer.events) item(l, setSheet),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text('MAIS',
                      style: TextStyle(
                          color: SG.textSoft, fontWeight: FontWeight.w600)),
                ),
                SwitchListTile(
                  secondary: Icon(Icons.my_location, color: SG.accent),
                  title: const Text('O mapa segue você',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Desloca o mapa com a sua posição'),
                  value: _follow,
                  onChanged: (v) {
                    setSheet(() {});
                    setState(() => _follow = v);
                    final pos = _pos;
                    if (v && pos != null) {
                      _map.move(LatLng(pos.latitude, pos.longitude), 16);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Reporta fila, obra, perigo ou polícia aqui (some após 6 h).
  Future<void> _submitEvent(Layer l) async {
    final pos = _pos;
    if (pos == null) {
      _snack('Aguarde o sinal do GPS para reportar.');
      return;
    }
    if (!communityEnabled) {
      _snack('Avisos precisam do Firebase configurado.');
      return;
    }
    final dir = pos.speed > 2.5 ? pos.heading : null;
    await _community.refresh(pos.latitude, pos.longitude);
    final dup =
        _community.nearby(pos.latitude, pos.longitude, dir, type: l.name);
    if (dup != null) {
      await _community.confirm(dup, true);
      if (!mounted) return;
      setState(() {});
      _snack('${l.label}: já reportado aqui. Confirmado por mais 6 h.');
      return;
    }
    final ok = await _community.report(
      lat: pos.latitude,
      lon: pos.longitude,
      mobile: false,
      direction: dir,
      event: l.name,
    );
    if (!mounted) return;
    setState(() {});
    _snack(ok
        ? '${l.label} reportado para todos. Some em 6 h.'
        : 'Sem conexão: não foi possível reportar.');
  }

  Future<void> _report() async {
    if (_pos == null) {
      _snack('Aguarde o sinal do GPS para reportar.');
      return;
    }
    final choice = await showDialog<Object>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Avisos de trânsito: um toque já reporta (somem em 6 h).
              Container(
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
                          onTap: () => Navigator.pop(ctx, l),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: l.color,
                                child: Icon(l.icon, color: Colors.white),
                              ),
                              const SizedBox(height: 4),
                              Text(l.label,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 12)),
                            ]),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SpeedPicker(
                onSelected: (c) => Navigator.pop(ctx, c),
                onCancel: () => Navigator.pop(ctx),
              ),
              const SizedBox(height: 8),
              Text(
                communityEnabled
                    ? 'Todos verão este radar. Radares móveis são confirmados a cada 48 h por quem passar.'
                    : 'O radar fica salvo só neste aparelho.',
                textAlign: TextAlign.center,
                style: TextStyle(color: SG.textSoft, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice is Layer) {
      await _submitEvent(choice);
    } else if (choice is SpeedChoice) {
      await _submitReport(mobile: choice.mobile, limit: choice.limit);
    }
  }

  /// Salva um radar reportado aqui (pelo app ou pelo botão + da bolha).
  Future<void> _submitReport({
    required bool mobile,
    int? limit,
    bool fromBubble = false,
  }) async {
    final pos = _pos;
    if (pos == null) {
      if (fromBubble) {
        _say('Sem sinal de GPS. Radar não salvo.');
      } else {
        _snack('Aguarde o sinal do GPS para reportar.');
      }
      return;
    }
    final dir = pos.speed > 2.5 ? pos.heading : null;
    var shared = false;
    if (communityEnabled) {
      // Já existe um radar aqui? Não cria outro: conta como confirmação.
      await _community.refresh(pos.latitude, pos.longitude);
      final dup = _community.nearby(pos.latitude, pos.longitude, dir);
      if (dup != null) {
        if (dup.type == 'movel') await _community.confirm(dup, true);
        if (!mounted) return;
        setState(() {});
        if (fromBubble) {
          _say('Radar já reportado. Confirmado, obrigado!');
        } else {
          _snack('Esse radar já estava reportado. Confirmado, obrigado!');
        }
        return;
      }
    }
    if (communityEnabled) {
      shared = await _community.report(
        lat: pos.latitude,
        lon: pos.longitude,
        mobile: mobile,
        maxSpeed: limit,
        direction: dir,
      );
    }
    if (!shared) {
      await _service.addUserRadar(pos.latitude, pos.longitude, limit, dir);
    }
    if (!mounted) return;
    setState(() {});
    if (fromBubble) {
      _say('Radar reportado. Obrigado!');
      return;
    }
    if (shared) {
      _snack('Radar compartilhado com todos. Obrigado!');
    } else if (communityEnabled) {
      _snack('Sem conexão: radar salvo só neste aparelho.');
    } else {
      _snack('Radar salvo neste aparelho.');
    }
  }

  void _showRadar(Radar r) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.typeLabel,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(r.maxSpeed != null
                ? 'Limite: ${r.maxSpeed} km/h'
                : 'Limite não informado'),
            if (r.type == 'usuario') ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.delete_outline),
                label: const Text('Excluir este radar'),
                onPressed: () async {
                  await _service.removeUserRadar(r.id);
                  if (!mounted) return;
                  Navigator.pop(context);
                  setState(() {});
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _settings() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('Alertas sonoros'),
                subtitle: const Text('Um aviso a cada 100 m, de 500 m até o radar'),
                value: _voice,
                onChanged: (v) async {
                  final p = await SharedPreferences.getInstance();
                  await p.setBool('voice', v);
                  setSheet(() => _voice = v);
                  setState(() {});
                },
              ),
              if (_voice)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                          value: 'voice',
                          icon: Icon(Icons.record_voice_over),
                          label: Text('Voz')),
                      ButtonSegment(
                          value: 'beep',
                          icon: Icon(Icons.notifications_active),
                          label: Text('Bipe')),
                    ],
                    selected: {_sound},
                    onSelectionChanged: (v) async {
                      final p = await SharedPreferences.getInstance();
                      await p.setString('sound', v.first);
                      setSheet(() => _sound = v.first);
                      // Amostra de como vai soar.
                      if (v.first == 'beep') {
                        _beep(1);
                      } else {
                        _tts.speak('Radar fixo a 500 metros. Limite 80.');
                      }
                    },
                  ),
                ),
              SwitchListTile(
                title: const Text('Modo discreto'),
                subtitle: const Text('Na voz, fala só a distância ("500 metros")'),
                value: _discreet,
                onChanged: (v) async {
                  final p = await SharedPreferences.getInstance();
                  await p.setBool('discreet', v);
                  setSheet(() => _discreet = v);
                },
              ),
              SwitchListTile(
                title: const Text('Bolha flutuante'),
                subtitle: const Text(
                    'Mostra velocidade e radar por cima do Maps/Waze'),
                value: _bubble,
                onChanged: (v) async {
                  if (v && !await FlutterOverlayWindow.isPermissionGranted()) {
                    final ok = await FlutterOverlayWindow.requestPermission();
                    if (ok != true) return;
                  }
                  final p = await SharedPreferences.getInstance();
                  await p.setBool('bubble', v);
                  setSheet(() => _bubble = v);
                },
              ),
              if (_bubble) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Tamanho do painel'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SegmentedButton<double>(
                    showSelectedIcon: false,
                    segments: [
                      for (final e in kPanelScales.entries)
                        ButtonSegment(value: e.value, label: Text(e.key)),
                    ],
                    selected: {_bubbleScale},
                    onSelectionChanged: (v) async {
                      final p = await SharedPreferences.getInstance();
                      await p.setDouble('bubbleScale', v.first);
                      setSheet(() => _bubbleScale = v.first);
                    },
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Formato do painel'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                          value: false,
                          icon: Icon(Icons.crop_portrait),
                          label: Text('Vertical')),
                      ButtonSegment(
                          value: true,
                          icon: Icon(Icons.crop_landscape),
                          label: Text('Horizontal')),
                    ],
                    selected: {_bubbleLand},
                    onSelectionChanged: (v) async {
                      final p = await SharedPreferences.getInstance();
                      await p.setBool('bubbleLand', v.first);
                      setSheet(() => _bubbleLand = v.first);
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: _PanelPreview(
                      landscape: _bubbleLand, scale: _bubbleScale),
                ),
                const SizedBox(height: 8),
              ],
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Ícone no mapa'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final v in VehicleIcon.values)
                      ChoiceChip(
                        avatar: Icon(v.icon, size: 18),
                        label: Text(v.label),
                        showCheckmark: false,
                        selected: _vehicle == v,
                        onSelected: (_) async {
                          final p = await SharedPreferences.getInstance();
                          await p.setString('vehicle', v.name);
                          setSheet(() => _vehicle = v);
                          setState(() {});
                        },
                      ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Cores do app'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ValueListenableBuilder<AppPalette>(
                  valueListenable: SG.palette,
                  builder: (_, cur, __) => Wrap(
                    spacing: 14,
                    runSpacing: 10,
                    children: [
                      for (final pal in AppPalette.all)
                        GestureDetector(
                          onTap: () async {
                            SG.palette.value = pal;
                            setSheet(() {});
                            _sendBubble();
                            final p = await SharedPreferences.getInstance();
                            await p.setString('palette', pal.name);
                          },
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [pal.main, pal.bg],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                border: Border.all(
                                    color: cur == pal
                                        ? SG.text
                                        : Colors.transparent,
                                    width: 3),
                                boxShadow: cur == pal
                                    ? SG.glow(pal.main, 10)
                                    : null,
                              ),
                              child: cur == pal
                                  ? const Icon(Icons.check,
                                      color: Colors.white, size: 22)
                                  : null,
                            ),
                            const SizedBox(height: 4),
                            Text(pal.name, style: const TextStyle(fontSize: 12)),
                          ]),
                        ),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Aparência'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ValueListenableBuilder<ThemeMode>(
                  valueListenable: SG.mode,
                  builder: (_, mode, __) => SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                          value: ThemeMode.system,
                          icon: Icon(Icons.brightness_auto),
                          label: Text('Auto')),
                      ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode),
                          label: Text('Claro')),
                      ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode),
                          label: Text('Escuro')),
                    ],
                    selected: {mode},
                    onSelectionChanged: (v) async {
                      SG.mode.value = v.first;
                      final p = await SharedPreferences.getInstance();
                      await p.setString('themeMode', v.first.name);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Atualizar radares agora'),
                onTap: () {
                  Navigator.pop(ctx);
                  if (_pos != null) {
                    _refresh(_pos!);
                    _community.refresh(_pos!.latitude, _pos!.longitude);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.public),
                title: Text('País: ${_rule.name}'),
                subtitle: Text(_modeLabel(_rule.mode)),
              ),
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('SpeedGuard 1.16.1'),
                subtitle: Text('Dados de radares: © colaboradores do '
                    'OpenStreetMap. Respeite sempre os limites de velocidade.'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _modeLabel(RadarMode m) {
    switch (m) {
      case RadarMode.full:
        return 'Radares visíveis com distância exata';
      case RadarMode.dangerZone:
        return 'Somente aviso de zona de perigo';
      case RadarMode.disabled:
        return 'Alertas desligados por lei';
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _radarIcon(Radar r) {
    if (r.isEvent) {
      // Fila, obra, perigo ou polícia: bolinha colorida com o símbolo.
      final l = Layer.of(r);
      return GestureDetector(
        onTap: () => _showRadar(r),
        child: Container(
          decoration: BoxDecoration(
            color: l.color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
          ),
          child: Icon(l.icon, color: Colors.white, size: 18),
        ),
      );
    }
    final color = r.type == 'usuario'
        ? SG.orange
        : (r.type == 'movel' || r.type == 'comunidade')
            ? SG.violet
        : r.type == 'semaforo'
            ? Colors.amber.shade700
            : SG.red;
    return GestureDetector(
      onTap: () => _showRadar(r),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 3),
        ),
        alignment: Alignment.center,
        // Número encolhe para caber (ex.: "130" inteiro na placa).
        child: r.maxSpeed != null
            ? Padding(
                padding: const EdgeInsets.all(4),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('${r.maxSpeed}',
                      style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: -0.5)),
                ),
              )
            : Icon(Icons.photo_camera, size: 16, color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Reconstrói a tela quando o tema (claro/escuro) muda.
    Theme.of(context);
    final pos = _pos;
    final speed = pos == null ? 0 : (pos.speed.clamp(0, 400) * 3.6).round();
    final showRadars = _rule.mode == RadarMode.full;
    final a = _alert;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: const LatLng(-15.79, -47.88),
              initialZoom: 15,
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture && _follow) setState(() => _follow = false);
                // Soltou o mapa em outra região: baixa os radares de lá.
                if (hasGesture) {
                  _areaTimer?.cancel();
                  _areaTimer = Timer(const Duration(milliseconds: 1200),
                      () => _loadArea(camera));
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.tecsattv.speedguard',
                // Modo escuro: mapa escurecido para não ofuscar à noite.
                tileBuilder: SG.dark ? darkModeTileBuilder : null,
              ),
              if (showRadars)
                MarkerLayer(
                  markers: [
                    for (final r in [
                      ..._allRadars,
                      for (final r in _service.area)
                        if (_layers.contains(Layer.of(r))) r
                    ])
                      Marker(
                        point: LatLng(r.lat, r.lon),
                        width: 34,
                        height: 34,
                        child: _radarIcon(r),
                      ),
                  ],
                ),
              if (pos != null)
                MarkerLayer(markers: [
                  Marker(
                    point: LatLng(pos.latitude, pos.longitude),
                    width: 64,
                    height: 64,
                    child: Transform.rotate(
                      angle: (pos.heading < 0 ? 0 : pos.heading) *
                          3.14159265 /
                          180,
                      child: VehicleMarker(type: _vehicle),
                    ),
                  ),
                ]),
              const SimpleAttributionWidget(
                source: Text('OpenStreetMap'),
              ),
            ],
          ),

          // Tela de alerta por cima do mapa (o mapa continua carregado).
          if (!_mapView)
            Positioned.fill(
              child: AlertView(
                alert: a,
                mode: _rule.mode,
                running: _running,
                status: _status,
              ),
            ),

          // Painel superior: velocidade e alerta
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      _SpeedBox(speed: speed, over: a.overLimit),
                      const SizedBox(width: 10),
                      Expanded(
                        // Card só aparece com radar à frente, parado, sem GPS
                        // ou logo após atualizar; atualizando: só o símbolo.
                        child: a.radar != null ||
                                !_running ||
                                _pos == null ||
                                _rule.mode == RadarMode.disabled ||
                                (_showCount && !_loading)
                            ? _alertCard(a)
                            : Align(
                                alignment: Alignment.centerRight,
                                child: _loading || _areaLoading
                                    ? const _UpdatingBadge()
                                    : const SizedBox.shrink(),
                              ),
                      ),
                    ],
                  ),
                  if (_ask != null) _askCard(),
                ],
              ),
            ),
          ),

          // Botões "Opções" (camadas do mapa) e "Navegar" (Google/Waze).
          Positioned(
            left: 12,
            bottom: 12,
            child: Row(children: [
              _pill(Icons.tune, 'Opções', _mapOptions),
              const SizedBox(width: 8),
              _pill(Icons.navigation, 'Navegar', _navigate),
            ]),
          ),

          if (_rule.mode == RadarMode.disabled && _running)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                alignment: Alignment.center,
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Alertas desligados em ${_rule.name}\n(proibido por lei)',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _follow || !_mapView
          ? null
          : FloatingActionButton.small(
              onPressed: () {
                setState(() => _follow = true);
                if (pos != null) {
                  _map.move(LatLng(pos.latitude, pos.longitude), 16);
                }
              },
              child: const Icon(Icons.my_location),
            ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: SG.page,
          border: Border(top: BorderSide(color: SG.line)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                _RoundAction(
                  tooltip: 'Configurações',
                  icon: Icons.settings,
                  onTap: _settings,
                ),
                const SizedBox(width: 10),
                _RoundAction(
                  tooltip: _mapView ? 'Tela de alerta' : 'Mapa',
                  icon: _mapView ? Icons.keyboard_double_arrow_up : Icons.map,
                  onTap: _toggleView,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MainButton(
                    running: _running,
                    onTap: _running ? _stop : _start,
                  ),
                ),
                const SizedBox(width: 10),
                _RoundAction(
                  tooltip: 'Reportar radar aqui',
                  icon: Icons.add_location_alt,
                  onTap: _report,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleView() async {
    setState(() => _mapView = !_mapView);
    final p = await SharedPreferences.getInstance();
    await p.setBool('mapView', _mapView);
  }

  Widget _askCard() {
    return Card(
      color: const Color(0xFF4A1F8C),
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            const Text('O radar móvel ainda está aqui?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1FAA6B),
                        minimumSize: const Size.fromHeight(48)),
                    onPressed: () => _answer(true),
                    icon: const Icon(Icons.check),
                    label: const Text('SIM'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: SG.red,
                        minimumSize: const Size.fromHeight(48)),
                    onPressed: () => _answer(false),
                    icon: const Icon(Icons.close),
                    label: const Text('NÃO'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _alertCard(AlertState a) {
    final hasAlert = a.radar != null;
    String title;
    String subtitle;
    if (!hasAlert) {
      title = _rule.name;
      subtitle = _status;
    } else if (_rule.mode == RadarMode.dangerZone) {
      title = 'ZONA DE PERIGO';
      subtitle = 'Respeite o limite de velocidade';
    } else {
      final d = a.distance!;
      title = d >= 1000
          ? '${(d / 1000).toStringAsFixed(1)} km'
          : '${d.round()} m';
      subtitle = a.radar!.maxSpeed != null
          ? '${a.radar!.typeLabel} • limite ${a.radar!.maxSpeed}'
          : a.radar!.typeLabel;
    }
    final accent = !hasAlert
        ? SG.violet
        : a.overLimit
            ? SG.red
            : SG.orange;
    return Container(
      decoration: BoxDecoration(
        gradient: hasAlert
            ? LinearGradient(colors: [
                accent.withValues(alpha: 0.95),
                (a.overLimit ? SG.pink : SG.red).withValues(alpha: 0.85),
              ])
            : null,
        color: hasAlert ? null : SG.card.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.8), width: 1.5),
        boxShadow: SG.glow(accent, hasAlert ? 18 : 10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold)),
            Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

/// Símbolo girando enquanto os radares da região são atualizados.
class _UpdatingBadge extends StatefulWidget {
  const _UpdatingBadge();
  @override
  State<_UpdatingBadge> createState() => _UpdatingBadgeState();
}

class _UpdatingBadgeState extends State<_UpdatingBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Atualizando radares',
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: SG.card.withValues(alpha: 0.94),
          shape: BoxShape.circle,
          border: Border.all(color: SG.violet, width: 1.5),
          boxShadow: SG.glow(SG.violet, 10),
        ),
        child: RotationTransition(
          turns: _spin,
          child: Icon(Icons.sync, color: SG.accent, size: 30),
        ),
      ),
    );
  }
}

class _SpeedBox extends StatelessWidget {
  final int speed;
  final bool over;
  const _SpeedBox({required this.speed, required this.over});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        gradient: over
            ? const LinearGradient(
                colors: [SG.red, SG.pink],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter)
            : SG.deep,
        shape: BoxShape.circle,
        border: Border.all(color: over ? Colors.white : SG.violet, width: 3),
        boxShadow: SG.glow(over ? SG.red : SG.violet, 16),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$speed',
              style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          Text('km/h',
              style: TextStyle(fontSize: 12, color: SG.violetLight)),
        ],
      ),
    );
  }
}

/// Miniatura do painel flutuante nas Configurações (proporção real).
class _PanelPreview extends StatelessWidget {
  final bool landscape;
  final double scale;
  const _PanelPreview({required this.landscape, required this.scale});

  @override
  Widget build(BuildContext context) {
    final size = panelDp(landscape, scale) * 0.6;
    final parts = [
      const FittedBox(
        child: Text('0\nKm/h',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold, height: 1.1)),
      ),
      const FittedBox(
        child: Icon(Icons.keyboard_double_arrow_up,
            color: Colors.lightGreenAccent),
      ),
      FittedBox(
        child: Icon(Icons.add_circle_outline, color: SG.violetLight),
      ),
    ];
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: size.width,
      height: size.height,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        gradient: SG.deep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: SG.violet, width: 2),
        boxShadow: SG.glow(SG.violet, 8),
      ),
      child: landscape
          ? Row(children: [for (final w in parts) Expanded(child: w)])
          : Column(children: [for (final w in parts) Expanded(child: w)]),
    );
  }
}

/// Botão principal: INICIAR em degradê vermelho→rosa; PARAR em roxo escuro.
class _MainButton extends StatelessWidget {
  final bool running;
  final VoidCallback onTap;
  const _MainButton({required this.running, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        gradient: running ? null : SG.hot,
        color: running ? SG.cardHigh : null,
        borderRadius: BorderRadius.circular(27),
        border: Border.all(
            color: running ? SG.violet : Colors.transparent, width: 1.5),
        boxShadow: SG.glow(running ? SG.violet : SG.red, running ? 10 : 18),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(27),
          onTap: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  color: Colors.white, size: 28),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(running ? 'PARAR' : 'INICIAR',
                      style: TextStyle(
                          color: running ? SG.text : Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          fontStyle: FontStyle.italic,
                          letterSpacing: 1.2)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Botão redondo secundário (configurações, reportar).
class _RoundAction extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  const _RoundAction(
      {required this.tooltip, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: SG.cardHigh,
        shape: CircleBorder(side: BorderSide(color: SG.outline, width: 1.5)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 52,
            height: 52,
            child: Icon(icon, color: SG.accent, size: 26),
          ),
        ),
      ),
    );
  }
}
