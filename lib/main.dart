import 'update_service.dart';
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
import 'presence_service.dart';
import 'radar_service.dart';
import 'splash_screen.dart';
import 'layers.dart';
import 'theme.dart';
import 'tutorial_page.dart';
import 'vehicle_icon.dart';
import 'gps_filter.dart';
import 'park_service.dart';
import 'road_limit.dart';
import 'route_service.dart';
import 'removed_radars.dart';
import 'section_watch.dart';
import 'speed_watch.dart';
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
/// Valores do seletor "Limitador do caminhão" (1.29.19): de 80 a 95 de 1
/// em 1 e depois de 10 em 10 até 130.
const List<int> kTruckLimits = [
  80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, //
  100, 110, 120, 130,
];

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
  final _removed = RemovedRadars();
  /// Quantas pessoas estão conectadas (mundo e país).
  final _presence = PresenceService();
  Timer? _presenceTimer;

  StreamSubscription<Position>? _sub;
  Position? _pos;
  final _gps = GpsFilter();
  final _roads = RoadLimitService();
  final _parks = ParkService();
  final _route = RouteService();
  /// Parks à frente (área de descanso/serviço, estacionamento de caminhão).
  List<ParkAhead> _parksAhead = const [];
  bool _showParks = true;
  bool _parkOpen = false;
  final _watch = SpeedWatch();
  final _section = SectionWatch(); // velocidade média (1.29.1)
  /// Aviso de velocidade excedida ligado (Configurações).
  bool _speedWarn = true;
  /// Velocidade máxima do caminhão (limitador), em km/h.
  int _truckMax = 90;
  /// Limite da via atual, se conhecido.
  int? _roadLimit;
  /// Limite da via já avisado ao caminhão (para não repetir).
  int? _roadWarned;
  Timer? _predictTimer;
  bool _running = false;
  bool _follow = true;
  // 1.29.10: mapa gira com o veículo (a seta fica sempre para cima).
  bool _headingUp = true;
  double _mapRot = 0;
  /// Tela cheia: true = mapa, false = tela de alerta (setas grandes).
  bool _mapView = true;
  /// Ícone da sua posição no mapa (seta, carro, caminhão ou moto).
  VehicleIcon _vehicle = VehicleIcon.arrow;
  /// Camadas ligadas no painel "Opções do mapa".
  Set<Layer> _layers = Layer.values.toSet();
  bool _voice = true;
  /// Tipo de aviso sonoro: 'voice' (fala a distância) ou 'beep' (bipes).
  String _sound = 'voice';
  /// Aviso de velocidade excedida: 'voice' ou 'beep' (1.27.2).
  String _speedSound = 'voice';
  /// Só avisar radares da via onde o veículo está (1.28.0).
  bool _sameRoad = true;
  /// Volume dos avisos (voz e bipes), 0.1 a 1.0 (1.27.3).
  double _volume = 1.0;
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
  // 1.29.15: janela só com o círculo da contagem (app minimizado sem bolha).
  bool _ringPopup = false;
  // 1.29.17: teste do pop-up (contagem de mentira, sem precisar correr).
  int? _testSecs;
  Timer? _testTimer;

  /// Registro do pop-up da contagem (1.29.20), em Configurações →
  /// Diagnóstico: mostra cada passo para achar por que não aparece.
  final List<String> _popLog = [];
  void _plog(String s) {
    final t = DateTime.now().toIso8601String().substring(11, 19);
    _popLog.add('$t $s');
    if (_popLog.length > 40) _popLog.removeAt(0);
    SharedPreferences.getInstance()
        .then((p) => p.setStringList('popup_log', _popLog))
        .catchError((_) => false);
  }

  /// Segundos da contagem (a de verdade ou a do teste).
  int? get _countSecs =>
      _testSecs ?? (_running && _speedWarn ? _watch.seconds : null);

  /// Testar pop-up: conta de 0 a 35 s; o usuário minimiza o app e vê o
  /// círculo por cima do outro app.
  /// 1.29.22: o toque só "arma" o teste; a contagem começa quando o app é
  /// minimizado (antes começava no toque e, se demorasse mais de 35 s para
  /// minimizar, o teste já tinha acabado).
  DateTime? _testArmed;
  void _testRing() {
    _testTimer?.cancel();
    _testSecs = null;
    _testArmed = DateTime.now();
    _plog('teste armado');
    _snack('Teste pronto: agora minimize o SpeedGuard e abra outro app (ex.: YouTube).');
  }

  void _startTestCount() {
    _testArmed = null;
    _testTimer?.cancel();
    _testSecs = 0;
    _plog('teste: contagem começou');
    _testTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final s = (_testSecs ?? 0) + 1;
      _testSecs = s > 35 ? null : s;
      if (_testSecs == null) t.cancel();
      _syncRingPopup();
      _sendBubble();
    });
  }
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
  List<Radar> get _allRadars {
    _removed.shared = _community.removed;
    return _allRadarsRaw;
  }

  List<Radar> get _allRadarsRaw => [
        for (final r in [..._service.all, ..._community.radars])
          if (_layers.contains(Layer.of(r)) && !_removed.hidden(r)) r
      ];

  /// Radares a desenhar no mapa: só os da área da tela (com margem) e no
  /// máximo [_maxMarkers], os mais perto do centro (1.28.3). Com o raio de
  /// 60 km, em cidade grande eram mais de 1.000 marcadores redesenhados a
  /// cada leitura do GPS, o que travava o velocímetro e o ícone do veículo.
  static const _maxMarkers = 250;
  List<Radar> _visibleRadars() {
    final all = [
      ..._allRadars,
      for (final r in _service.area)
        if (_layers.contains(Layer.of(r)) && !_removed.hidden(r)) r
    ];
    LatLngBounds? b;
    try {
      b = _map.camera.visibleBounds;
    } catch (_) {}
    if (b == null) return all.length > _maxMarkers ? all.sublist(0, _maxMarkers) : all;
    final mLat = (b.north - b.south) * 0.2;
    final mLon = (b.east - b.west) * 0.2;
    final inView = [
      for (final r in all)
        if (r.lat >= b.south - mLat &&
            r.lat <= b.north + mLat &&
            r.lon >= b.west - mLon &&
            r.lon <= b.east + mLon)
          r
    ];
    if (inView.length <= _maxMarkers) return inView;
    final cLat = (b.north + b.south) / 2, cLon = (b.east + b.west) / 2;
    double d2(Radar r) =>
        (r.lat - cLat) * (r.lat - cLat) + (r.lon - cLon) * (r.lon - cLon);
    inView.sort((x, y) => d2(x).compareTo(d2(y)));
    return inView.sublist(0, _maxMarkers);
  }

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
        if (m['closed'] == true) {
          _overlayShown = false;
          _ringPopup = false;
        }
        if (m['event'] is String) {
          final l = Layer.values.where((x) => x.name == m['event']);
          if (l.isNotEmpty && l.first.isEvent) {
            _submitEvent(l.first, fromBubble: true);
          }
        }
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
    // Nova versão no GitHub? Pergunta sempre que o app abre (1.29.13).
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) UpdateService.autoCheck(context);
    });
  }

  Future<void> _init() async {
    final p = await SharedPreferences.getInstance();
    await _removed.load();
    _voice = p.getBool('voice') ?? true;
    _speedWarn = p.getBool('speed_warn') ?? true;
    _showParks = p.getBool('show_parks') ?? true;
    _parks.truckOnly = p.getBool('parks_truck_only') ?? true;
    _truckMax = p.getInt('truck_max') ?? 90;
    if (!kTruckLimits.contains(_truckMax)) _truckMax = 90;
    _sound = p.getString('sound') ?? 'voice';
    _speedSound = p.getString('speed_sound') ?? 'voice';
    _sameRoad = p.getBool('same_road') ?? true;
    _volume = p.getDouble('volume') ?? 1.0;
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
    _headingUp = p.getBool('map_heading_up') ?? true;
    _vehicle = VehicleIcon.fromName(p.getString('vehicle'));
    final saved = p.getStringList('layers');
    if (saved != null) {
      // Camadas novas (ex.: acidente) vêm ligadas para quem já tinha opções salvas.
      final known = p.getStringList('layersKnown') ??
          const ['fixos', 'semaforo', 'moveis', 'fila', 'obra', 'perigo', 'policia'];
      _layers = {
        for (final l in Layer.values)
          if (saved.contains(l.name) || !known.contains(l.name)) l
      };
    }
    _country = p.getString('country');
    await _service.load();
    await _tts.setLanguage('pt-BR');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(_volume);
    await _tts.awaitSpeakCompletion(false);
    if (mounted) setState(() {});
    _presenceTick();
    _presenceTimer =
        Timer.periodic(PresenceService.beat, (_) => _presenceTick());
  }

  /// A cada minuto: avisa que está conectado (app aberto ou monitorando)
  /// e, com o app na tela, atualiza os cards de conectados.
  Future<void> _presenceTick() async {
    if (!_inFront && !_running) return;
    await _presence.ping(_country);
    if (!_inFront) return;
    final ok = await _presence.refresh(_country);
    if (ok && mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presenceTimer?.cancel();
    _closeBubble();
    _overlaySub?.cancel();
    _askTimer?.cancel();
    _sub?.cancel();
    _predictTimer?.cancel();
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
    _plog('app ${state.name} (monit. ${_running ? 'on' : 'off'}, bolha '
        '${_bubble ? 'on' : 'off'}, teste ${_testSecs ?? '-'}, '
        'janela ${_overlayShown ? 'aberta' : 'fechada'}'
        '${_opening ? ', abrindo' : ''})');
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _inFront = false;
      final armed = _testArmed;
      if (armed != null) {
        if (DateTime.now().difference(armed).inMinutes < 3) {
          _startTestCount();
        } else {
          _testArmed = null;
        }
      }
      if (_running && _bubble) _showBubble();
      // 1.29.16: sem a bolha, abre já agora (app ainda visível) a janela do
      // círculo da contagem, minúscula e invisível; ela cresce quando a
      // contagem começa. Aberta depois, com o app em segundo plano, o
      // Android 15 bloqueava e o pop-up não aparecia.
      if (!_bubble && ((_running && _speedWarn) || _testSecs != null)) {
        _showRing();
      }
    } else if (state == AppLifecycleState.resumed) {
      _inFront = true;
      _closeBubble();
      _presenceTick();
      if (mounted) UpdateService.autoCheck(context, resumed: true);
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

  /// Contagem dos 30 s com o app minimizado e a bolha desligada (1.29.15):
  /// abre por cima do app da tela um pop-up só com o círculo vermelho da
  /// contagem (igual ao da bolha) e fecha quando volta ao limite.
  /// Bipe quando o pop-up da contagem entra na tela (1.29.18; desde a
  /// 1.29.22 o mesmo bipe do 1º aviso de radar).
  bool _ringBeeped = false;
  void _ringBeep() {
    final counting = !_inFront && !_bubble && _countSecs != null;
    if (counting && !_ringBeeped) {
      _ringBeeped = true;
      if (_voice && _speedSound != 'mute') {
        _player
            .stop()
            .then((_) => _player.play(AssetSource('sounds/step1.wav'),
                volume: _volume))
            .catchError((_) {});
      }
    } else if (_countSecs == null) {
      _ringBeeped = false;
    }
  }

  void _syncRingPopup() {
    _ringBeep();
    final want = !_inFront &&
        !_bubble &&
        (_testSecs != null ||
            (_running &&
                _speedWarn &&
                _rule.mode != RadarMode.disabled &&
                _watch.seconds != null));
    // A janela fica aberta (minúscula) enquanto o app está minimizado;
    // aqui só tenta abrir se ainda não abriu (Android antigo deixa).
    if (want && !_overlayShown) _showRing();
  }

  Future<void> _showRing() async {
    if (_overlayShown || _opening) {
      _plog('abrir círculo: ignorado (${_overlayShown ? 'já aberta' : 'abrindo'})');
      return;
    }
    _opening = true;
    _plog('abrir círculo: pedindo');
    try {
      if (!await FlutterOverlayWindow.isPermissionGranted()) {
        _plog('abrir círculo: SEM PERMISSÃO');
        _bubbleNoPermission = true;
        _logError('pop-up da contagem', 'sem permissão Sobrepor a outros apps',
            StackTrace.current);
        return;
      }
      // 1.29.17: janela já do tamanho do círculo, transparente e que deixa
      // os toques passarem (clickThrough) — sem mudar de tamanho (na 1.29.16
      // a janela minúscula não crescia e o círculo não aparecia).
      await FlutterOverlayWindow.showOverlay(
        height: overlayUnits(kRingD),
        width: overlayUnits(kRingD),
        alignment: OverlayAlignment.topCenter,
        flag: OverlayFlag.clickThrough,
        enableDrag: false,
        positionGravity: PositionGravity.none,
        overlayTitle: 'SpeedGuard',
        overlayContent: 'Contagem dos 30 s',
      );
      _overlayShown = true;
      _ringPopup = true;
      _plog('abrir círculo: Android aceitou');
      Future.delayed(const Duration(milliseconds: 1500), () async {
        try {
          _plog('janela ativa: ${await FlutterOverlayWindow.isActive()}');
        } catch (e) {
          _plog('janela ativa: erro $e');
        }
      });
      if (_inFront) {
        _plog('abrir círculo: app voltou, fechando');
        await _closeBubble();
        return;
      }
      _sendBubble();
    } catch (e, st) {
      _plog('abrir círculo: ERRO $e');
      _logError('pop-up da contagem', e, st);
    } finally {
      _opening = false;
    }
  }

  Future<void> _closeBubble() async {
    if (!_overlayShown) return;
    if (_ringPopup) _plog('fechar círculo');
    _overlayShown = false;
    _ringPopup = false;
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
      'over': a.overLimit || _watch.seconds != null,
      // Segundos acima do limite (contagem dos 30 s e pop-up na bolha).
      'overSecs': _countSecs,
      'road': _running && _speedWarn ? _shownLimit : null,
      'park': _running && _showParks && _parksAhead.isNotEmpty
          ? _km(_parksAhead.first.distance)
          : null,
      'ask': _ask != null,
      'scale': _bubbleScale,
      'land': _bubbleLand,
      'palette': SG.palette.value.name,
      'ringOnly': _ringPopup,
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
      // Provedor "fused" do Android (na 1.22.0 forçar o chip de GPS
      // deixou as leituras lentas e travadas em alguns celulares).
      distanceFilter: 5,
      intervalDuration: const Duration(seconds: 1),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'SpeedGuard ativo',
        notificationText: 'Monitorando radares no caminho',
        enableWakeLock: true,
      ),
    );
    _sub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_onRawPosition, onError: (e) => _snack('Erro no GPS: $e'));
    _gps.reset();
    _predictTimer?.cancel();
    // GPS ficou alguns segundos sem leitura? Os avisos de radar seguem
    // o veículo pela última velocidade e direção (a tela não muda).
    _predictTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final p = _gps.predict(DateTime.now());
      if (p != null) _runAlerts(p);
    });
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
    final file = n >= AlertEngine.overBeep ? 'beep_fast' : 'step$n';
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/$file.wav'), volume: _volume);
    } catch (_) {}
  }

  Future<void> _stop() async {
    await _sub?.cancel();
    _sub = null;
    _predictTimer?.cancel();
    _predictTimer = null;
    _gps.reset();
    _section.reset();
    // Parou o monitoramento: o painel flutuante sai da tela.
    await _closeBubble();
    await WakelockPlus.disable();
    setState(() {
      _running = false;
      _alert = const AlertState();
      _status = 'Monitoramento parado';
    });
  }

  void _onRawPosition(Position raw) {
    final pos = _gps.accept(raw);
    if (pos != null) _onPosition(pos);
  }

  /// Último erro de cálculo (Configurações → Diagnóstico). Um erro numa
  /// etapa não pode mais congelar a tela (1.28.4).
  String? _lastError;
  Future<void> _logError(String where, Object e, StackTrace st) async {
    final lines = st.toString().split('\n').take(4).join('\n');
    _lastError = '${DateTime.now().toIso8601String().substring(0, 19)} '
        '$where: $e\n$lines';
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('last_error', _lastError!);
    } catch (_) {}
  }

  void _safe(String where, void Function() f) {
    try {
      f();
    } catch (e, st) {
      _logError(where, e, st);
    }
  }

  /// Leva o mapa até [pos]. Com "mapa gira com o veículo", vira o mapa
  /// para a direção em que você anda (só andando: parado mantém o giro).
  void _camTo(Position pos, double zoom) {
    final c = LatLng(pos.latitude, pos.longitude);
    if (!_headingUp) {
      if (_mapRot != 0 || _map.camera.rotation != 0) {
        _mapRot = 0;
        _map.moveAndRotate(c, zoom, 0);
      } else {
        _map.move(c, zoom);
      }
      return;
    }
    if (pos.speed > 2.5 && pos.heading >= 0) {
      var d = (-pos.heading) - _mapRot;
      d = (d + 540) % 360 - 180; // menor caminho (ex.: 359° → 1°)
      // Ignora tremidas pequenas do GPS; suaviza as curvas.
      if (d.abs() > 3) _mapRot += d * (d.abs() > 45 ? 1 : 0.6);
    }
    _map.moveAndRotate(c, zoom, _mapRot);
  }

  Future<void> _onPosition(Position pos) async {
    _pos = pos;
    // Velocidade e posição na tela primeiro, aconteça o que acontecer depois.
    if (mounted) setState(() {});
    _safe('mapa', () {
      if (_follow) _camTo(pos, _map.camera.zoom);
    });
    _safe('país', () => _checkCountry(pos));
    _safe('radares', () {
      if (!_loading && _service.needsRefresh(pos.latitude, pos.longitude)) {
        _refresh(pos);
      }
    });
    _safe('comunidade', () {
      if (_community.needsRefresh(pos.latitude, pos.longitude)) {
        _community.refresh(pos.latitude, pos.longitude).then((_) {
          _removed.shared = _community.removed;
          if (mounted) setState(() {});
        });
      }
    });
    _safe('avisos', () => _runAlerts(pos));
    _safe('velocidade', () => _checkSpeedLimit(pos));
    _safe('média', () {
      final say = _section.update(
          pos, [for (final r in _allRadars) if (r.type == 'media') r]);
      if (say != null && _voice && _speedSound != 'mute') {
        if (_sound == 'beep') {
          _beep(3);
        } else {
          _tts.speak(say);
        }
      }
    });
    _safe('parks', () => _checkParks(pos));
    _safe('pergunta', () => _checkAsk(pos));
  }

  void _checkParks(Position pos) {
    if (!_showParks) {
      _parksAhead = const [];
      return;
    }
    _parks.update(pos.latitude, pos.longitude);
    final prog = _routeProgress(pos);
    // Rota longa: busca o próximo pedaço quando faltam < 40 km do buscado.
    if (prog != null && _parks.needMore(_route, prog)) {
      _parks.loadRoute(_route,
          country: _country, from: _parks.loadedUntil);
    }
    _parksAhead = prog != null
        ? _parks.alongRoute(prog)
        : _parks.ahead(pos.latitude, pos.longitude,
            pos.speed > 2.5 ? pos.heading : -1,
            country: _country);
    final say = _parks.announce(_parksAhead);
    if (say != null && _voice) _tts.speak(say);
  }

  /// Quanto já andou na rota (m), ou null sem rota / fora dela.
  /// Chegou ao destino: encerra a rota.
  double? _routeProgress(Position pos) {
    if (!_route.active || !_parks.hasRoute) return null;
    final prog = _route.progress(pos.latitude, pos.longitude);
    if (prog != null && _route.total - prog < 300) {
      _route.clear();
      _parks.clearRoute();
      return null;
    }
    return prog;
  }

  /// Calcula a rota até o destino digitado e busca os parks nela.
  Future<void> _planRoute(String dest) async {
    _parks.onRouteUpdate = () {
      if (mounted) setState(() {});
    };
    final pos = _pos ?? await _currentPos();
    if (pos == null) return;
    _route.clear();
    _parks.clearRoute();
    final err = await _route.plan(pos.latitude, pos.longitude, dest);
    if (err != null) {
      _snack('$err Os parks seguem pelo seu sentido.');
      return;
    }
    if (mounted) setState(() {});
    var n = await _parks.loadRoute(_route, country: _country);
    // 1.29.12: busca os pedaços seguintes até ter os 30 parks (ou o fim da
    // rota), sem esperar o GPS andar.
    for (var i = 0; i < 20 && n != null && mounted; i++) {
      final prog = _route.progress(pos.latitude, pos.longitude) ?? 0;
      if (!_parks.needMore(_route, prog)) break;
      final more = await _parks.loadRoute(_route,
          country: _country, from: _parks.loadedUntil);
      if (more == null) break; // pedaço falhou: o resto vem andando
      n = more;
      if (mounted) setState(() {});
    }
    if (!mounted) return;
    setState(() {});
    _snack(n == null
        ? 'Não consegui buscar os parks da rota. Toque no P para tentar de novo.'
        : 'Parks da rota até ${_route.destName} prontos. Toque no P para ver.');
  }

  static String _km(double m) => m < 1000
      ? '${(m / 50).round() * 50} m'
      : m < 10000
          ? '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} km'
          : '${(m / 1000).round()} km';

  /// Compartilha o park (WhatsApp, SMS, e-mail…) com o link do Google Maps.
  Future<void> _sharePark(Park p) async {
    final title = p.name.isNotEmpty ? '${p.name} (${p.kindLabel})' : p.kindLabel;
    final f = p.features;
    final text = [
      'Park: $title',
      if (f.isNotEmpty) f.join(', '),
      'https://www.google.com/maps/search/?api=1&query=${p.lat},${p.lon}',
    ].join('\n');
    try {
      await AndroidIntent(
        action: 'android.intent.action.SEND',
        type: 'text/plain',
        arguments: {'android.intent.extra.TEXT': text},
      ).launchChooser('Compartilhar park');
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      _snack('Link do park copiado.');
    }
  }

  /// Abre o Google Maps (ou o Waze) com rota até o park.
  Future<void> _navigateTo(Park p) async {
    final ll = '${p.lat},${p.lon}';
    try {
      await AndroidIntent(
        action: 'action_view',
        data: 'google.navigation:q=$ll',
        package: 'com.google.android.apps.maps',
        flags: const [Flag.FLAG_ACTIVITY_NEW_TASK],
      ).launch();
    } catch (_) {
      try {
        await AndroidIntent(
          action: 'action_view',
          data: 'https://waze.com/ul?ll=$ll&navigate=yes',
          package: 'com.waze',
          flags: const [Flag.FLAG_ACTIVITY_NEW_TASK],
        ).launch();
      } catch (_) {
        _snack('Não foi possível abrir o Google Maps nem o Waze.');
      }
    }
  }

  /// Botão "P" ao lado de Navegar: abre a lista dos 3 parks à frente.
  Widget _parkButton() => Material(
        color: const Color(0xFF1565C0),
        shape: CircleBorder(side: BorderSide(color: SG.outline, width: 1.5)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _parksSheet,
          child: const SizedBox(
            width: 46,
            height: 46,
            child: Center(
              child: Text('P',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900)),
            ),
          ),
        ),
      );

  /// Janela "Parks à frente": os 3 próximos no seu sentido; toque abre a
  /// rota no Google Maps.
  Future<void> _parksSheet() async {
    final pos = _pos ?? await _currentPos();
    if (!mounted) return;
    if (pos == null) {
      _snack('Aguardando o sinal do GPS…');
      return;
    }
    // Rota calculada mas a busca dos parks falhou: tenta de novo.
    if (_route.active && !_parks.hasRoute && !_parks.routeLoading) {
      _parks.loadRoute(_route, country: _country);
    }
    final load = _parks.update(pos.latitude, pos.longitude);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => FutureBuilder<void>(
          future: load,
          builder: (ctx, snap) {
            final waiting = snap.connectionState != ConnectionState.done;
            final routing = _route.active;
            String title, hint = '';
            List<ParkAhead> list;
            if (routing && _parks.hasRoute) {
              final prog =
                  _route.progress(pos.latitude, pos.longitude) ?? 0;
              list = _parks.alongRoute(prog, max: ParkService.routeList);
              title = 'Próximos parks até ${_route.destName}';
              hint = _parks.routeLoading
                  ? 'Buscando mais parks da rota…'
                  : 'Distância pela estrada';
            } else {
              list = _parks.ahead(pos.latitude, pos.longitude,
                  pos.speed > 2.5 ? pos.heading : -1,
                  country: _country);
              final noDir = !_parks.hasHeading;
              if (noDir) list = _parks.nearest(pos.latitude, pos.longitude);
              title = noDir ? 'Parks mais perto' : 'Parks à frente';
              hint = routing && _parks.routeLoading
                  ? 'Buscando os parks da rota… abra de novo em instantes.'
                  : noDir
                      ? 'Comece a andar para ver só os do seu sentido.'
                      : 'Digite o destino em Navegar para ver todos os parks da rota.';
            }
            // Ainda buscando: atualiza a janela sozinha a cada 2 s.
            if (waiting || (routing && _parks.routeLoading)) {
              Future.delayed(const Duration(seconds: 2), () {
                if (ctx.mounted) setSheet(() {});
              });
            }
            Widget tile(ParkAhead a) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () {
                    Navigator.pop(ctx);
                    _navigateTo(a.park);
                  },
                  leading: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: const Color(0xFF1565C0),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Text('P',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900)),
                  ),
                  // Distância em destaque antes do nome.
                  title: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text: '${_km(a.distance)}  ',
                            style: const TextStyle(
                                color: Color(0xFF64B5F6),
                                fontSize: 18,
                                fontWeight: FontWeight.w900)),
                        TextSpan(
                            text: a.park.name.isNotEmpty
                                ? a.park.name
                                : a.park.kindLabel,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                      ]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  subtitle: Text([
                    if (a.park.name.isNotEmpty) a.park.kindLabel,
                    if (a.side != null) 'à ${a.side}',
                    ...a.park.features,
                  ].join(' · ')),
                  // Compartilhar (separado) e rota.
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: 'Compartilhar',
                      icon: const Icon(Icons.share),
                      onPressed: () => _sharePark(a.park),
                    ),
                    const Icon(Icons.directions, color: Color(0xFF1A73E8)),
                  ]),
                );
            return Padding(
              // Espaço para a barra de navegação do Android não cobrir
              // o botão "Encerrar rota".
              padding: EdgeInsets.fromLTRB(
                  16, 8, 16, 20 + MediaQuery.viewPaddingOf(ctx).bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  if (hint.isNotEmpty)
                    Text(hint,
                        style: TextStyle(color: SG.textSoft, fontSize: 12)),
                  const SizedBox(height: 8),
                  if (waiting && list.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (list.isEmpty && routing && _parks.routeLoading)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                          routing && _parks.hasRoute
                              ? 'Nenhum park à frente nesta rota.'
                              : 'Nenhum park encontrado à frente (até 60 km).',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: SG.textSoft)),
                    )
                  else
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [for (final a in list) tile(a)],
                      ),
                    ),
                  if (routing)
                    TextButton.icon(
                      onPressed: () {
                        _route.clear();
                        _parks.clearRoute();
                        setState(() {});
                        Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.close),
                      label: const Text('Encerrar rota'),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Posição atual quando o monitoramento está parado.
  Future<Position?> _currentPos() async {
    try {
      if (!await _ensurePermission()) return null;
      return await Geolocator.getCurrentPosition()
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      return null;
    }
  }

  /// Card "Parks à frente", em cima dos botões Opções/Navegar.
  Widget _parkCard() {
    final list = _parkOpen ? _parksAhead : _parksAhead.take(1).toList();
    Widget row(ParkAhead a) {
      final p = a.park;
      final title = p.name.isNotEmpty ? p.name : p.kindLabel;
      final info = [
        if (p.name.isNotEmpty) p.kindLabel,
        if (a.side != null) 'à ${a.side}',
        ...p.features,
      ].join(' · ');
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: const Color(0xFF1565C0),
                borderRadius: BorderRadius.circular(6)),
            child: const Text('P',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 64,
            child: Text(_km(a.distance),
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (info.isNotEmpty)
                    Text(info,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: SG.textSoft)),
                ]),
          ),
          IconButton(
            tooltip: 'Compartilhar',
            icon: const Icon(Icons.share, size: 20),
            onPressed: () => _sharePark(p),
          ),
          IconButton(
            tooltip: 'Ir até o park',
            icon: const Icon(Icons.directions),
            onPressed: () => _navigateTo(p),
          ),
        ]),
      );
    }

    return GestureDetector(
      onTap: () => setState(() => _parkOpen = !_parkOpen),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
        decoration: BoxDecoration(
          color: SG.card.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF1565C0), width: 2),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final a in list) row(a),
          if (_parksAhead.length > 1)
            Icon(_parkOpen ? Icons.expand_more : Icons.expand_less,
                size: 18, color: SG.textSoft),
        ]),
      ),
    );
  }

  bool get _isTruck => _vehicle == VehicleIcon.truck;

  /// Limite usado para a contagem de 30 s: caminhão = a partir de quanto o
  /// limitador começa a contar (80, ou 90 a 95, escolhido nas Configurações),
  /// outros veículos = limite da via.
  int? get _watchLimit => _isTruck ? _truckMax : _roadLimit;

  /// Limite legal do caminhão mostrado na placa (1.29.2): com o seletor em
  /// 91–95 a placa continua 90; só a contagem começa mais acima.
  int get _truckBase => _truckMax >= 90 ? 90 : _truckMax;

  /// Limite mostrado na placa em cima da velocidade.
  int? get _shownLimit {
    if (!_isTruck) return _roadLimit;
    final r = _roadLimit;
    return r == null ? _truckBase : (r < _truckBase ? r : _truckBase);
  }

  void _checkSpeedLimit(Position pos) {
    _roads.update(pos.latitude, pos.longitude);
    _roadLimit = _roads.limitAt(pos.latitude, pos.longitude,
        pos.speed > 2.5 ? pos.heading : -1,
        truck: _isTruck, country: _country);
    final speed = (pos.speed.clamp(0, 400) * 3.6).round();
    if (!_speedWarn || _rule.mode == RadarMode.disabled) {
      _watch.reset();
      return;
    }
    final ev = _watch.update(speed: speed, limit: _watchLimit);
    _syncRingPopup();
    String? say = ev?.text;
    var beep = ev == null
        ? 0
        : (ev.step == 2 ? 3 : (ev.step == 3 ? AlertEngine.overBeep : 0));
    // Caminhão numa via com limite menor que o do limitador: avisa uma vez.
    final road = _roadLimit;
    if (_isTruck && road != null && road < _truckBase) {
      if (speed > road + 2 && _roadWarned != road) {
        _roadWarned = road;
        if (say == null) {
          say = 'Limite da via $road.';
          beep = 2;
        }
      } else if (speed <= road) {
        _roadWarned = null;
      }
    }
    if (ev != null || say != null) {
      // 1.28.8: o aviso de velocidade não vibra mais (só tela e som).
      if (ev?.step == 3) setState(() {}); // card "VELOCIDADE EXCEDIDA"
      // Mudo: sem som, mas o aviso visual (velocímetro vermelho, contagem
      // dos 30 s e "VELOCIDADE EXCEDIDA") continua igual.
      if (_voice && say != null && _speedSound != 'mute') {
        if (_speedSound == 'beep') {
          if (beep > 0) _beep(beep);
        } else {
          _tts.speak(say);
        }
      }
    }
  }

  /// Calcula o radar à frente e toca os avisos.
  void _runAlerts(Position pos) {
    final st = _engine.update(
        pos: pos, radars: _allRadars, mode: _rule.mode,
        onRoad: _sameRoad
            ? (r) {
                try {
                  final b = (Geolocator.bearingBetween(
                              pos.latitude, pos.longitude, r.lat, r.lon) +
                          360) %
                      360;
                  return _roads.radarOnMyRoad(
                      r, pos.heading, b, pos.speed * 3.6);
                } catch (e, st) {
                  _logError('via do radar', e, st);
                  return null;
                }
              }
            : null);
    if (st.speak != null || st.beeps > 0) {
      HapticFeedback.heavyImpact();
      if (_voice) {
        if (_sound == 'beep' && st.beeps > 0) {
          _beep(st.beeps);
        } else if (st.speak != null) {
          _tts.speak(!_discreet
              ? st.speak!
              : st.beeps == AlertEngine.overBeep
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
      _presenceTick();
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

  Future<void> _refresh(Position pos, {bool force = false}) async {
    setState(() => _loading = true);
    final n =
        await _service.refresh(pos.latitude, pos.longitude, force: force);
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
    // Calcula a mesma rota aqui, para listar os parks do caminho.
    if (dest.isNotEmpty) _planRoute(dest);
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
      await p.setStringList('layersKnown', [for (final l in Layer.values) l.name]);
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
                    if (v && pos != null) _camTo(pos, 16);
                  },
                ),
                SwitchListTile(
                  secondary: Icon(Icons.explore, color: SG.accent),
                  title: const Text('Mapa gira com o veículo',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text(
                      'Ligado: a seta fica sempre para cima e o mapa vira '
                      'conforme você anda. Desligado: norte sempre em cima.'),
                  value: _headingUp,
                  onChanged: (v) async {
                    setSheet(() {});
                    setState(() => _headingUp = v);
                    (await SharedPreferences.getInstance())
                        .setBool('map_heading_up', v);
                    final pos = _pos;
                    if (pos != null) {
                      _camTo(pos, _map.camera.zoom);
                    } else if (!v) {
                      _mapRot = 0;
                      _map.rotate(0);
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

  /// Reporta fila, acidente, obra, perigo ou polícia aqui (some após 6 h).
  /// Reporta um aviso de trânsito (pelo app ou pelo painel flutuante).
  /// Vindo do painel, o app está em segundo plano: avisa por voz.
  Future<void> _submitEvent(Layer l, {bool fromBubble = false}) async {
    void tell(String text) {
      if (fromBubble) {
        _say(text);
      } else {
        _snack(text);
      }
    }

    final pos = _pos;
    if (pos == null) {
      tell(fromBubble
          ? 'Sem sinal de GPS. Aviso não salvo.'
          : 'Aguarde o sinal do GPS para reportar.');
      return;
    }
    if (!communityEnabled) {
      tell('Avisos precisam do Firebase configurado.');
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
      tell(fromBubble
          ? '${l.label} já reportado. Confirmado, obrigado!'
          : '${l.label}: já reportado aqui. Confirmado por mais 6 h.');
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
    tell(ok
        ? (fromBubble
            ? '${l.label} reportado. Obrigado!'
            : '${l.label} reportado para todos. Some em 6 h.')
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
              EventBar(onSelected: (l) => Navigator.pop(ctx, l)),
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

  /// "Este radar não existe mais" (1.29.7): esconde para você e avisa os
  /// outros (radar móvel compartilhado é apagado direto, como no "Não").
  Future<void> _radarGone(Radar r) async {
    await _removed.hide(r);
    if (mounted) setState(() {});
    if (r.type == 'movel' && r.id.startsWith('cm_')) {
      await _community.confirm(r, false);
    } else {
      await _community.reportRemoved(r);
    }
    _removed.shared = _community.removed;
    _snack('Radar escondido. Obrigado pelo aviso!');
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
            if (r.type != 'usuario' && !r.isEvent) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.not_interested),
                label: const Text('Este radar não existe mais'),
                onPressed: () async {
                  Navigator.pop(context);
                  await _radarGone(r);
                },
              ),
              const SizedBox(height: 4),
              const Text(
                  'Some na hora para você. Para os outros motoristas, some '
                  'quando 2 pessoas avisarem.',
                  style: TextStyle(fontSize: 12, color: Colors.white60)),
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
                title: const Text('Parks à frente'),
                subtitle: const Text(
                    'Áreas de descanso, de serviço e estacionamentos de caminhão '
                    'no seu sentido, com aviso a 2 km'),
                value: _showParks,
                onChanged: (v) async {
                  final p = await SharedPreferences.getInstance();
                  await p.setBool('show_parks', v);
                  setSheet(() => _showParks = v);
                  setState(() {});
                },
              ),
              if (_showParks)
                SwitchListTile(
                  title: const Text('Só parks de caminhão'),
                  subtitle: const Text(
                      'Estacionamentos e paradas de caminhão. Desligado: também '
                      'as áreas de descanso e de serviço sem vaga de caminhão marcada'),
                  value: _parks.truckOnly,
                  onChanged: (v) async {
                    final p = await SharedPreferences.getInstance();
                    await p.setBool('parks_truck_only', v);
                    setSheet(() => _parks.truckOnly = v);
                    setState(() {});
                  },
                ),
              SwitchListTile(
                title: const Text('Só radares da minha via'),
                subtitle: const Text(
                    'Avisa só os radares da rodovia/rua onde você está. Radares '
                    'de ruas ao lado ou que cruzam são ignorados'),
                value: _sameRoad,
                onChanged: (v) async {
                  final p = await SharedPreferences.getInstance();
                  await p.setBool('same_road', v);
                  setSheet(() => _sameRoad = v);
                  setState(() {});
                },
              ),
              if (_removed.mineCount > 0)
                // 1.29.9: mesmo formato das outras opções (texto em largura
                // total, botão embaixo); antes o botão ao lado espremia o texto.
                ListTile(
                  title: const Text('Radares escondidos'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_removed.mineCount == 1
                          ? '1 radar marcado por você como "não existe mais"'
                          : '${_removed.mineCount} radares marcados por você '
                              'como "não existe mais"'),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        label: const Text('Mostrar de novo'),
                        onPressed: () async {
                          await _removed.clearMine();
                          setSheet(() {});
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
              SwitchListTile(
                title: const Text('Aviso de velocidade excedida'),
                subtitle: Text(_isTruck
                    ? 'Caminhão: passou de $_truckMax, o velocímetro fica vermelho '
                        'com a contagem; aos 20 s "Atenção" e aos 30 s "Velocidade '
                        'excedida. Tempo excedido". Mostra o limite da via'
                    : 'Passou do limite da via: velocímetro vermelho com a contagem; '
                        'aos 20 s "Atenção" e aos 30 s "Velocidade excedida"'),
                value: _speedWarn,
                onChanged: (v) async {
                  final p = await SharedPreferences.getInstance();
                  await p.setBool('speed_warn', v);
                  _watch.reset();
                  setSheet(() => _speedWarn = v);
                  setState(() {});
                },
              ),
              if (_speedWarn)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    const Text('Som do aviso de velocidade (Mudo: só o aviso na tela)'),
                    const SizedBox(height: 6),
                    SegmentedButton<String>(
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
                        ButtonSegment(
                            value: 'mute',
                            icon: Icon(Icons.volume_off),
                            label: Text('Mudo')),
                      ],
                      selected: {_speedSound},
                      onSelectionChanged: (v) async {
                        final p = await SharedPreferences.getInstance();
                        await p.setString('speed_sound', v.first);
                        setSheet(() => _speedSound = v.first);
                        // Amostra de como vai soar.
                        if (v.first == 'beep') {
                          _beep(3);
                        } else if (v.first == 'voice') {
                          _tts.speak('Atenção.');
                        }
                      },
                    ),
                  ]),
                ),
              if (_speedWarn && _isTruck)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(children: [
                    const Expanded(
                        child: Text('Limitador do caminhão\n'
                            'Começa a contar os 30 s acima de',
                            style: TextStyle(height: 1.3))),
                    DropdownButton<int>(
                      value: _truckMax,
                      menuMaxHeight: 360,
                      items: kTruckLimits
                          .map((v) => DropdownMenuItem(
                              value: v, child: Text('$v km/h')))
                          .toList(),
                      onChanged: (v) async {
                        if (v == null) return;
                        final p = await SharedPreferences.getInstance();
                        await p.setInt('truck_max', v);
                        _watch.reset();
                        setSheet(() => _truckMax = v);
                        setState(() {});
                      },
                    ),
                  ]),
                ),
              SwitchListTile(
                title: const Text('Alertas sonoros'),
                subtitle: const Text('Avisos a 1000, 800, 500, 400, 300 e 100 m do radar'),
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
                        _tts.speak('Radar fixo a 1000 metros. Limite 80.');
                      }
                    },
                  ),
                ),
              // Volume dos avisos (voz e bipes de radar e de velocidade).
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Row(children: [
                  const Icon(Icons.volume_down),
                  Expanded(
                    child: Slider(
                      value: _volume,
                      min: 0.1,
                      max: 1.0,
                      divisions: 9,
                      label: '${(_volume * 100).round()}%',
                      onChanged: (v) => setSheet(() => _volume = v),
                      onChangeEnd: (v) async {
                        final p = await SharedPreferences.getInstance();
                        await p.setDouble('volume', v);
                        await _tts.setVolume(v);
                        // Amostra no volume novo.
                        if (_sound == 'beep') {
                          _beep(3);
                        } else {
                          _tts.speak('Volume ${(v * 100).round()} por cento.');
                        }
                      },
                    ),
                  ),
                  const Icon(Icons.volume_up),
                  SizedBox(
                      width: 44,
                      child: Text('${(_volume * 100).round()}%',
                          textAlign: TextAlign.right)),
                ]),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                    'Volume dos avisos (voz e bipes). 100% = volume do celular',
                    style: TextStyle(fontSize: 12)),
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
              if (!_bubble)
                ListTile(
                  leading: Icon(Icons.timer_outlined, color: SG.red),
                  title: const Text('Testar pop-up da contagem'),
                  subtitle: const Text(
                      'Conta 35 s de mentira: toque, minimize o app e abra '
                      'outro (ex.: YouTube) — o círculo vermelho tem de '
                      'aparecer por cima'),
                  onTap: () async {
                    if (!await FlutterOverlayWindow.isPermissionGranted()) {
                      final ok = await FlutterOverlayWindow.requestPermission();
                      if (ok != true) return;
                    }
                    if (!mounted) return;
                    Navigator.pop(context);
                    _testRing();
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
                leading: const Icon(Icons.play_circle_outline),
                title: const Text('Tutorial'),
                subtitle: const Text('Vídeo de como configurar e usar o app'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const TutorialPage()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Atualizar radares agora'),
                onTap: () {
                  Navigator.pop(ctx);
                  if (_pos != null) {
                    _areaBounds = null;
                    _refresh(_pos!, force: true);
                    _community.refresh(_pos!.latitude, _pos!.longitude);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.bug_report_outlined),
                title: const Text('Diagnóstico (último erro)'),
                onTap: () async {
                  final p = await SharedPreferences.getInstance();
                  final err = _lastError ?? p.getString('last_error');
                  await p.reload();
                  final log = [
                    ...(_popLog.isNotEmpty
                        ? _popLog
                        : (p.getStringList('popup_log') ?? const <String>[])),
                    // O que a própria janela registrou (1.29.23).
                    ...(p.getStringList('overlay_log') ?? const <String>[]),
                  ]..sort();
                  if (!ctx.mounted) return;
                  showDialog(
                    context: ctx,
                    builder: (d) => AlertDialog(
                      title: const Text('Último erro'),
                      content: SingleChildScrollView(
                          child: SelectableText(
                              '${err ?? 'Nenhum erro registrado.'}\n\n'
                              'Pop-up da contagem:\n'
                              '${log.isEmpty ? '(vazio)' : log.reversed.take(25).join('\n')}',
                              style: const TextStyle(fontSize: 12))),
                      actions: [
                        if (err != null)
                          TextButton(
                              onPressed: () async {
                                await p.remove('last_error');
                                _lastError = null;
                                if (d.mounted) Navigator.pop(d);
                              },
                              child: const Text('Apagar')),
                        TextButton(
                            onPressed: () => Navigator.pop(d),
                            child: const Text('Fechar')),
                      ],
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.system_update),
                title: const Text('Procurar atualização do app'),
                // 1.28.9: mostra a versão instalada (muda a cada atualização).
                subtitle: FutureBuilder<String>(
                  future: UpdateService.installed(),
                  builder: (_, s) =>
                      Text('Versão instalada: ${s.data ?? '…'}'),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  UpdateService.manualCheck(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.public),
                title: Text('País: ${_rule.name}'),
                subtitle: Text(_modeLabel(_rule.mode)),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                // Versão real do app instalado (antes fixa em "1.19.0").
                title: FutureBuilder<String>(
                  future: UpdateService.installed(),
                  builder: (_, s) => Text('SpeedGuard ${s.data ?? ''}'.trim()),
                ),
                subtitle: const Text('Dados de radares: © colaboradores do '
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
      // Fila, acidente, obra, perigo ou polícia: bolinha colorida com o símbolo.
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
        : r.type == 'media'
            ? const Color(0xFF00BCD4)
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
    final overSecs = _running ? _watch.seconds : null;
    final roadSign = _running && _speedWarn ? _shownLimit : null;
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
                    for (final r in _visibleRadars())
                      Marker(
                        point: LatLng(r.lat, r.lon),
                        width: 34,
                        height: 34,
                        rotate: true, // placa fica em pé com o mapa girado
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
                  // Conectados no mundo e no país, no alto da tela.
                  if (_presence.world != null) _onlineCards(),
                  Row(
                    children: [
                      Column(mainAxisSize: MainAxisSize.min, children: [
                        // Placa com o limite da via (caminhão: no máximo o
                        // do limitador) em cima da velocidade.
                        if (roadSign != null) ...[
                          // 1.29.21: maior; caminhão com a placa do
                          // caminhão embaixo.
                          SpeedSign(
                              label: '$roadSign', size: 56, truck: _isTruck),
                          const SizedBox(height: 4),
                        ],
                        _SpeedBox(
                            speed: speed,
                            over: a.overLimit || overSecs != null),
                        // Trecho de velocidade média: mostra a média.
                        if (_running && _section.active)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                                color: (_section.average ?? 0) >
                                        (_section.limit ?? 9999) + 2
                                    ? SG.red
                                    : const Color(0xFF00BCD4),
                                borderRadius: BorderRadius.circular(10)),
                            child: Text(
                                'Média ${_section.average ?? '--'}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold)),
                          ),
                        // Contagem dos 30 s acima do limite.
                        if (overSecs != null)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                                color: SG.red,
                                borderRadius: BorderRadius.circular(10)),
                            child: Text(
                                overSecs >= 30
                                    ? 'VELOCIDADE\nEXCEDIDA'
                                    : '${30 - overSecs} s',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: overSecs >= 30 ? 11 : 14,
                                    height: 1.1,
                                    fontWeight: FontWeight.bold)),
                          ),
                      ]),
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

          // Parks à frente, logo acima dos botões.
          if (_running && _showParks && _parksAhead.isNotEmpty)
            Positioned(left: 12, right: 12, bottom: 72, child: _parkCard()),

          // Botões "Opções" (camadas do mapa) e "Navegar" (Google/Waze).
          Positioned(
            left: 12,
            bottom: 12,
            child: Row(children: [
              _pill(Icons.tune, 'Opções', _mapOptions),
              const SizedBox(width: 8),
              _pill(Icons.navigation, 'Navegar', _navigate),
              const SizedBox(width: 8),
              _parkButton(),
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
                if (pos != null) _camTo(pos, 16);
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

  /// Dois cards pequenos lado a lado, no alto da tela (acima da
  /// velocidade): conectados no mundo e no país onde você está.
  Widget _onlineCards() {
    final p = _presence;
    final code = p.countryCode;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _OnlineChip(
            icon: '🌍',
            count: p.world!,
            label: 'no mundo',
            tooltip: 'Pessoas com o SpeedGuard conectado no mundo',
          ),
          if (code != null && p.country != null) ...[
            const SizedBox(width: 8),
            _OnlineChip(
              icon: PresenceService.flag(code),
              count: p.country!,
              label: 'no país',
              tooltip: 'Pessoas com o SpeedGuard conectado em '
                  '${ruleFor(code).name}',
            ),
          ],
        ],
      ),
    );
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

/// Card pequeno "🌍 128 no mundo" / "🇫🇷 12 no país".
class _OnlineChip extends StatelessWidget {
  final String icon;
  final int count;
  final String label;
  final String tooltip;
  const _OnlineChip({
    required this.icon,
    required this.count,
    required this.label,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
        decoration: BoxDecoration(
          color: SG.card.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: SG.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 5),
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                  color: Color(0xFF3DDC84), shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(PresenceService.format(count),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: SG.text)),
            const SizedBox(width: 3),
            Text(label, style: TextStyle(fontSize: 11, color: SG.textSoft)),
          ],
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
