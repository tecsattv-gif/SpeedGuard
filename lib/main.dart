import 'update_service.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
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
import 'live_bg.dart';
import 'live_service.dart';
import 'theme.dart';
import 'help_page.dart';
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
import 'toll_service.dart';
import 'track_nav.dart';
import 'track_recorder.dart';
import 'i18n.dart';

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
  await loadLang();
  runApp(const SpeedGuardApp());
}

/// Valores do seletor "Limitador do caminhão" (1.29.19): de 80 a 95 de 1
/// em 1 e depois de 10 em 10 até 130.
const List<int> kTruckLimits = [
  80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, //
  100, 110, 120, 130,
];

/// Ponto de entrada da bolha flutuante (roda separado do app).
/// ATENÇÃO: o @pragma tem de ficar colado no overlayMain — na 1.29.19 uma
/// constante entrou no meio, o compilador removeu o overlayMain e a bolha
/// e o pop-up pararam de funcionar (corrigido na 1.29.25).
@pragma('vm:entry-point')
Future<void> overlayMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 1.29.24: registro do Diagnóstico — a janela flutuante foi criada.
  try {
    final p = await SharedPreferences.getInstance();
    final l = p.getStringList('overlay_log') ?? <String>[];
    l.add('${DateTime.now().toIso8601String().substring(11, 19)} '
        'janela: motor criado');
    await p.setStringList('overlay_log', l.length > 15 ? l.sublist(l.length - 15) : l);
  } catch (_) {}
  // Mesmas cores do app (a paleta também chega pelos dados do painel).
  try {
    final p = await SharedPreferences.getInstance();
    SG.palette.value = AppPalette.byName(p.getString('palette'));
  } catch (_) {}
  await loadLang();
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
      listenable: Listenable.merge([SG.mode, SG.palette, langNotifier]),
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
    _snack(tr('Teste pronto: agora minimize o SpeedGuard e abra outro app (ex.: YouTube).'));
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
  String _status = tr('Toque em INICIAR para monitorar radares');

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
    // Mensagem de voz terminou de tocar (1.33.0).
    _voicePlayer.onPlayerComplete.listen((_) {
      _playing = null;
      _chatRefresh?.call(() {});
      if (mounted) setState(() {});
    });
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
    await _rec.load();
    await _live.load();
    _live.onPhoto = () {
      if (mounted) setState(() {});
    };
    _liveTimer = Timer.periodic(LiveService.every, (_) => _liveTick());
    // 1.34.0: tocar na notificação de mensagem abre a conversa de quem mandou.
    LiveBorder.listenTaps((from, nick) {
      if (mounted) _openChatFrom(from, nick);
    });
    Future.delayed(const Duration(seconds: 6), () => _liveTick(photo: true));
    LiveBorder.schedule(_isTruck && _live.hasGroup);
    // 1.29.39: app fechado no meio da navegação: oferece continuar.
    Future.delayed(const Duration(seconds: 4), () async {
      final l = await _lastNav();
      if (l == null || !mounted || _nav != null) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 12),
        content: Text(tr('Continuar a rota "{0}"?', [l.$1.name])),
        action: SnackBarAction(label: tr('CONTINUAR'), onPressed: _continueNav),
      ));
    });
    _loadUserParks();
    Timer.periodic(const Duration(minutes: 30), (_) => _loadUserParks());
    _voice = p.getBool('voice') ?? true;
    _speedWarn = p.getBool('speed_warn') ?? true;
    _showParks = p.getBool('show_parks') ?? true;
    _tolls.enabled = p.getBool('toll_warn') ?? true;
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
    await _tts.setLanguage(ttsLang);
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
    _liveTimer?.cancel();
    _trackTimer?.cancel();
    _msgPopTimer?.cancel();
    _closeBubble();
    _overlaySub?.cancel();
    _askTimer?.cancel();
    _sub?.cancel();
    _predictTimer?.cancel();
    _tts.stop();
    _player.dispose();
    _voicePlayer.dispose();
    _voiceRec.dispose();
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
      // 1.31.0: a mesma janela mostra também o card do aviso de radar,
      // então abre sempre que o monitoramento está ligado.
      if (!_bubble && (_running || _testSecs != null)) {
        _showRing();
      }
    } else if (state == AppLifecycleState.resumed) {
      _inFront = true;
      _closeBubble();
      _presenceTick();
      if (mounted) UpdateService.autoCheck(context, resumed: true);
      if (_bubbleNoPermission) {
        _bubbleNoPermission = false;
        _snack(tr('Painel flutuante sem permissão: ative "Sobrepor a outros apps" para o SpeedGuard.'));
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
        overlayContent: tr('Bolha de radares ativa'),
      );
      _overlayShown = true;
      _keepOverlay();
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
        // 1.29.26: o bipe de "acima do limite" do próprio app.
        _beep(AlertEngine.overBeep);
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
                _rule.mode != RadarMode.disabled &&
                ((_speedWarn && _watch.seconds != null) ||
                    _alert.radar != null)));
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
      // 1.29.24: abre do mesmo jeito que a bolha (que funciona neste
      // celular): canto de cima, toque normal; a janela é levada para o
      // centro e a própria janela passa a deixar os toques passarem
      // depois que recebe a contagem. Aberta direto "sem toque" e no
      // centro, a janela não desenhava nada.
      final w = mounted ? MediaQuery.sizeOf(context).width : 400.0;
      // 1.31.0: janela do card do radar + círculo da contagem.
      await FlutterOverlayWindow.showOverlay(
        height: overlayUnits(kPopH),
        width: overlayUnits(kPopW),
        alignment: OverlayAlignment.topLeft,
        enableDrag: true,
        positionGravity: PositionGravity.none,
        startPosition: OverlayPosition((w - kPopW) / 2, 0),
        overlayTitle: 'SpeedGuard',
        overlayContent: tr('Avisos de radar por cima dos outros apps'),
      );
      _overlayShown = true;
      _ringPopup = true;
      _plog('abrir círculo: Android aceitou');
      // 1.32.0: a janela só passa a deixar os toques passarem quando recebe
      // a 1ª mensagem; parado, o GPS não manda nada (filtro de 5 m) e a
      // janela transparente travava o alto da tela dos outros apps. Manda
      // o estado a cada segundo enquanto a janela estiver aberta.
      _keepOverlay();
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

  Timer? _popKeep;

  /// 1.32.0: manda o estado para a janela flutuante a cada segundo (mesmo
  /// parado, sem GPS novo). A janela usa isso para saber que o app está
  /// vivo; sem notícia ela libera os toques e se fecha sozinha.
  void _keepOverlay() {
    _popKeep?.cancel();
    _popKeep = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_overlayShown) {
        _popKeep?.cancel();
        _popKeep = null;
        return;
      }
      _sendBubble();
    });
  }

  Future<void> _closeBubble() async {
    _popKeep?.cancel();
    _popKeep = null;
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
    // Teste dos pop-ups (1.31.0): radar fixo de mentira, limite 50, que vai
    // chegando de 1000 m até 20 m junto com a contagem.
    final test = _testSecs;
    final testDist = test == null ? null : (1000 - test * 28).clamp(20, 1000);
    FlutterOverlayWindow.shareData(jsonEncode({
      'speed': pos == null ? 0 : (pos.speed.clamp(0, 400) * 3.6).round(),
      'dist': testDist ?? (show ? a.distance : null),
      'limit': test != null ? 50 : (show ? a.radar!.maxSpeed : null),
      'sub': test != null
          ? '${tr('Radar fixo')} • ${tr('limite')} 50'
          : !show
              ? null
              : a.radar!.maxSpeed != null
                  ? '${a.radar!.typeLabel} • ${tr('limite')} ${a.radar!.maxSpeed}'
                  : a.radar!.typeLabel,
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
      'lang': appLang,
      'ringOnly': _ringPopup,
    })).catchError((_) => false);
  }

  Future<bool> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      _snack(tr('Ative o GPS do celular.'));
      await Geolocator.openLocationSettings();
      return false;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      _snack(tr('Permissão de localização negada. Libere nas configurações.'));
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
      foregroundNotificationConfig: ForegroundNotificationConfig(
        notificationTitle: tr('SpeedGuard ativo'),
        notificationText: tr('Monitorando radares no caminho'),
        enableWakeLock: true,
      ),
    );
    _sub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_onRawPosition, onError: (e) => _snack(tr('Erro no GPS: {0}', [e])));
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
      _status = tr('Procurando sinal de GPS…');
    });
  }

  /// Zoom mínimo para baixar a área vista (evita pedir um país inteiro).
  static const _areaMinZoom = 9.0;

  Future<void> _loadArea(MapCamera camera) async {
    if (!mounted || _rule.mode != RadarMode.full) return;
    if (camera.zoom < _areaMinZoom) {
      if (!_zoomHintShown) {
        _zoomHintShown = true;
        _snack(tr('Aproxime o mapa para ver os radares desta região.'));
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
    if (n == null) _snack(tr('Sem conexão para baixar os radares desta região.'));
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
      _status = tr('Monitoramento parado');
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

  /// Último sentido confiável (andando) — para "Radar da outra pista".
  double _goodHeading = -1;

  Future<void> _onPosition(Position pos) async {
    _pos = pos;
    if (_rec.recording) {
      _rec.add(pos).catchError((_) {});
    }
    if (_nav != null) _safe('navegação', () => _navTick(pos));
    if (pos.speed > 2.5 && pos.heading >= 0) _goodHeading = pos.heading;
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
    _safe('pedágio', () => _checkToll(pos));
    _safe('pergunta', () => _checkAsk(pos));
  }

  // ---------- Aviso de pedágio (1.29.48) ----------
  final _tolls = TollService();
  String? _tollBanner;
  bool _tollGantry = false; // aviso é de pórtico eletrônico (1.36.0)
  Timer? _tollTimer;

  void _checkToll(Position pos) {
    if (!_tolls.enabled) return;
    _tolls.update(pos.latitude, pos.longitude);
    // 1.35.0: só o pedágio da via onde você está (não o da saída ao lado).
    final mine = _roads.myRoad();
    final hit = _tolls.check(
        pos.latitude, pos.longitude, pos.heading, pos.speed * 3.6,
        sameRoad: _sameRoad, myType: mine?.$1, myIds: mine?.$2 ?? const {});
    if (hit == null) return;
    String say, banner;
    if (hit.passing) {
      // 1.36.0: passando por baixo do pórtico de pedágio eletrônico.
      say = tr('Passando pelo pedágio eletrônico.');
      banner = tr('Pedágio eletrônico agora');
    } else {
      final m = (hit.d / 100).round() * 100;
      final km = m >= 900;
      if (hit.gantry) {
        say = km
            ? tr('Pedágio eletrônico em 1 quilômetro.')
            : tr('Pedágio eletrônico em {0} metros.', [m]);
        banner = km
            ? tr('Pedágio eletrônico a 1 km')
            : tr('Pedágio eletrônico a {0} m', [m]);
      } else {
        say = km ? tr('Pedágio em 1 quilômetro.') : tr('Pedágio em {0} metros.', [m]);
        banner = km ? tr('Pedágio a 1 km') : tr('Pedágio a {0} m', [m]);
      }
    }
    if (_voice) _tts.speak(say);
    _tollTimer?.cancel();
    setState(() {
      _tollBanner = banner;
      _tollGantry = hit.gantry;
    });
    _tollTimer = Timer(Duration(seconds: hit.passing ? 8 : 15), () {
      if (mounted) setState(() => _tollBanner = null);
    });
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
    if (prog != null && _route.total - prog < 300 && _nav == null) {
      _route.clear();
      _parks.clearRoute();
      return null;
    }
    return prog;
  }

  /// Calcula a rota até o destino digitado e busca os parks nela.
  Future<void> _planRoute(String dest) async {
    _nav = null; // rota nova do Navegar encerra a navegação gravada
    _parks.onRouteUpdate = () {
      if (mounted) setState(() {});
    };
    final pos = _pos ?? await _currentPos();
    if (pos == null) return;
    _route.clear();
    _parks.clearRoute();
    final err = await _route.plan(pos.latitude, pos.longitude, dest);
    if (err != null) {
      _snack(tr('{0} Os parks seguem pelo seu sentido.', [err]));
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
        ? tr('Não consegui buscar os parks da rota. Toque no P para tentar de novo.')
        : tr('Parks da rota até {0} prontos. Toque no P para ver.', [_route.destName]));
  }

  static String _km(double m) => m < 1000
      ? '${(m / 50).round() * 50} m'
      : m < 10000
          ? '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} km'
          : '${(m / 1000).round()} km';

  /// Compartilha o park (WhatsApp, SMS, e-mail…) com o link do Google Maps.
  /// Toque no "P+" do mapa: nome, tipo, ir até lá e compartilhar.
  void _showUserPark(Park p) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, 20 + MediaQuery.viewPaddingOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(p.name,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text([p.kindLabel, ...p.features].join(' · '),
                style: TextStyle(color: SG.textSoft)),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.directions),
              label: Text(tr('Ir até lá')),
              onPressed: () {
                Navigator.pop(ctx);
                _navigateTo(p);
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.share),
              label: Text(tr('Compartilhar')),
              onPressed: () {
                Navigator.pop(ctx);
                _sharePark(p);
              },
            ),
            // Só quem adicionou (neste aparelho) muda de lugar ou exclui.
            if (_myParkIds.contains(p.id)) ...[
              const SizedBox(height: 16),
              Text(tr('Este park foi você que adicionou'),
                  style: TextStyle(color: SG.textSoft, fontSize: 12)),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                icon: const Icon(Icons.open_with),
                label: Text(tr('Mudar de lugar')),
                onPressed: () {
                  Navigator.pop(ctx);
                  _startMove(p);
                },
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: SG.red),
                icon: const Icon(Icons.delete_outline),
                label: Text(tr('Excluir park')),
                onPressed: () {
                  Navigator.pop(ctx);
                  _deletePark(p);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _sharePark(Park p) async {
    final title = p.name.isNotEmpty ? '${p.name} (${p.kindLabel})' : p.kindLabel;
    final f = p.features;
    final text = [
      tr('Park: {0}', [title]),
      if (f.isNotEmpty) f.join(', '),
      'https://www.google.com/maps/search/?api=1&query=${p.lat},${p.lon}',
    ].join('\n');
    try {
      await AndroidIntent(
        action: 'android.intent.action.SEND',
        type: 'text/plain',
        arguments: {'android.intent.extra.TEXT': text},
      ).launchChooser(tr('Compartilhar park'));
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      _snack(tr('Link do park copiado.'));
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
        _snack(tr('Não foi possível abrir o Google Maps nem o Waze.'));
      }
    }
  }

  // ---------- Adicionar park (1.29.30) ----------

  /// Parks dos motoristas: do aparelho (na hora) e depois do Firebase.
  Future<void> _loadUserParks() async {
    final p = await SharedPreferences.getInstance();
    List<Park> fromJson(String? raw) {
      if (raw == null) return [];
      try {
        return [
          for (final e in jsonDecode(raw) as List)
            Park.user(e['id'] as String, (e['lat'] as num).toDouble(),
                (e['lon'] as num).toDouble(), e['t'] as String,
                (e['n'] as String?) ?? '')
        ];
      } catch (_) {
        return [];
      }
    }

    final mine = fromJson(p.getString('my_parks'));
    _myParkIds
      ..clear()
      ..addAll(mine.map((e) => e.id));
    if (_parks.userParks.isEmpty) {
      _parks.userParks = [...fromJson(p.getString('user_parks')), ...mine];
    }
    final got = await _community.fetchParks();
    if (got == null) return;
    final list = [
      for (final (id, lat, lon, t, n) in got) Park.user(id, lat, lon, t, n)
    ];
    // Os seus que ainda não subiram (sem internet) continuam valendo.
    final ids = list.map((e) => e.id).toSet();
    _parks.userParks = [
      ...list,
      for (final m in mine)
        if (!ids.contains(m.id) && m.id.startsWith('local_')) m
    ];
    await p.setString(
        'user_parks',
        jsonEncode([
          for (final (id, lat, lon, t, n) in got)
            {'id': id, 'lat': lat, 'lon': lon, 't': t, 'n': n}
        ]));
    if (mounted) setState(() {});
  }

  // ---------- Rotas gravadas (1.29.35) ----------

  final _rec = TrackRecorder();

  // ---------- Localização em grupo (1.29.43) ----------
  final _live = LiveService();
  Timer? _liveTimer;
  bool _livePhotoSent = false;

  // ---------- Localizar colega (1.32.0) ----------
  String? _trackId; // colega que o mapa está seguindo
  String _trackNick = '';
  bool _trackCam = true; // false quando você arrasta o mapa
  Timer? _trackTimer;

  void _locate(LiveMember m) {
    _trackTimer?.cancel();
    setState(() {
      _trackId = m.id;
      _trackNick = m.nick;
      _trackCam = true;
      _follow = false;
      _mapView = true;
    });
    final (la, lo) = m.shown;
    _map.move(LatLng(la, lo), 15);
    _trackTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _trackStep());
  }

  void _trackStep() {
    if (!mounted || _trackId == null) return;
    final m = _live.members[_trackId];
    if (m == null) {
      final n = _trackNick.isEmpty ? tr('O colega') : _trackNick;
      _stopLocate();
      _snack(tr('{0} saiu do mapa (parou de compartilhar ou ficou sem sinal).', [n]));
      return;
    }
    if (_trackCam && !_follow) {
      final (la, lo) = m.shown;
      _safe('localizar', () => _map.move(LatLng(la, lo), _map.camera.zoom));
    }
    setState(() {});
  }

  void _stopLocate() {
    _trackTimer?.cancel();
    _trackTimer = null;
    if (mounted) setState(() => _trackId = null);
  }

  /// Card no rodapé do mapa com o colega que está sendo localizado.
  Widget _locateCard(LiveMember m) {
    final pos = _pos;
    final ago = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(m.updatedAt));
    final km = pos == null
        ? null
        : Geolocator.distanceBetween(
                pos.latitude, pos.longitude, m.lat, m.lon) /
            1000;
    return Material(
      color: SG.card,
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            SizedBox(
                width: 40,
                child: FittedBox(
                    child: _livePin(m.photo, m.nick, const Color(0xFFFF9800)))),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      tr('Localizando {0}',
                          [m.nick.isEmpty ? tr('Motorista') : m.nick]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  Text(
                      [
                        if (m.country.isNotEmpty)
                          PresenceService.flag(m.country),
                        '${m.kmh.round()} km/h',
                        if (km != null)
                          '${km < 10 ? km.toStringAsFixed(1) : km.toStringAsFixed(0)} km',
                        ago.inMinutes < 1
                            ? tr('agora')
                            : tr('há {0} min', [ago.inMinutes]),
                      ].join(' · '),
                      style: TextStyle(color: SG.textSoft, fontSize: 12)),
                ],
              ),
            ),
            IconButton(
              tooltip: tr('Fechar'),
              icon: const Icon(Icons.close),
              onPressed: _stopLocate,
            ),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6)),
                icon: Icon(_trackCam ? Icons.gps_fixed : Icons.center_focus_strong,
                    size: 18),
                label: Text(_trackCam ? tr('Seguindo') : tr('Centralizar'),
                    overflow: TextOverflow.ellipsis),
                onPressed: () {
                  setState(() {
                    _trackCam = true;
                    _follow = false;
                  });
                  final (la, lo) = m.shown;
                  _map.move(LatLng(la, lo), _map.camera.zoom);
                },
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6)),
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                label: Text(tr('Mensagem'), overflow: TextOverflow.ellipsis),
                onPressed: () => _chatWith(m.id, m.nick),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6)),
                icon: const Icon(Icons.map, size: 18),
                label: Text(tr('Google Maps'), overflow: TextOverflow.ellipsis),
                onPressed: () => _openMapAt(m.lat, m.lon),
              ),
            ),
            const SizedBox(width: 6),
          ]),
        ]),
      ),
    );
  }

  // ---------- Mensagens diretas (1.32.0) ----------
  /// Conversa de cada colega. Desde a 1.38.0 fica guardada no celular por
  /// 7 dias (não usa o Firebase: lá a mensagem continua sendo apagada
  /// assim que é entregue).
  final Map<String, List<_ChatItem>> _chat = {};
  bool _chatLoaded = false;
  static const _chatKeepDays = 7;

  /// Lê as conversas guardadas no celular e descarta as com mais de 7 dias.
  Future<void> _loadChat() async {
    if (_chatLoaded) return;
    _chatLoaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('chat_history');
      if (raw == null) return;
      final old = DateTime.now()
          .subtract(const Duration(days: _chatKeepDays))
          .millisecondsSinceEpoch;
      final saved = <String, List<_ChatItem>>{};
      (jsonDecode(raw) as Map).forEach((k, v) {
        final list = <_ChatItem>[
          for (final m in v as List)
            if ((m['at'] as int? ?? 0) >= old) _ChatItem.fromJson(m as Map)
        ];
        if (list.isNotEmpty) saved[k.toString()] = list;
      });
      // O que chegou antes de ler (raro) vai depois do histórico.
      _chat.forEach((k, v) => (saved[k] ??= []).addAll(v));
      _chat
        ..clear()
        ..addAll(saved);
      _chatRefresh?.call(() {});
    } catch (_) {}
  }

  /// Guarda as conversas no celular (só as dos últimos 7 dias).
  Future<void> _saveChat() async {
    try {
      final old = DateTime.now()
          .subtract(const Duration(days: _chatKeepDays))
          .millisecondsSinceEpoch;
      final out = <String, List<Map<String, dynamic>>>{};
      _chat.forEach((k, v) {
        v.removeWhere((it) => it.at < old);
        if (v.isNotEmpty) out[k] = [for (final it in v) it.toJson()];
      });
      final p = await SharedPreferences.getInstance();
      await p.setString('chat_history', jsonEncode(out));
    } catch (_) {}
  }

  // Mensagens de voz (1.33.0).
  final _voiceRec = AudioRecorder();
  final _voicePlayer = AudioPlayer();
  String? _playing; // arquivo tocando agora
  bool _voiceClean = false;

  Future<void> _playVoice(String path) async {
    try {
      if (_playing == path) {
        await _voicePlayer.stop();
        _playing = null;
      } else {
        await _tts.stop();
        await _voicePlayer.stop();
        _playing = path;
        await _voicePlayer.play(DeviceFileSource(path));
      }
    } catch (_) {
      _playing = null;
    }
    _chatRefresh?.call(() {});
    if (mounted) setState(() {});
  }

  static String _mmss(int ms) {
    final s = (ms / 1000).round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
  final Set<String> _unread = {};
  StateSetter? _chatRefresh; // redesenha a conversa aberta
  String? _chatOpen;

  static const _emojis = [
    '👍', '👋', '😀', '😂', '😉', '😎', '🙏', '❤️', '👌', '✅', '❌', '⚠️',
    '🚛', '🅿️', '⛽', '☕', '🍽️', '😴', '🚨', '👮', '🚧', '🛑', '📍', '🕐',
  ];
  static const _quick = [
    'Onde você está?', 'Tudo bem?', 'Vou parar no próximo park 🅿️',
    'Parando para café ☕', 'Cuidado: polícia à frente 👮',
    'Fila à frente 🚧', 'Me liga quando puder 📞', 'Boa viagem! 🚛',
  ];

  /// Tiques embaixo das minhas mensagens (1.37.0): ✓ enviada,
  /// ✓✓ verde-claro entregue no celular do colega.
  Widget _withTicks(_ChatItem it, Widget child) {
    if (!it.mine || it.docId == null) return child;
    return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          Icon(it.delivered ? Icons.done_all : Icons.done,
              size: 16,
              color: it.delivered
                  ? const Color(0xFFB9F6CA)
                  : Colors.white70),
        ]);
  }

  /// Confere quais mensagens minhas já foram entregues (1.37.0).
  Future<void> _checkDelivered() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    var changed = false;
    for (final list in _chat.values) {
      for (final it in list) {
        if (!it.mine || it.delivered || it.docId == null) continue;
        // Com mais de 24 h quem recebe apaga sem mostrar: para de conferir.
        if (now - it.at > 25 * 3600 * 1000) continue;
        if (await _live.delivered(it.docId!) == true) {
          it.delivered = true;
          changed = true;
        }
      }
    }
    if (changed) {
      _saveChat();
      _chatRefresh?.call(() {});
      if (mounted) setState(() {});
    }
  }

  /// Bipe de mensagem nova (1.37.0), antes da voz ler a mensagem.
  Future<void> _msgBeep() async {
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/msg.wav'), volume: _volume);
      await Future.delayed(const Duration(milliseconds: 600));
    } catch (_) {}
  }

  void _onInbox(LiveMsg msg) {
    final nick = msg.nick.isEmpty ? tr('Um colega') : msg.nick;
    (_chat[msg.from] ??= []).add(_ChatItem(false, msg.text, msg.at,
        audio: msg.audioPath, durMs: msg.durMs));
    _saveChat();
    final shown = msg.isVoice ? tr('🎤 Mensagem de voz') : msg.text;
    final open = _chatOpen == msg.from;
    if (open) {
      _chatRefresh?.call(() {});
    } else {
      _unread.add(msg.from);
    }
    final bg = WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed;
    if (bg) {
      LiveBorder.notifyMsg(nick, shown, from: msg.from, voice: msg.isVoice);
    } else if (!open && mounted) {
      _msgPopup(msg.from, msg.nick, shown, msg.isVoice);
    }
    // 1.37.0: bipe de mensagem nova com o app aberto (minimizado, a
    // notificação já toca o som dela).
    final beep = (_voice && !bg) ? _msgBeep() : Future<void>.value();
    if (msg.isVoice) {
      // Com a voz ligada e o app aberto, anuncia e toca sozinha (mãos no
      // volante); senão fica na conversa com o botão ▶.
      if (_voice && !bg) {
        beep
            .then((_) => _tts.speak(tr('Mensagem de voz de {0}', [nick])))
            .then((_) async {
          await Future.delayed(const Duration(milliseconds: 2500));
          if (_playing == null) _playVoice(msg.audioPath!);
        });
      }
      return;
    }
    if (_voice) {
      final clean = msg.text
          .replaceAll(RegExp(r'[^\p{L}\p{N} .,!?]', unicode: true), '')
          .trim();
      beep.then((_) => _tts.speak(clean.isEmpty
          ? tr('Mensagem de {0}', [nick])
          : '${tr('Mensagem de {0}', [nick])}. $clean'));
    }
  }

  // ---------- Pop-up de mensagem nova (1.34.0) ----------
  OverlayEntry? _msgPop;
  Timer? _msgPopTimer;

  void _closeMsgPopup() {
    _msgPopTimer?.cancel();
    _msgPopTimer = null;
    _msgPop?.remove();
    _msgPop = null;
  }

  /// Card no alto da tela com a foto, o nome e a mensagem do colega.
  /// Tocar abre direto a conversa com ele; deslizar para cima ou o ✕
  /// fecha; some sozinho em 10 s.
  void _msgPopup(String from, String nick, String text, bool voice) {
    _closeMsgPopup();
    final ov = Overlay.maybeOf(context);
    if (ov == null) return;
    final name = nick.isEmpty ? tr('Um colega') : nick;
    final photo = _live.members[from]?.photo;
    _msgPop = OverlayEntry(
      builder: (ctx) => Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: Dismissible(
              key: ValueKey('msgpop$from${DateTime.now().millisecondsSinceEpoch}'),
              direction: DismissDirection.up,
              onDismissed: (_) {
                _msgPop?.remove();
                _msgPop = null;
                _msgPopTimer?.cancel();
              },
              child: Material(
                elevation: 10,
                color: SG.card,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    _closeMsgPopup();
                    _openChatFrom(from, nick);
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                    child: Row(children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: SG.accent,
                        backgroundImage:
                            photo == null ? null : MemoryImage(photo),
                        child: photo == null
                            ? Text(name.characters.first.toUpperCase(),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold))
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('💬 $name',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: SG.text,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15)),
                            const SizedBox(height: 2),
                            Text(text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: SG.text)),
                            const SizedBox(height: 2),
                            Text(
                                voice
                                    ? tr('Toque para ouvir')
                                    : tr('Toque para abrir a conversa'),
                                style: TextStyle(
                                    fontSize: 11, color: SG.textSoft)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, size: 20, color: SG.textSoft),
                        tooltip: tr('Fechar'),
                        onPressed: _closeMsgPopup,
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    ov.insert(_msgPop!);
    _msgPopTimer = Timer(const Duration(seconds: 10), _closeMsgPopup);
  }

  /// Abre a conversa com [from] vindo do pop-up ou da notificação: fecha o
  /// que estiver aberto por cima (outra conversa, lista do grupo,
  /// Configurações…) e abre direto a conversa de quem mandou.
  bool _openingChat = false;
  Future<void> _openChatFrom(String from, String nick) async {
    if (_openingChat || !mounted) return;
    _openingChat = true;
    try {
      _closeMsgPopup();
      LiveBorder.clearChat(from);
      // Veio da notificação: espera o app voltar para a frente.
      for (var i = 0;
          i < 20 &&
              WidgetsBinding.instance.lifecycleState !=
                  AppLifecycleState.resumed;
          i++) {
        await Future.delayed(const Duration(milliseconds: 150));
      }
      if (!mounted || _chatOpen == from) return;
      final nav = Navigator.of(context);
      if (nav.canPop()) {
        nav.popUntil((r) => r.isFirst);
        await Future.delayed(const Duration(milliseconds: 350));
        if (!mounted) return;
      }
      final m = _live.members[from];
      await _chatWith(from, m != null && m.nick.isNotEmpty ? m.nick : nick);
    } finally {
      _openingChat = false;
    }
  }

  Future<void> _chatWith(String id, String nick) async {
    _openingChat = false;
    await _loadChat();
    LiveBorder.clearChat(id);
    final name = nick.isEmpty ? tr('Motorista') : nick;
    final textC = TextEditingController();
    var sending = false;
    var recording = false;
    var recMs = 0;
    Timer? recTimer;
    _chatOpen = id;
    setState(() => _unread.remove(id));
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        _chatRefresh = setS;
        final hist = _chat[id] ?? const [];
        Future<void> send(String t) async {
          if (t.trim().isEmpty || sending) return;
          setS(() => sending = true);
          final docId = await _live.sendMsg(id, t);
          sending = false;
          if (docId != null) {
            (_chat[id] ??= []).add(_ChatItem(
                true, t.trim(), DateTime.now().millisecondsSinceEpoch,
                docId: docId));
            _saveChat();
            textC.clear();
          } else {
            _snack(_live.msgRulesMissing
                ? tr('Falta publicar a regra msgs no Firebase (veja o README).')
                : tr('Não foi possível enviar. Verifique a internet.'));
          }
          if (ctx.mounted) setS(() {});
        }

        // ---- Mensagem de voz (1.33.0): toque no 🎤 grava, toque de novo
        // envia; ✕ cancela; para sozinha em 60 s e envia.
        Future<void> stopRec({required bool sendIt}) async {
          if (!recording) return;
          recTimer?.cancel();
          final dur = recMs;
          String? path;
          try {
            path = await _voiceRec.stop();
          } catch (_) {}
          recording = false;
          if (ctx.mounted) setS(() {});
          if (!sendIt || path == null) return;
          if (dur < 800) {
            _snack(tr('Gravação muito curta.'));
            return;
          }
          final bytes = await File(path).readAsBytes();
          if (bytes.length > LiveService.voiceMaxBytes) {
            _snack(tr('Gravação muito grande.'));
            return;
          }
          if (ctx.mounted) setS(() => sending = true);
          final docId = await _live.sendMsg(id, tr('🎤 Mensagem de voz'),
              audio: bytes, durMs: dur);
          sending = false;
          if (docId != null) {
            (_chat[id] ??= []).add(_ChatItem(true, tr('🎤 Mensagem de voz'),
                DateTime.now().millisecondsSinceEpoch,
                audio: path, durMs: dur, docId: docId));
            _saveChat();
          } else {
            _snack(_live.msgRulesMissing
                ? tr('Falta publicar a regra msgs no Firebase (veja o README).')
                : tr('Não foi possível enviar. Verifique a internet.'));
          }
          if (ctx.mounted) setS(() {});
        }

        Future<void> startRec() async {
          if (recording || sending) return;
          try {
            if (!await _voiceRec.hasPermission()) {
              _snack(tr('Permita o microfone para gravar mensagem de voz.'));
              return;
            }
            final dir = Directory(
                '${(await getApplicationDocumentsDirectory()).path}/voice');
            await dir.create(recursive: true);
            final path =
                '${dir.path}/me_${DateTime.now().millisecondsSinceEpoch}.m4a';
            await _voicePlayer.stop();
            _playing = null;
            await _voiceRec.start(
                const RecordConfig(
                    encoder: AudioEncoder.aacLc,
                    bitRate: 32000,
                    sampleRate: 16000,
                    numChannels: 1),
                path: path);
            HapticFeedback.mediumImpact();
            recording = true;
            recMs = 0;
            final t0 = DateTime.now();
            recTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
              recMs = DateTime.now().difference(t0).inMilliseconds;
              if (recMs >= LiveService.voiceMaxSec * 1000) {
                stopRec(sendIt: true);
              } else if (ctx.mounted) {
                setS(() {});
              }
            });
            if (ctx.mounted) setS(() {});
          } catch (_) {
            recording = false;
            _snack(tr('Não foi possível gravar.'));
          }
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16,
              12 + MediaQuery.viewInsetsOf(ctx).bottom +
                  MediaQuery.viewPaddingOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('Mensagem para {0}', [name]),
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (hist.isNotEmpty)
                ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(ctx).height * 0.25),
                  child: ListView(
                    shrinkWrap: true,
                    reverse: true,
                    children: [
                      for (final it in hist.reversed)
                        Align(
                          alignment: it.mine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            constraints: BoxConstraints(
                                maxWidth: MediaQuery.sizeOf(ctx).width * 0.7),
                            decoration: BoxDecoration(
                              color: it.mine
                                  ? const Color(0xFF7E57C2)
                                  : SG.line,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: _withTicks(it, it.audio == null
                                ? Text(it.text,
                                    style: TextStyle(
                                        color: it.mine ? Colors.white : null))
                                : InkWell(
                                    onTap: () => _playVoice(it.audio!),
                                    child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                              _playing == it.audio
                                                  ? Icons.stop_circle
                                                  : Icons.play_circle_fill,
                                              size: 34,
                                              color: it.mine
                                                  ? Colors.white
                                                  : const Color(0xFF7E57C2)),
                                          const SizedBox(width: 6),
                                          Icon(Icons.graphic_eq,
                                              color: it.mine
                                                  ? Colors.white70
                                                  : null),
                                          const SizedBox(width: 6),
                                          Text(_mmss(it.durMs),
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: it.mine
                                                      ? Colors.white
                                                      : null)),
                                        ]),
                                  )),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                children: [
                  for (final e in _emojis)
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        textC.text = '${textC.text}$e';
                        textC.selection = TextSelection.collapsed(
                            offset: textC.text.length);
                        setS(() {});
                      },
                      onLongPress: () => send(e), // toque longo: envia já
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: Text(e, style: const TextStyle(fontSize: 26)),
                      ),
                    ),
                ],
              ),
              Text(tr('Toque no emoji para escrever; toque longo envia na hora.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: SG.textSoft, fontSize: 11)),
              const SizedBox(height: 6),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final q in _quick)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          label: Text(tr(q)),
                          onPressed: () => send(tr(q)),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (recording)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red),
                  ),
                  child: Row(children: [
                    const Icon(Icons.fiber_manual_record, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          '${tr('Gravando')} ${_mmss(recMs)} / ${_mmss(LiveService.voiceMaxSec * 1000)}',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      tooltip: tr('Cancelar'),
                      onPressed: () => stopRec(sendIt: false),
                      icon: const Icon(Icons.close),
                    ),
                    IconButton.filled(
                      tooltip: tr('Enviar'),
                      style: IconButton.styleFrom(
                          backgroundColor: Colors.red),
                      onPressed: () => stopRec(sendIt: true),
                      icon: const Icon(Icons.send),
                    ),
                  ]),
                )
              else
              Row(children: [
                IconButton.filledTonal(
                  tooltip: tr('Gravar mensagem de voz'),
                  onPressed: sending ? null : startRec,
                  icon: const Icon(Icons.mic),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: textC,
                    maxLength: 300,
                    minLines: 1,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: tr('Escreva a mensagem'),
                      counterText: '',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: send,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: tr('Enviar'),
                  onPressed: sending ? null : () => send(textC.text),
                  icon: sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                ),
              ]),
            ],
          ),
        );
      }),
    );
    // Fechou a janela gravando: descarta a gravação.
    recTimer?.cancel();
    if (recording) {
      try {
        await _voiceRec.cancel();
      } catch (_) {}
    }
    _chatOpen = null;
    _chatRefresh = null;
    if (mounted) setState(() => _unread.remove(id));
  }

  Future<void> _liveTick({bool photo = false}) async {
    if (!mounted) return;
    // 1.29.45: só com Caminhão escolhido nas Configurações.
    if (!_isTruck) {
      if (_live.members.isNotEmpty) setState(() => _live.members.clear());
      return;
    }
    final pos = _pos;
    if (_live.sharing && _live.hasGroup && pos != null) {
      final ok = await _live.push(pos.latitude, pos.longitude, pos.heading,
          pos.speed * 3.6,
          withPhoto: photo || !_livePhotoSent,
          country: _country);
      if (ok) _livePhotoSent = true;
    }
    if (_live.hasGroup) {
      // Mensagens diretas dos colegas (1.32.0). Primeiro as que chegaram
      // com o app fechado (1.33.0), depois as novas.
      if (!_voiceClean) {
        _voiceClean = true;
        LiveService.cleanVoice();
      }
      await _loadChat();
      for (final msg in [
        ...await LiveService.takePending(),
        ...await _live.inbox()
      ]) {
        if (mounted) _onInbox(msg);
      }
      await _checkDelivered();
      if (await _live.refresh()) {
        // Colega atravessou fronteira (1.29.47): notificação + voz.
        for (final (nick, cc) in await _live.borderEvents()) {
          LiveBorder.notify(nick, cc);
          final txt = tr('{0} está {1}', [nick, LiveService.inCountry(cc)]);
          if (_voice) {
            _tts.speak(txt.replaceAll(RegExp(r'[^\p{L}\p{N} ]', unicode: true), ''));
          }
          _snack(txt);
        }
      }
      if (mounted) setState(() {});
    }
  }

  /// Lista dos colegas do grupo (1.29.47): toque leva o mapa até ele.
  void _groupList() {
    final pos = _pos;
    final list = _live.members.values.toList()
      ..sort((a, b) {
        if (pos == null) return a.nick.compareTo(b.nick);
        final da = Geolocator.distanceBetween(
            pos.latitude, pos.longitude, a.lat, a.lon);
        final db = Geolocator.distanceBetween(
            pos.latitude, pos.longitude, b.lat, b.lon);
        return da.compareTo(db);
      });
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 16 + MediaQuery.viewPaddingOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Grupo ({0} no mapa)', [list.length]),
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(tr('Toque num colega para localizá-lo no mapa (o mapa segue ele). 💬 manda mensagem.'),
                style: TextStyle(color: SG.textSoft, fontSize: 12)),
            const SizedBox(height: 8),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                    tr('Ninguém do grupo compartilhando agora.\nOs colegas aparecem aqui quando ligam o compartilhamento com o mesmo código.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: SG.textSoft)),
              )
            else
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final m in list)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: SizedBox(
                          width: 48,
                          child: FittedBox(
                              child: _livePin(m.photo, m.nick,
                                  const Color(0xFF7E57C2)))),
                      title: Text(m.nick.isEmpty ? tr('Motorista') : m.nick,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text([
                        if (m.country.isNotEmpty)
                          '${PresenceService.flag(m.country)} '
                              '${LiveService.countryName(m.country)}',
                        '${m.kmh.round()} km/h',
                        if (pos != null)
                          '${(Geolocator.distanceBetween(pos.latitude, pos.longitude, m.lat, m.lon) / 1000).toStringAsFixed(0)} km',
                        () {
                          final ago = DateTime.now().difference(
                              DateTime.fromMillisecondsSinceEpoch(m.updatedAt));
                          return ago.inMinutes < 1
                              ? tr('agora')
                              : tr('há {0} min', [ago.inMinutes]);
                        }(),
                      ].join(' · ')),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          tooltip: tr('Localizar no mapa'),
                          icon: const Icon(Icons.person_search),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _locate(m);
                          },
                        ),
                        IconButton(
                          tooltip: tr('Mensagem'),
                          icon: Badge(
                            isLabelVisible: _unread.contains(m.id),
                            smallSize: 10,
                            child: const Icon(Icons.chat_bubble_outline),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _chatWith(m.id, m.nick);
                          },
                        ),
                        IconButton(
                          tooltip: tr('Ir até lá (Google Maps)'),
                          icon: const Icon(Icons.directions),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _navigateTo(Park('live', m.nick, m.lat, m.lon,
                                'parking', const {}));
                          },
                        ),
                      ]),
                      onTap: () {
                        Navigator.pop(ctx);
                        _locate(m);
                      },
                    ),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _livePin(Uint8List? photo, String nick, Color color,
          {bool label = false}) =>
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1.29.46: apelido em cima da gota, no mapa.
          if (label && nick.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 2),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              constraints: const BoxConstraints(maxWidth: 110),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(nick,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textScaler: TextScaler.noScaling,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800)),
            ),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 5)],
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            child: photo != null
                ? Image.memory(photo, fit: BoxFit.cover, width: 44, height: 44,
                    gaplessPlayback: true)
                : Text(
                    nick.isEmpty ? '?' : nick.characters.first.toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900)),
          ),
          Transform.translate(
            offset: const Offset(0, -12),
            child: const Icon(Icons.arrow_drop_down,
                color: Colors.white, size: 30),
          ),
        ],
      );

  Future<void> _openMapAt(double lat, double lon) async {
    try {
      await AndroidIntent(
        action: 'action_view',
        data: 'geo:$lat,$lon?q=$lat,$lon',
        package: 'com.google.android.apps.maps',
        flags: const [Flag.FLAG_ACTIVITY_NEW_TASK],
      ).launch();
    } catch (_) {
      _snack(tr('Não foi possível abrir o Google Maps.'));
    }
  }

  void _showMember(LiveMember m) {
    final ago = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(m.updatedAt));
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, 20 + MediaQuery.viewPaddingOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              _livePin(m.photo, m.nick, const Color(0xFF7E57C2)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.nick.isEmpty ? tr('Motorista') : m.nick,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    Text(
                        '${m.kmh.round()} km/h · '
                        '${ago.inMinutes < 1 ? tr('agora') : tr('há {0} min', [ago.inMinutes])}',
                        style: TextStyle(color: SG.textSoft)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.directions),
              label: Text(tr('Ir até lá (Google Maps)')),
              onPressed: () {
                Navigator.pop(ctx);
                _navigateTo(Park('live', m.nick, m.lat, m.lon, 'parking', const {}));
              },
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.person_search),
                  label: Text(tr('Localizar')),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _locate(m);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: Text(tr('Mensagem')),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _chatWith(m.id, m.nick);
                  },
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _groupSheet() async {
    final nickC = TextEditingController(text: _live.nick);
    final groupC = TextEditingController(text: _live.group);
    var share = _live.sharing;
    Uint8List? photo = _live.photo;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20,
              20 + MediaQuery.viewInsetsOf(ctx).bottom +
                  MediaQuery.viewPaddingOf(ctx).bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(tr('Localização em grupo'),
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                Text(
                    tr('Só quem tem o mesmo código de grupo vê você no mapa (e você vê eles). Some do mapa ao desligar ou 5 min sem sinal. Nada fica gravado.'),
                    style: TextStyle(color: SG.textSoft, fontSize: 12)),
                const SizedBox(height: 14),
                Row(children: [
                  _livePin(photo, nickC.text, SG.pink),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.photo),
                      label: Text(tr('Escolher foto')),
                      onPressed: () async {
                        try {
                          final r = await FilePicker.platform.pickFiles(
                              type: FileType.image, withData: true);
                          final b = r?.files.first.bytes;
                          if (b == null) return;
                          final small = await LiveService.shrink(b);
                          if (small != null) setS(() => photo = small);
                        } catch (_) {}
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                TextField(
                  controller: nickC,
                  maxLength: 30,
                  onChanged: (_) => setS(() {}),
                  decoration: InputDecoration(
                      labelText: tr('Apelido (nome que os outros veem)')),
                ),
                TextField(
                  controller: groupC,
                  maxLength: 40,
                  decoration: InputDecoration(
                      labelText: tr('Código do grupo'),
                      helperText:
                          tr('Combine com os colegas. Mínimo 4 letras/números. Quem não sabe o código não vê o grupo.')),
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Compartilhar minha localização')),
                  subtitle: Text(tr('Desligado: você só vê o grupo.')),
                  value: share,
                  onChanged: (v) => setS(() => share = v),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(tr('Salvar')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final nick = nickC.text.trim(), group = groupC.text.trim();
    nickC.dispose();
    groupC.dispose();
    if (ok != true) return;
    if (share && group.length < 4) {
      _snack(tr('O código do grupo precisa ter pelo menos 4 letras ou números.'));
      return;
    }
    final wasSharing = _live.sharing;
    final groupChanged = group != _live.group;
    _live
      ..nick = nick
      ..group = group
      ..photo = photo
      ..sharing = share;
    if (groupChanged) _live.members.clear();
    await _live.save();
    if (wasSharing && !share) await _live.remove();
    _livePhotoSent = false;
    if (share && !_running) await _start();
    if (group.length >= 4) await LiveBorder.askPermission();
    LiveBorder.schedule(_isTruck && group.length >= 4);
    await _liveTick(photo: true);
    if (_live.rulesMissing) {
      _snack(tr('Falta publicar a regra "live" no Firebase (veja o README).'));
    } else {
      _snack(share
          ? tr('Compartilhando com o grupo.')
          : group.length >= 4
              ? tr('Você está vendo o grupo (sem compartilhar).')
              : tr('Localização em grupo desligada.'));
    }
  }

  // ---------- Navegar pela rota gravada (1.29.38) ----------
  TrackNav? _nav;
  int _navOff = 0;
  bool _navOffRoute = false;
  DateTime? _navOffSaid;
  double _navKmh = 0;
  double _navProg = 0;

  void _navSay(String t) {
    if (_voice) _tts.speak(t);
  }

  /// Última navegação que não chegou ao fim (1.29.39).
  Future<(SavedTrack, bool)?> _lastNav() async {
    final p = await SharedPreferences.getInstance();
    try {
      final j = jsonDecode(p.getString('nav_last') ?? '') as Map;
      final t = _rec.tracks.firstWhere((x) => x.id == j['id']);
      return (t, j['rev'] == true);
    } catch (_) {
      return null;
    }
  }

  Future<void> _continueNav() async {
    final l = await _lastNav();
    if (l == null) {
      _snack(tr('Nenhuma rota parada para continuar.'));
      return;
    }
    await _startTrackNav(l.$1, reverse: l.$2, resume: true);
  }

  Future<void> _startTrackNav(SavedTrack t,
      {bool reverse = false, bool resume = false}) async {
    var pts = await _rec.points0(t);
    if (pts.length < 2 || !mounted) return;
    // Está no fim da rota: navega o caminho de volta.
    final pos0 = _pos;
    if (!reverse && pos0 != null) {
      var best = double.infinity, at = 0;
      for (var i = 0; i < pts.length; i++) {
        final d = Geolocator.distanceBetween(
            pos0.latitude, pos0.longitude, pts[i].$1, pts[i].$2);
        if (d < best) {
          best = d;
          at = i;
        }
      }
      if (!resume && best <= 3000 && at > pts.length * 0.8) {
        _snack(tr('Você está no fim desta rota: navegando o caminho de volta.'));
        reverse = true;
      }
    }
    if (reverse) pts = reversedTrack(pts);
    final name = reverse ? tr('{0} (volta)', [t.name]) : t.name;
    // 1.29.39: lembra a navegação para "Continuar rota".
    SharedPreferences.getInstance().then((p) => p.setString(
        'nav_last', jsonEncode({'id': t.id, 'rev': reverse})));
    _route.setTrack(name, pts);
    _nav = TrackNav(_route.pts, _route.cum);
    _navOff = 0;
    _navOffRoute = false;
    _navProg = 0;
    setState(() {
      _shownTrack = [for (final p in pts) LatLng(p.$1, p.$2)];
      _shownTrackName = name;
      _mapView = true;
      _follow = true;
    });
    final pos = _pos;
    if (pos != null) _camTo(pos, 16);
    _parks.clearRoute();
    _parks.loadRoute(_route, country: _country).then((_) {
      if (mounted) setState(() {});
    });
    if (!_running) await _start();
    final pos1 = _pos;
    final left = pos1 == null
        ? _route.total
        : _route.total -
            (_route.progress(pos1.latitude, pos1.longitude) ?? 0);
    _navSay(resume
        ? tr('Continuando a rota {0}. Faltam {1} quilômetros.', [name, (left / 1000).round()])
        : tr('Navegação iniciada pela rota {0}. {1} quilômetros.', [name, (_route.total / 1000).round()]));
  }

  void _stopTrackNav({bool arrived = false}) {
    _nav = null;
    _navOffRoute = false;
    if (arrived) {
      _navSay(tr('Você chegou ao destino.'));
      SharedPreferences.getInstance().then((p) => p.remove('nav_last'));
    }
    _hideTrack();
  }

  void _navTick(Position pos) {
    final nav = _nav;
    if (nav == null) return;
    final kmh = pos.speed * 3.6;
    if (kmh > 5) _navKmh = _navKmh == 0 ? kmh : _navKmh * 0.97 + kmh * 0.03;
    final (i, d, _) = _route.nearest(pos.latitude, pos.longitude);
    // Fora da rota: mais de 80 m da linha em 3 leituras seguidas.
    _navOff = d > 80 ? _navOff + 1 : 0;
    final off = _navOff >= 3;
    if (off != _navOffRoute) setState(() => _navOffRoute = off);
    if (off) {
      final now = DateTime.now();
      if (_navOffSaid == null ||
          now.difference(_navOffSaid!) > const Duration(seconds: 45)) {
        _navOffSaid = now;
        _navSay(tr('Fora da rota. Volte para a linha azul.'));
      }
      return;
    }
    final prog = _route.progress(pos.latitude, pos.longitude) ?? _route.cum[i];
    _navProg = prog;
    if (nav.total - prog < 80) {
      _stopTrackNav(arrived: true);
      return;
    }
    final say = nav.speak(prog, kmh);
    if (say != null) _navSay(say);
    if (mounted) setState(() {});
  }

  Widget _navPanel() {
    final nav = _nav!;
    final t = nav.next(_navProg);
    final left = (nav.total - _navProg).clamp(0, double.infinity);
    final kmh = _navKmh > 20 ? _navKmh : 70.0;
    final eta = DateTime.now()
        .add(Duration(minutes: (left / 1000 / kmh * 60).round()));
    final dist = t == null ? null : t.at - _navProg;
    String km(double m) => m >= 1000
        ? '${(m / 1000).toStringAsFixed(m >= 10000 ? 0 : 1)} km'
        : '${(m / 10).round() * 10} m';
    return Material(
      color: _navOffRoute ? SG.red : const Color(0xFF0B5D3B),
      borderRadius: BorderRadius.circular(16),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(children: [
          Icon(
              _navOffRoute
                  ? Icons.wrong_location
                  : (t?.icon ?? Icons.straight),
              color: Colors.white,
              size: 44),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    _navOffRoute
                        ? tr('Fora da rota')
                        : dist == null
                            ? tr('Siga até o destino')
                            : km(dist),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        height: 1.1)),
                Text(
                    _navOffRoute
                        ? tr('Volte para a linha azul')
                        : t == null
                            ? _route.destName
                            : t.phrase,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
                Text(
                    tr('Faltam {0} · chegada {1}:{2}', [km(left.toDouble()), _two(eta.hour), _two(eta.minute)]),
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            tooltip: tr('Encerrar navegação'),
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => _stopTrackNav(),
          ),
        ]),
      ),
    );
  }
  List<LatLng>? _shownTrack;
  String? _shownTrackName;

  String _two(int n) => n.toString().padLeft(2, '0');
  String _when(DateTime d) =>
      '${_two(d.day)}/${_two(d.month)}/${d.year} ${_two(d.hour)}:${_two(d.minute)}';
  String _dur(Duration d) =>
      d.inHours > 0 ? tr('{0} h {1} min', [d.inHours, _two(d.inMinutes % 60)]) : '${d.inMinutes} min';

  Future<String?> _askName(String title, String initial) async {
    final c = TextEditingController(text: initial);
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 60,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: tr('Nome da rota')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('Cancelar'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: Text(tr('Salvar'))),
        ],
      ),
    );
    c.dispose();
    return r;
  }

  Future<void> _startRecording() async {
    await _rec.start();
    if (!_running) await _start();
    if (mounted) setState(() {});
    _snack(tr('Gravando a rota. Para parar: botão Rotas → Parar gravação.'));
  }

  /// Continuar gravando uma rota já salva (1.29.41).
  Future<void> _resumeRecording(SavedTrack t) async {
    if (_rec.recording) {
      _snack(tr('Já está gravando. Pare a gravação atual antes.'));
      return;
    }
    await _rec.resume(t);
    if (!_running) await _start();
    if (mounted) setState(() {});
    _snack(tr('Continuando a gravação de "{0}" ({1} km). O caminho novo entra no fim dela.', [t.name, t.km.toStringAsFixed(1)]));
  }

  Future<void> _stopRecording() async {
    final cont = _rec.appendTo == null
        ? null
        : _rec.tracks.where((t) => t.id == _rec.appendTo).firstOrNull;
    final def = cont?.name ?? tr('Rota {0}', [_when(DateTime.now())]);
    final name = await _askName(tr('Salvar rota gravada'), def);
    if (name == null) return; // continua gravando
    final t = await _rec.stop(name.isEmpty ? def : name);
    if (mounted) setState(() {});
    _snack(t == null
        ? tr('Rota muito curta, não foi salva.')
        : tr('Rota "{0}" salva ({1} km).', [t.name, t.km.toStringAsFixed(1)]));
  }

  Future<void> _showTrack(SavedTrack t) async {
    _nav = null;
    final pts = await _rec.points0(t);
    if (pts.length < 2 || !mounted) return;
    final ll = [for (final p in pts) LatLng(p.$1, p.$2)];
    setState(() {
      _shownTrack = ll;
      _shownTrackName = t.name;
      _mapView = true;
      _follow = false;
    });
    try {
      _map.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(ll),
          padding: const EdgeInsets.all(48)));
    } catch (_) {}
    // Parks do caminho na lista do P, como numa rota de Navegar.
    _route.setTrack(t.name, pts);
    _parks.clearRoute();
    _parks.loadRoute(_route, country: _country).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _hideTrack() {
    setState(() {
      _shownTrack = null;
      _shownTrackName = null;
    });
    _route.clear();
    _parks.clearRoute();
  }

  Future<void> _trackToGoogle(SavedTrack t, {bool reverse = false}) async {
    var pts = await _rec.points0(t);
    if (pts.length < 2) return;
    if (reverse) pts = reversedTrack(pts);
    var from = 0;
    final pos = _pos;
    if (pos != null) {
      var best = double.infinity;
      for (var i = 0; i < pts.length; i++) {
        final d = Geolocator.distanceBetween(
            pos.latitude, pos.longitude, pts[i].$1, pts[i].$2);
        if (d < best) {
          best = d;
          from = i;
        }
      }
      if (best > 3000) from = 0;
      // 1.29.38: está no fim da rota (ex.: gravou até aqui) → o Google
      // abria só os últimos metros. Abre o caminho de volta.
      if (!reverse && best <= 3000 && from > pts.length * 0.8) {
        _snack(tr('Você está no fim desta rota: abrindo o caminho de volta.'));
        return _trackToGoogle(t, reverse: true);
      }
    }
    final url = TrackRecorder.googleUrl(pts, from: from);
    try {
      await AndroidIntent(
        action: 'action_view',
        data: url,
        package: 'com.google.android.apps.maps',
        flags: const [Flag.FLAG_ACTIVITY_NEW_TASK],
      ).launch();
    } catch (_) {
      try {
        await AndroidIntent(
                action: 'action_view',
                data: url,
                flags: const [Flag.FLAG_ACTIVITY_NEW_TASK])
            .launch();
      } catch (_) {
        _snack(tr('Não foi possível abrir o Google Maps.'));
      }
    }
  }

  Future<void> _shareTrack(SavedTrack t) async {
    final f = await _rec.fileOf(t);
    final safe = t.name.replaceAll(RegExp(r'[^\w\- ]'), '').trim();
    final tmp = File('${f.parent.path}/${safe.isEmpty ? 'rota' : safe}.gpx');
    await f.copy(tmp.path);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(tmp.path, mimeType: 'application/gpx+xml')],
      text: tr('Rota "{0}" ({1} km), gravada no SpeedGuard. Abra no SpeedGuard (Rotas → Importar) ou em outro app de GPS.', [t.name, t.km.toStringAsFixed(0)]),
    ));
  }

  Future<void> _importTrack() async {
    FilePickerResult? res;
    try {
      res = await FilePicker.platform
          .pickFiles(type: FileType.any, withData: true);
    } catch (_) {
      _snack(tr('Não consegui abrir os arquivos.'));
      return;
    }
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    var bytes = f.bytes;
    if (bytes == null && f.path != null) bytes = await File(f.path!).readAsBytes();
    if (bytes == null) return;
    final t = await _rec.importGpx(utf8.decode(bytes, allowMalformed: true),
        f.name.replaceAll(RegExp(r'\.gpx$', caseSensitive: false), ''));
    if (mounted) setState(() {});
    _snack(t == null
        ? tr('Esse arquivo não tem uma rota (GPX).')
        : tr('Rota "{0}" importada ({1} km).', [t.name, t.km.toStringAsFixed(0)]));
  }

  void _trackActions(SavedTrack t) {
    // 1.29.40: rola (antes os últimos botões ficavam escondidos embaixo).
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      builder: (ctx) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, 24 + MediaQuery.viewPaddingOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Continuar a navegação desta rota que foi parada.
            FutureBuilder<(SavedTrack, bool)?>(
              future: _lastNav(),
              builder: (c, snap) {
                final l = snap.data;
                if (l == null || l.$1.id != t.id || _nav != null) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0B8F5A),
                        foregroundColor: Colors.white),
                    icon: const Icon(Icons.play_arrow),
                    label: Text(tr('Continuar rota{0}', [l.$2 ? tr(' (volta)') : ''])),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _continueNav();
                    },
                  ),
                );
              },
            ),
            Text(t.name,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text('${_when(t.start)} · ${t.km.toStringAsFixed(1)} km'
                '${t.duration.inMinutes > 0 ? ' · ${_dur(t.duration)}' : ''}',
                style: TextStyle(color: SG.textSoft)),
            const SizedBox(height: 14),
            // 1.29.38: navegar pela rota dentro do app.
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0B8F5A),
                  foregroundColor: Colors.white),
              icon: const Icon(Icons.navigation),
              label: Text(tr('Navegar por esta rota (no app)')),
              onPressed: () {
                Navigator.pop(ctx);
                _startTrackNav(t);
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.swap_vert),
              label: Text(tr('Navegar no sentido contrário (volta)')),
              onPressed: () {
                Navigator.pop(ctx);
                _startTrackNav(t, reverse: true);
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.fiber_manual_record, color: Colors.red),
              label: Text(tr('Continuar gravando esta rota')),
              onPressed: () {
                Navigator.pop(ctx);
                _resumeRecording(t);
              },
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.map),
              label: Text(tr('Ver no mapa')),
              onPressed: () {
                Navigator.pop(ctx);
                _showTrack(t);
              },
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.directions),
              label: Text(tr('Seguir no Google Maps')),
              onPressed: () {
                Navigator.pop(ctx);
                _trackToGoogle(t);
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.swap_vert),
              label: Text(tr('Google Maps no sentido contrário (volta)')),
              onPressed: () {
                Navigator.pop(ctx);
                _trackToGoogle(t, reverse: true);
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.share),
              label: Text(tr('Compartilhar')),
              onPressed: () {
                Navigator.pop(ctx);
                _shareTrack(t);
              },
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.edit),
                  label: Text(tr('Renomear')),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final n = await _askName(tr('Renomear rota'), t.name);
                    if (n == null || n.isEmpty) return;
                    await _rec.rename(t, n);
                    if (mounted) setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: SG.red),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(tr('Excluir')),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (d) => AlertDialog(
                        title: Text(tr('Excluir rota?')),
                        content: Text(tr('"{0}" será apagada do celular.', [t.name])),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(d, false),
                              child: Text(tr('Cancelar'))),
                          FilledButton(
                              onPressed: () => Navigator.pop(d, true),
                              child: Text(tr('Excluir'))),
                        ],
                      ),
                    );
                    if (ok != true) return;
                    if (_shownTrackName == t.name) _hideTrack();
                    await _rec.delete(t);
                    if (mounted) setState(() {});
                  },
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _tracksSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              16, 12, 16, 16 + MediaQuery.viewPaddingOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('Rotas gravadas'),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              Text(tr('Ficam só no seu celular.'),
                  style: TextStyle(color: SG.textSoft, fontSize: 12)),
              const SizedBox(height: 10),
              if (_rec.recording)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: SG.red, foregroundColor: Colors.white),
                  icon: const Icon(Icons.stop),
                  label: Text(tr('Parar gravação ({0} km)', [_rec.km.toStringAsFixed(1)])),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _stopRecording();
                  },
                )
              else
                FilledButton.icon(
                  icon: const Icon(Icons.fiber_manual_record,
                      color: Colors.red),
                  label: Text(tr('Gravar rota agora')),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _startRecording();
                  },
                ),
              // 1.29.39: continuar a navegação que foi parada.
              FutureBuilder<(SavedTrack, bool)?>(
                future: _lastNav(),
                builder: (c, snap) {
                  final l = snap.data;
                  if (l == null || _nav != null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0B8F5A),
                          foregroundColor: Colors.white),
                      icon: const Icon(Icons.play_arrow),
                      label: Text(
                          tr('Continuar rota: {0}{1}', [l.$1.name, l.$2 ? tr(' (volta)') : '']),
                          overflow: TextOverflow.ellipsis),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _continueNav();
                      },
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.file_open),
                label: Text(tr('Importar rota (arquivo GPX)')),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _importTrack();
                },
              ),
              const SizedBox(height: 8),
              if (_rec.tracks.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(tr('Nenhuma rota gravada ainda.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: SG.textSoft)),
                )
              else
                Flexible(
                  child: ListView(shrinkWrap: true, children: [
                    for (final t in _rec.tracks)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.route, size: 32),
                        title: Text(t.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${_when(t.start)} · '
                            '${t.km.toStringAsFixed(1)} km'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.pop(ctx);
                          _trackActions(t);
                        },
                      ),
                  ]),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Marcando o park no mapa (1.29.32): tipo e nome já escolhidos.
  (String, String)? _placing;
  /// Mudando de lugar um park seu (1.29.34).
  Park? _moving;
  /// Ids dos parks adicionados neste aparelho (só o dono muda/exclui).
  final Set<String> _myParkIds = {};

  Future<List> _myParksJson() async {
    final p = await SharedPreferences.getInstance();
    try {
      return jsonDecode(p.getString('my_parks') ?? '[]') as List;
    } catch (_) {
      return [];
    }
  }

  Future<void> _forgetMine(String id) async {
    final mine = await _myParksJson()..removeWhere((e) => e['id'] == id);
    final p = await SharedPreferences.getInstance();
    await p.setString('my_parks', jsonEncode(mine));
    _myParkIds.remove(id);
    _parks.userParks = [
      for (final x in _parks.userParks)
        if (x.id != id) x
    ];
  }

  Future<void> _deletePark(Park park) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Excluir park?')),
        content: Text(tr('"{0}" some para todos os motoristas.', [park.name])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Cancelar'))),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: SG.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Excluir'))),
        ],
      ),
    );
    if (ok != true) return;
    if (park.id.startsWith('cm_') && !await _community.expirePark(park.id)) {
      _snack(tr('Sem internet: não consegui excluir. Tente de novo.'));
      return;
    }
    await _forgetMine(park.id);
    if (mounted) setState(() {});
    _snack(tr('Park excluído.'));
  }

  void _startMove(Park park) {
    setState(() {
      _moving = park;
      _placing = (park.tags['ptype'] ?? 'park_zona',
          park.name == Park.userTypeLabel(park.tags['ptype'] ?? '').$1
              ? ''
              : park.name);
      _mapView = true;
      _follow = false;
    });
    _map.move(LatLng(park.lat, park.lon), 17);
    _snack(tr('Toque no mapa (ou arraste) até o lugar certo e confirme.'));
  }

  Future<void> _confirmPlace(double lat, double lon) async {
    final (t, n) = _placing!;
    final old = _moving;
    setState(() {
      _placing = null;
      _moving = null;
    });
    if (old != null) {
      // Mudar de lugar: o antigo some e entra o novo (as regras do
      // Firebase não deixam mudar a posição de um documento).
      if (old.id.startsWith('cm_') && !await _community.expirePark(old.id)) {
        _snack(tr('Sem internet: não consegui mudar o park. Tente de novo.'));
        return;
      }
      await _forgetMine(old.id);
    }
    await _savePark(lat, lon, t, n);
  }

  /// Aviso antes de adicionar park (1.29.33): balão com X para fechar.
  Future<bool> _parkWarning() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded,
            color: Colors.amber, size: 40),
        title: Row(children: [
          Expanded(child: Text(tr('Atenção, motorista!'))),
          IconButton(
            tooltip: tr('Fechar'),
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ]),
        content: Text(
          tr('Só adicione um park onde você mesmo parou com o caminhão e tem certeza de que o caminhão entra, manobra e sai.\n\nPark adicionado aparece para todos os motoristas. Um park errado ou inventado pode levar um colega a um lugar sem saída, sem vaga ou proibido — de madrugada, cansado e sem tempo de direção.\n\nNa dúvida, não adicione.'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Cancelar'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Entendi'))),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _addPark() async {
    // Só caminhão adiciona park (1.29.34): evita park falso de quem usa o
    // app no carro.
    if (!_isTruck) {
      _snack(tr('Adicionar park é só para quem escolheu Caminhão nas Configurações.'));
      return;
    }
    if (!await _parkWarning()) return;
    final pos = _pos ?? await _currentPos();
    if (!mounted) return;
    final nameCtrl = TextEditingController();
    String? type;
    var onMap = pos == null; // sem GPS: só marcando no mapa
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          Widget opt(String t, IconData icon, String label, String sub) =>
              RadioListTile<String>(
                value: t,
                groupValue: type,
                onChanged: (v) => setD(() => type = v),
                contentPadding: EdgeInsets.zero,
                secondary: Icon(icon),
                title: Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
              );
          return AlertDialog(
            title: Text(tr('Adicionar park aqui')),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                opt('park_privado', Icons.local_parking, tr('Park privado'),
                    tr('Pago')),
                opt('park_free', Icons.money_off, tr('Park free'), tr('Grátis')),
                opt('park_zona', Icons.factory_outlined, tr('Zona industrial'),
                    tr('Onde caminhão estaciona, entra e sai')),
                const SizedBox(height: 8),
                // 1.29.32: onde fica o park.
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                        value: false,
                        icon: Icon(Icons.my_location),
                        label: Text(tr('Onde estou'))),
                    ButtonSegment(
                        value: true,
                        icon: Icon(Icons.touch_app),
                        label: Text(tr('Marcar no mapa'))),
                  ],
                  selected: {onMap},
                  onSelectionChanged: pos == null
                      ? null
                      : (v) => setD(() => onMap = v.first),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nameCtrl,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                      labelText: tr('Nome (opcional)'),
                      hintText: tr('Ex.: Park Los Pinos')),
                ),
              ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(tr('Cancelar'))),
              FilledButton(
                  onPressed:
                      type == null ? null : () => Navigator.pop(ctx, true),
                  child: Text(tr('Adicionar'))),
            ],
          );
        },
      ),
    );
    final name = nameCtrl.text.trim();
    nameCtrl.dispose();
    if (ok != true || type == null) return;
    if (onMap || pos == null) {
      // Marca no mapa: alfinete no centro; toque no mapa leva o alfinete.
      setState(() {
        _placing = (type!, name);
        _mapView = true;
        _follow = false;
      });
      _snack(tr('Toque no mapa (ou arraste) até o local exato e confirme.'));
      return;
    }
    await _savePark(pos.latitude, pos.longitude, type!, name);
  }

  Future<void> _savePark(
      double lat, double lon, String type, String name) async {
    final id = await _community.reportPark(
            lat, lon, type, name, _goodHeading) ??
        'local_${DateTime.now().millisecondsSinceEpoch}';
    final park = Park.user(id, lat, lon, type, name);
    _parks.userParks = [..._parks.userParks, park];
    final p = await SharedPreferences.getInstance();
    List mine;
    try {
      mine = jsonDecode(p.getString('my_parks') ?? '[]') as List;
    } catch (_) {
      mine = [];
    }
    mine.add({
      'id': id,
      'lat': lat,
      'lon': lon,
      't': type,
      'n': name,
    });
    await p.setString('my_parks', jsonEncode(mine));
    _myParkIds.add(id);
    if (mounted) setState(() {});
    _snack(id.startsWith('local_')
        ? tr('Park salvo neste aparelho (sem internet para enviar).')
        : tr('Park adicionado! Ele aparece para todos os motoristas.'));
  }

  /// Botão "P+" verde ao lado do P (1.29.31): adicionar park aqui.
  Widget _addParkButton() => Material(
        color: const Color(0xFF2E7D32),
        shape: CircleBorder(side: BorderSide(color: SG.outline, width: 1.5)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _addPark,
          child: const SizedBox(
            width: 46,
            height: 46,
            child: Center(
              child: Text('P+',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w900)),
            ),
          ),
        ),
      );

  /// Botão "P" ao lado de Navegar: abre a lista dos 3 parks à frente.
  /// Toque longo: adicionar park aqui (1.29.30).
  Widget _parkButton() => Material(
        color: const Color(0xFF1565C0),
        shape: CircleBorder(side: BorderSide(color: SG.outline, width: 1.5)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _parksSheet,
          onLongPress: _isTruck ? _addPark : null,
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
      _snack(tr('Aguardando o sinal do GPS…'));
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
              title = tr('Próximos parks até {0}', [_route.destName]);
              hint = _parks.routeLoading
                  ? tr('Buscando mais parks da rota…')
                  : tr('Distância pela estrada');
            } else {
              list = _parks.ahead(pos.latitude, pos.longitude,
                  pos.speed > 2.5 ? pos.heading : -1,
                  country: _country);
              final noDir = !_parks.hasHeading;
              if (noDir) list = _parks.nearest(pos.latitude, pos.longitude);
              title = noDir ? tr('Parks mais perto') : tr('Parks à frente');
              hint = routing && _parks.routeLoading
                  ? tr('Buscando os parks da rota… abra de novo em instantes.')
                  : noDir
                      ? tr('Comece a andar para ver só os do seu sentido.')
                      : tr('Digite o destino em Navegar para ver todos os parks da rota.');
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
                  // Park de motorista: toque longo abre as opções (o dono
                  // muda de lugar ou exclui).
                  onLongPress: a.park.isUser
                      ? () {
                          Navigator.pop(ctx);
                          _showUserPark(a.park);
                        }
                      : null,
                  // Park adicionado por motorista: "P+" verde (1.29.30).
                  leading: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: a.park.isUser
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFF1565C0),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(a.park.isUser ? 'P+' : 'P',
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
                    if (a.side != null) tr('à {0}', [tr(a.side!)]),
                    ...a.park.features,
                  ].join(' · ')),
                  // Compartilhar (separado) e rota.
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: tr('Compartilhar'),
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
                  // 1.29.30: park que não está no mapa (só caminhão).
                  if (_isTruck)
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _addPark();
                    },
                    icon: const Icon(Icons.add_location_alt),
                    label: Text(tr('Adicionar park aqui')),
                  ),
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
                              ? tr('Nenhum park à frente nesta rota.')
                              : tr('Nenhum park encontrado à frente (até 60 km).'),
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
                      label: Text(tr('Encerrar rota')),
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
        if (a.side != null) tr('à {0}', [tr(a.side!)]),
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
                color: p.isUser
                    ? const Color(0xFF2E7D32)
                    : const Color(0xFF1565C0),
                borderRadius: BorderRadius.circular(6)),
            child: Text(p.isUser ? 'P+' : 'P',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: p.isUser ? 17 : 22,
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
            tooltip: tr('Compartilhar'),
            icon: const Icon(Icons.share, size: 20),
            onPressed: () => _sharePark(p),
          ),
          IconButton(
            tooltip: tr('Ir até o park'),
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
          say = tr('Limite da via {0}.', [road]);
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
        onRoad: (r) {
          // Marcado por você como "da outra pista" neste sentido (1.29.28).
          if (_removed.wrongSide(r, pos.heading)) return false;
          return _sameRoadCheck(pos, r);
        });
    _afterAlerts(st);
  }

  bool? _sameRoadCheck(Position pos, Radar r) {
    return _sameRoad
            ? (() {
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
              })()
            : null;
  }

  void _afterAlerts(AlertState st) {
    if (st.speak != null || st.beeps > 0) {
      HapticFeedback.heavyImpact();
      if (_voice) {
        if (_sound == 'beep' && st.beeps > 0) {
          _beep(st.beeps);
        } else if (st.speak != null) {
          _tts.speak(!_discreet
              ? st.speak!
              : st.beeps == AlertEngine.overBeep
                  ? tr('Reduza.')
                  : st.beeps > 0
                      ? '${AlertEngine.stages[st.beeps - 1]} metros.'
                      : tr('Radar.'));
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _alert = st;
      if (_rule.mode == RadarMode.disabled) {
        _status = tr('Alertas desligados neste país');
      } else if (st.radar == null) {
        _status = tr('{0} radares carregados na região', [_allRadars.length]);
      }
    });
    _syncRingPopup();
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
      _say(tr('O radar móvel ainda está aí? Responda na tela.'));
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
        ? tr('Sem conexão: resposta não enviada.')
        : stillThere
            ? tr('Obrigado! Radar mantido por mais 48 horas.')
            : tr('Obrigado! Radar removido.'));
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
      _say(tr('Você entrou em {0}.', [_rule.name]));
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(_rule.name),
          content: Text(notice),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr('Entendi'))),
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
      _snack(tr('Sem conexão para baixar radares. Usando os já salvos.'));
    }
  }

  Widget _pill(IconData icon, String label, VoidCallback onTap) => Material(
        color: SG.cardHigh,
        shape: StadiumBorder(side: BorderSide(color: SG.outline, width: 1.5)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            // 1.29.31: um pouco mais estreito, para caber o botão P+.
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            Text(tr('Navegar'),
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              textInputAction: TextInputAction.go,
              decoration: InputDecoration(
                hintText: tr('Para onde? (endereço, cidade ou lugar)'),
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
                  ? tr('O SpeedGuard continua avisando os radares no painel flutuante.')
                  : tr('Dica: ligue a Bolha flutuante em Configurações para ver os radares por cima do mapa.'),
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
          ? tr('Não foi possível abrir o Waze. Ele está instalado?')
          : tr('Não foi possível abrir o Google Maps. Ele está instalado?'));
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
              ? tr('{0} · some após 6 h', [l.subtitle])
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
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(tr('Opções do mapa'),
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ),
                for (final l in Layer.values.where((l) => !l.isEvent))
                  item(l, setSheet),
                const Divider(indent: 16, endIndent: 16),
                for (final l in Layer.events) item(l, setSheet),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(tr('MAIS'),
                      style: TextStyle(
                          color: SG.textSoft, fontWeight: FontWeight.w600)),
                ),
                SwitchListTile(
                  secondary: Icon(Icons.my_location, color: SG.accent),
                  title: Text(tr('O mapa segue você'),
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(tr('Desloca o mapa com a sua posição')),
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
                  title: Text(tr('Mapa gira com o veículo'),
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      tr('Ligado: a seta fica sempre para cima e o mapa vira conforme você anda. Desligado: norte sempre em cima.')),
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
          ? tr('Sem sinal de GPS. Aviso não salvo.')
          : tr('Aguarde o sinal do GPS para reportar.'));
      return;
    }
    if (!communityEnabled) {
      tell(tr('Avisos precisam do Firebase configurado.'));
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
          ? tr('{0} já reportado. Confirmado, obrigado!', [l.label])
          : tr('{0}: já reportado aqui. Confirmado por mais 6 h.', [l.label]));
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
            ? tr('{0} reportado. Obrigado!', [l.label])
            : tr('{0} reportado para todos. Some em 6 h.', [l.label]))
        : tr('Sem conexão: não foi possível reportar.'));
  }

  Future<void> _report() async {
    if (_pos == null) {
      _snack(tr('Aguarde o sinal do GPS para reportar.'));
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
                    ? tr('Todos verão este radar. Radares móveis são confirmados a cada 48 h por quem passar.')
                    : tr('O radar fica salvo só neste aparelho.'),
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
        _say(tr('Sem sinal de GPS. Radar não salvo.'));
      } else {
        _snack(tr('Aguarde o sinal do GPS para reportar.'));
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
          _say(tr('Radar já reportado. Confirmado, obrigado!'));
        } else {
          _snack(tr('Esse radar já estava reportado. Confirmado, obrigado!'));
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
      _say(tr('Radar reportado. Obrigado!'));
      return;
    }
    if (shared) {
      _snack(tr('Radar compartilhado com todos. Obrigado!'));
    } else if (communityEnabled) {
      _snack(tr('Sem conexão: radar salvo só neste aparelho.'));
    } else {
      _snack(tr('Radar salvo neste aparelho.'));
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
    _snack(tr('Radar escondido. Obrigado pelo aviso!'));
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
                ? tr('Limite: {0} km/h', [r.maxSpeed])
                : tr('Limite não informado')),
            if (r.type == 'usuario') ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.delete_outline),
                label: Text(tr('Excluir este radar')),
                onPressed: () async {
                  await _service.removeUserRadar(r.id);
                  if (!mounted) return;
                  Navigator.pop(context);
                  setState(() {});
                },
              ),
            ],
            if (r.type != 'usuario') ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.swap_horiz),
                label: Text(tr('Este radar é da outra pista')),
                onPressed: _goodHeading < 0
                    ? null
                    : () async {
                        Navigator.pop(context);
                        await _removed.markWrongSide(r, _goodHeading);
                        if (mounted) setState(() {});
                        _snack(tr('Pronto: neste sentido ele não avisa mais. Na pista dele continua avisando.'));
                      },
              ),
              const SizedBox(height: 4),
              Text(
                  _goodHeading < 0
                      ? tr('Para usar, ande um pouco (o app precisa saber o seu sentido).')
                      : tr('Use quando o app avisar um radar da pista contrária: ele para de avisar no seu sentido.'),
                  style: const TextStyle(fontSize: 12, color: Colors.white60)),
            ],
            if (r.type != 'usuario' && !r.isEvent) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.not_interested),
                label: Text(tr('Este radar não existe mais')),
                onPressed: () async {
                  Navigator.pop(context);
                  await _radarGone(r);
                },
              ),
              const SizedBox(height: 4),
              Text(
                  tr('Some na hora para você. Para os outros motoristas, some quando 2 pessoas avisarem.'),
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
                title: Text(tr('Parks à frente')),
                subtitle: Text(
                    tr('Áreas de descanso, de serviço e estacionamentos de caminhão no seu sentido, com aviso a 2 km')),
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
                  title: Text(tr('Só parks de caminhão')),
                  subtitle: Text(
                      tr('Estacionamentos e paradas de caminhão. Desligado: também as áreas de descanso e de serviço sem vaga de caminhão marcada')),
                  value: _parks.truckOnly,
                  onChanged: (v) async {
                    final p = await SharedPreferences.getInstance();
                    await p.setBool('parks_truck_only', v);
                    setSheet(() => _parks.truckOnly = v);
                    setState(() {});
                  },
                ),
              SwitchListTile(
                title: Text(tr('Aviso de pedágio')),
                subtitle: Text(
                    tr('Avisa uma vez, a 1000 m, com voz e na tela')),
                value: _tolls.enabled,
                onChanged: (v) async {
                  final p = await SharedPreferences.getInstance();
                  await p.setBool('toll_warn', v);
                  setSheet(() => _tolls.enabled = v);
                },
              ),
              SwitchListTile(
                title: Text(tr('Só radares da minha via')),
                subtitle: Text(
                    tr('Avisa só os radares da rodovia/rua onde você está. Radares de ruas ao lado ou que cruzam são ignorados')),
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
                  title: Text(tr('Radares escondidos')),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_removed.mineCount == 1
                          ? tr('1 radar marcado por você como "não existe mais"')
                          : tr('{0} radares marcados por você como "não existe mais"', [_removed.mineCount])),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        label: Text(tr('Mostrar de novo')),
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
                title: Text(tr('Aviso de velocidade excedida')),
                subtitle: Text(_isTruck
                    ? tr('Caminhão: passou de {0}, o velocímetro fica vermelho com a contagem; aos 20 s "Atenção" e aos 30 s "Velocidade excedida. Tempo excedido". Mostra o limite da via', [_truckMax])
                    : tr('Passou do limite da via: velocímetro vermelho com a contagem; aos 20 s "Atenção" e aos 30 s "Velocidade excedida"')),
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
                    Text(tr('Som do aviso de velocidade (Mudo: só o aviso na tela)')),
                    const SizedBox(height: 6),
                    SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                            value: 'voice',
                            icon: Icon(Icons.record_voice_over),
                            label: Text(tr('Voz'))),
                        ButtonSegment(
                            value: 'beep',
                            icon: Icon(Icons.notifications_active),
                            label: Text(tr('Bipe'))),
                        ButtonSegment(
                            value: 'mute',
                            icon: Icon(Icons.volume_off),
                            label: Text(tr('Mudo'))),
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
                          _tts.speak(tr('Atenção.'));
                        }
                      },
                    ),
                  ]),
                ),
              if (_speedWarn && _isTruck)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(children: [
                    Expanded(
                        child: Text(tr('Limitador do caminhão\nComeça a contar os 30 s acima de'),
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
                title: Text(tr('Alertas sonoros')),
                subtitle: Text(tr('Avisos a 1000, 800, 500, 400, 300 e 100 m do radar')),
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
                    segments: [
                      ButtonSegment(
                          value: 'voice',
                          icon: Icon(Icons.record_voice_over),
                          label: Text(tr('Voz'))),
                      ButtonSegment(
                          value: 'beep',
                          icon: Icon(Icons.notifications_active),
                          label: Text(tr('Bipe'))),
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
                        _tts.speak(tr('Radar fixo a 1000 metros. Limite 80.'));
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
                          _tts.speak(tr('Volume {0} por cento.', [(v * 100).round()]));
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
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                    tr('Volume dos avisos (voz e bipes). 100% = volume do celular'),
                    style: TextStyle(fontSize: 12)),
              ),
              SwitchListTile(
                title: Text(tr('Modo discreto')),
                subtitle: Text(tr('Na voz, fala só a distância ("500 metros")')),
                value: _discreet,
                onChanged: (v) async {
                  final p = await SharedPreferences.getInstance();
                  await p.setBool('discreet', v);
                  setSheet(() => _discreet = v);
                },
              ),
              SwitchListTile(
                title: Text(tr('Bolha flutuante')),
                subtitle: Text(
                    tr('Mostra velocidade e radar por cima do Maps/Waze')),
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
                  title: Text(tr('Testar pop-up do radar e da contagem')),
                  subtitle: Text(
                      tr('Radar e contagem de mentira (35 s): toque, minimize o app e abra outro (ex.: YouTube) — o aviso do radar e o círculo vermelho têm de aparecer por cima')),
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
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(tr('Tamanho do painel')),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SegmentedButton<double>(
                    showSelectedIcon: false,
                    segments: [
                      for (final e in kPanelScales.entries)
                        ButtonSegment(value: e.value, label: Text(tr(e.key))),
                    ],
                    selected: {_bubbleScale},
                    onSelectionChanged: (v) async {
                      final p = await SharedPreferences.getInstance();
                      await p.setDouble('bubbleScale', v.first);
                      setSheet(() => _bubbleScale = v.first);
                    },
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(tr('Formato do painel')),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                          value: false,
                          icon: Icon(Icons.crop_portrait),
                          label: Text(tr('Vertical'))),
                      ButtonSegment(
                          value: true,
                          icon: Icon(Icons.crop_landscape),
                          label: Text(tr('Horizontal'))),
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
              Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(tr('Ícone no mapa')),
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
              Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(tr('Cores do app')),
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
                            Text(tr(pal.name), style: const TextStyle(fontSize: 12)),
                          ]),
                        ),
                    ],
                  ),
                ),
              ),
              // 1.30.0: idioma do app e dos avisos falados.
              ListTile(
                leading: const Icon(Icons.language),
                title: Text(tr('Idioma')),
                subtitle: Text(tr('Textos do app e avisos de voz')),
                trailing: DropdownButton<String>(
                  value: langChoice,
                  underline: const SizedBox(),
                  items: [
                    DropdownMenuItem(value: '', child: Text(tr('Auto'))),
                    for (final e in kLangs.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) async {
                    if (v == null) return;
                    await setLang(v);
                    await _tts.setLanguage(ttsLang);
                    _sendBubble();
                    if (mounted) setState(() {});
                    setSheet(() {});
                  },
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(tr('Aparência')),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ValueListenableBuilder<ThemeMode>(
                  valueListenable: SG.mode,
                  builder: (_, mode, __) => SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                          value: ThemeMode.system,
                          icon: Icon(Icons.brightness_auto),
                          label: Text(tr('Auto'))),
                      ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode),
                          label: Text(tr('Claro'))),
                      ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode),
                          label: Text(tr('Escuro'))),
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
                title: Text(tr('Tutorial')),
                subtitle: Text(tr('Vídeo de como configurar e usar o app')),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const TutorialPage()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: Text(tr('Ajuda')),
                subtitle: Text(tr('Perguntas e respostas (funciona sem internet)')),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const HelpPage()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: Text(tr('Atualizar radares agora')),
                onTap: () {
                  Navigator.pop(ctx);
                  if (_pos != null) {
                    _areaBounds = null;
                    _refresh(_pos!, force: true);
                    _community.refresh(_pos!.latitude, _pos!.longitude);
                  }
                },
              ),
              if (_isTruck)
              ListTile(
                leading: const Icon(Icons.groups),
                title: Text(tr('Localização em grupo')),
                subtitle: Text(_live.sharing
                    ? tr('Compartilhando · {0} no mapa', [_live.members.length])
                    : _live.hasGroup
                        ? tr('Vendo o grupo · {0} no mapa', [_live.members.length])
                        : tr('Ver e mostrar colegas no mapa')),
                onTap: () {
                  Navigator.pop(context);
                  _groupSheet();
                },
              ),
              ListTile(
                leading: const Icon(Icons.bug_report_outlined),
                title: Text(tr('Diagnóstico (último erro)')),
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
                      title: Text(tr('Último erro')),
                      content: SingleChildScrollView(
                          child: SelectableText(
                              tr('{0}\n\nPop-up da contagem:\n{1}', [err ?? tr('Nenhum erro registrado.'), log.isEmpty ? tr('(vazio)') : log.reversed.take(25).join('\n')]),
                              style: const TextStyle(fontSize: 12))),
                      actions: [
                        if (err != null)
                          TextButton(
                              onPressed: () async {
                                await p.remove('last_error');
                                _lastError = null;
                                if (d.mounted) Navigator.pop(d);
                              },
                              child: Text(tr('Apagar'))),
                        TextButton(
                            onPressed: () => Navigator.pop(d),
                            child: Text(tr('Fechar'))),
                      ],
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.system_update),
                title: Text(tr('Procurar atualização do app')),
                // 1.28.9: mostra a versão instalada (muda a cada atualização).
                subtitle: FutureBuilder<String>(
                  future: UpdateService.installed(),
                  builder: (_, s) =>
                      Text(tr('Versão instalada: {0}', [s.data ?? '…'])),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  UpdateService.manualCheck(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.public),
                title: Text(tr('País: {0}', [_rule.name])),
                subtitle: Text(_modeLabel(_rule.mode)),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                // Versão real do app instalado (antes fixa em "1.19.0").
                title: FutureBuilder<String>(
                  future: UpdateService.installed(),
                  builder: (_, s) => Text(tr('SpeedGuard {0}', [s.data ?? '']).trim()),
                ),
                subtitle: Text(tr('Dados de radares: © colaboradores do OpenStreetMap. Respeite sempre os limites de velocidade.')),
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
        return tr('Radares visíveis com distância exata');
      case RadarMode.dangerZone:
        return tr('Somente aviso de zona de perigo');
      case RadarMode.disabled:
        return tr('Alertas desligados por lei');
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
              // Marcando park: o toque leva o alfinete (centro) até o ponto.
              onTap: (_, p) {
                if (_placing != null) _map.move(p, _map.camera.zoom);
              },
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture && _follow) setState(() => _follow = false);
                if (hasGesture && _trackId != null && _trackCam) {
                  setState(() => _trackCam = false);
                }
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
              // Rota gravada aberta e a gravação em andamento (1.29.35).
              if (_shownTrack != null || (_rec.recording && _rec.points > 1))
                PolylineLayer(polylines: [
                  if (_shownTrack != null)
                    Polyline(
                        points: _shownTrack!,
                        strokeWidth: 6,
                        color: const Color(0xCC00E5FF)),
                  if (_rec.recording && _rec.points > 1)
                    Polyline(
                        points: [
                          for (final p in _rec.livePts) LatLng(p.$1, p.$2)
                        ],
                        strokeWidth: 4,
                        color: const Color(0xCCFF1744)),
                ]),
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
              // Parks adicionados pelos motoristas (1.29.30): "P+" verde no
              // mapa, até 50 km de você.
              if (pos != null && _parks.userParks.isNotEmpty)
                MarkerLayer(markers: [
                  for (final p in _parks.userParks)
                    if (Geolocator.distanceBetween(
                            pos.latitude, pos.longitude, p.lat, p.lon) <
                        50000)
                      Marker(
                        point: LatLng(p.lat, p.lon),
                        width: 34,
                        height: 34,
                        rotate: true,
                        // 1.29.34: toque abre o Google Maps até o park;
                        // toque longo abre as opções (dono: mudar/excluir).
                        child: GestureDetector(
                          onTap: () => _navigateTo(p),
                          onLongPress: () => _showUserPark(p),
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2E7D32),
                              borderRadius: BorderRadius.circular(7),
                              border:
                                  Border.all(color: Colors.white, width: 2),
                              boxShadow: const [
                                BoxShadow(color: Colors.black45, blurRadius: 4)
                              ],
                            ),
                            child: const Text('P+',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900)),
                          ),
                        ),
                      ),
                ]),
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
              // Localização em grupo (1.29.43): caminhãozinho de cada
              // colega e a gota com a foto em cima.
              if (_isTruck && _live.members.isNotEmpty)
                MarkerLayer(markers: [
                  for (final m in _live.members.values)
                    Marker(
                      point: LatLng(m.shown.$1, m.shown.$2),
                      width: 40,
                      height: 40,
                      child: GestureDetector(
                        onTap: () => _navigateTo(
                            Park('live', m.nick, m.lat, m.lon, 'parking', const {})),
                        onLongPress: () => _showMember(m),
                        child: Transform.rotate(
                          angle: m.heading * 3.14159265 / 180,
                          child: const VehicleMarker(
                              type: VehicleIcon.truck, size: 40),
                        ),
                      ),
                    ),
                ]),
              if (_isTruck &&
                  (_live.members.isNotEmpty ||
                      (_live.sharing && _live.hasGroup && pos != null)))
                MarkerLayer(markers: [
                  for (final m in _live.members.values)
                    Marker(
                      point: LatLng(m.shown.$1, m.shown.$2),
                      width: 110,
                      height: 100,
                      rotate: true,
                      alignment: Alignment.topCenter,
                      child: GestureDetector(
                        onTap: () => _navigateTo(
                            Park('live', m.nick, m.lat, m.lon, 'parking', const {})),
                        onLongPress: () => _showMember(m),
                        child: _livePin(
                            m.photo,
                            m.nick,
                            m.id == _trackId
                                ? const Color(0xFFFF9800)
                                : const Color(0xFF7E57C2),
                            label: true),
                      ),
                    ),
                  if (_live.sharing && _live.hasGroup && pos != null)
                    Marker(
                      point: LatLng(pos.latitude, pos.longitude),
                      width: 110,
                      height: 110,
                      rotate: true,
                      alignment: Alignment.topCenter,
                      // Sua gota: abre o Google Maps na sua posição.
                      child: GestureDetector(
                          onTap: () => _openMapAt(pos.latitude, pos.longitude),
                          child: _livePin(_live.photo, _live.nick, SG.pink,
                              label: true)),
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
                              label: '$roadSign',
                              size: 56,
                              // 1.29.37: foto do veículo escolhido (seta: só
                              // a placa).
                              plateImage: switch (_vehicle) {
                                VehicleIcon.truck => 'assets/caminhao_azul.png',
                                VehicleIcon.car => 'assets/carro.png',
                                VehicleIcon.moto => 'assets/moto.png',
                                _ => null,
                              }),
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
                                tr('Média {0}', [_section.average ?? '--']),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold)),
                          ),
                        // Contagem dos 30 s acima do limite.
                        if (overSecs != null)
                          // 1.29.27: contagem e aviso bem maiores.
                          Container(
                            margin: const EdgeInsets.only(top: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                                color: SG.red,
                                borderRadius: BorderRadius.circular(16),
                                border:
                                    Border.all(color: Colors.white, width: 2)),
                            child: Text(
                                overSecs >= 30
                                    ? tr('VELOCIDADE\nEXCEDIDA')
                                    : '${30 - overSecs} s',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: overSecs >= 30 ? 22 : 44,
                                    height: 1.05,
                                    fontWeight: FontWeight.w900)),
                          ),
                        // 1.29.36: as faixas da bolha (verdes = caminho
                        // livre; a cada aviso uma fica vermelha) com o
                        // limite e a distância do radar, no mapa.
                        // Só com radar à frente.
                        if (_mapView && _running && a.radar != null)
                          _radarBandsCard(a),
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

          // Marcando park no mapa (1.29.32): alfinete no centro + botões.
          if (_placing != null) ...[
            const IgnorePointer(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 44),
                  child: Icon(Icons.location_on,
                      size: 48,
                      color: Color(0xFF2E7D32),
                      shadows: [Shadow(color: Colors.black, blurRadius: 6)]),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Material(
                color: SG.card,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                        tr(_moving != null ? 'Novo lugar: toque no mapa ou arraste até o local exato do {0}' : 'Toque no mapa ou arraste até o local exato do {0}', [_placing!.$2.isNotEmpty ? _placing!.$2 : Park.userTypeLabel(_placing!.$1).$1]),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setState(() {
                            _placing = null;
                            _moving = null;
                          }),
                          child: Text(tr('Cancelar')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF2E7D32),
                              foregroundColor: Colors.white),
                          icon: const Icon(Icons.check),
                          label: Text(tr('Confirmar')),
                          onPressed: () {
                            final c = _map.camera.center;
                            _confirmPlace(c.latitude, c.longitude);
                          },
                        ),
                      ),
                    ]),
                  ]),
                ),
              ),
            ),
          ],

          // Rota gravada aberta no mapa / gravando (1.29.35).
          // Navegação pela rota gravada (1.29.38): painel no alto.
          if (_placing == null && _nav != null)
            Positioned(
              left: 12,
              right: 12,
              // Acima do card do park (quando ele aparece) e dos botões.
              bottom: _running && _showParks && _parksAhead.isNotEmpty
                  ? 166
                  : 72,
              child: _navPanel(),
            ),
          if (_placing == null &&
              (_nav == null && (_shownTrack != null || _rec.recording) ||
                  (_isTruck && _live.hasGroup)))
            Positioned(
              right: 12,
              top: MediaQuery.paddingOf(context).top + 64,
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                // 1.29.47: botão do grupo (lista dos colegas).
                if (_isTruck && _live.hasGroup) ...[
                  Badge(
                    label: Text(_unread.isNotEmpty
                        ? '💬${_unread.length}'
                        : '${_live.members.length}'),
                    backgroundColor: _unread.isNotEmpty ? SG.red : null,
                    isLabelVisible:
                        _live.members.isNotEmpty || _unread.isNotEmpty,
                    child: FloatingActionButton.small(
                      heroTag: 'grupo',
                      tooltip: tr('Grupo'),
                      backgroundColor: const Color(0xFF7E57C2),
                      foregroundColor: Colors.white,
                      onPressed: _groupList,
                      child: const Icon(Icons.groups),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                if (_nav == null && _rec.recording)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: SG.red,
                        borderRadius: BorderRadius.circular(20)),
                    child: Text(tr('● REC {0} km', [_rec.km.toStringAsFixed(1)]),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800)),
                  ),
                if (_nav == null && _shownTrack != null) ...[
                  const SizedBox(height: 6),
                  InputChip(
                    avatar: const Icon(Icons.route, size: 18),
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: Text(_shownTrackName ?? tr('Rota'),
                          overflow: TextOverflow.ellipsis),
                    ),
                    onDeleted: _hideTrack,
                  ),
                ],
              ]),
            ),

          // Aviso de pedágio (15 s), acima do card do park e dos botões.
          if (_tollBanner != null && _placing == null)
            Positioned(
              left: 12,
              right: 12,
              bottom: (_running && _showParks && _parksAhead.isNotEmpty
                      ? 166.0
                      : 72.0) +
                  (_nav != null ? 96 : 0),
              child: Material(
                color: const Color(0xFFF9A825),
                borderRadius: BorderRadius.circular(16),
                elevation: 6,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    Icon(_tollGantry ? Icons.contactless : Icons.toll,
                        color: Colors.black, size: 38),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(_tollBanner!,
                          style: const TextStyle(
                              color: Colors.black,
                              fontSize: 24,
                              fontWeight: FontWeight.w900)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.black),
                      onPressed: () => setState(() => _tollBanner = null),
                    ),
                  ]),
                ),
              ),
            ),

          // Parks à frente, logo acima dos botões.
          if (_placing == null &&
              _running &&
              _showParks &&
              _parksAhead.isNotEmpty)
            Positioned(left: 12, right: 12, bottom: 72, child: _parkCard()),

          // Colega sendo localizado (1.32.0): card com Google Maps.
          if (_placing == null &&
              _mapView &&
              _trackId != null &&
              _live.members[_trackId] != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: _running && _showParks && _parksAhead.isNotEmpty
                  ? 166
                  : 72,
              child: _locateCard(_live.members[_trackId]!),
            ),

          // Botões "Opções" (camadas do mapa) e "Navegar" (Google/Waze).
          if (_placing == null)
          Positioned(
            left: 12,
            bottom: 12,
            child: Row(children: [
              _pill(Icons.tune, tr('Opções'), _mapOptions),
              const SizedBox(width: 6),
              _pill(Icons.navigation, tr('Navegar'), _navigate),
              const SizedBox(width: 6),
              _parkButton(),
              // Adicionar park: só com caminhão escolhido (1.29.34).
              if (_isTruck) ...[
                const SizedBox(width: 6),
                _addParkButton(),
              ],
            ]),
          ),

          if (_rule.mode == RadarMode.disabled && _running)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                alignment: Alignment.center,
                padding: const EdgeInsets.all(32),
                child: Text(
                  tr('Alertas desligados em {0}\n(proibido por lei)', [_rule.name]),
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
                setState(() {
                  _follow = true;
                  _trackCam = false;
                });
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
                  tooltip: tr('Configurações'),
                  icon: Icons.settings,
                  onTap: _settings,
                ),
                const SizedBox(width: 10),
                _RoundAction(
                  tooltip: _mapView ? tr('Tela de alerta') : tr('Mapa'),
                  icon: _mapView ? Icons.keyboard_double_arrow_up : Icons.map,
                  onTap: _toggleView,
                ),
                const SizedBox(width: 10),
                // 1.29.35: rotas gravadas (vermelho enquanto grava).
                _RoundAction(
                  tooltip: tr('Rotas gravadas'),
                  icon: _rec.recording ? Icons.fiber_manual_record : Icons.route,
                  onTap: _tracksSheet,
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
                  tooltip: tr('Reportar radar aqui'),
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
            label: tr('no mundo'),
            tooltip: tr('Pessoas com o SpeedGuard conectado no mundo'),
          ),
          if (code != null && p.country != null) ...[
            const SizedBox(width: 8),
            _OnlineChip(
              icon: PresenceService.flag(code),
              count: p.country!,
              label: tr('no país'),
              tooltip: tr('Pessoas com o SpeedGuard conectado em {0}', [ruleFor(code).name]),
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
            Text(tr('O radar móvel ainda está aqui?'),
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
                    label: Text(tr('SIM')),
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
                    label: Text(tr('NÃO')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _radarBandsCard(AlertState a) {
    const green = Color(0xFF4ED636);
    final d = a.radar != null ? a.distance : null;
    final over = a.overLimit;
    final border = d == null
        ? SG.violet
        : over
            ? SG.red
            : SG.orange;
    return GestureDetector(
      onTap: a.radar != null ? () => _showRadar(a.radar!) : null,
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        width: 96,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [SG.palette.value.deepTop, SG.bg],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border, width: 3),
          boxShadow: SG.glow(border, 10),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          RadarBands(
              green: green,
              red: d == null ? 0 : RadarBands.redFor(d),
              size: 72),
          if (d != null) ...[
            const SizedBox(height: 6),
            if (a.radar!.maxSpeed != null)
              SpeedSign(label: '${a.radar!.maxSpeed}', size: 40),
            Text(
                d >= 1000
                    ? '${(d / 1000).toStringAsFixed(1)} km'
                    : '${d.round()} m',
                style: TextStyle(
                    color: over ? SG.red : SG.orange,
                    fontSize: 18,
                    fontWeight: FontWeight.w900)),
          ],
        ]),
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
      title = tr('ZONA DE PERIGO');
      subtitle = tr('Respeite o limite de velocidade');
    } else {
      final d = a.distance!;
      title = d >= 1000
          ? '${(d / 1000).toStringAsFixed(1)} km'
          : '${d.round()} m';
      subtitle = a.radar!.maxSpeed != null
          ? '${a.radar!.typeLabel} • ${tr('limite')} ${a.radar!.maxSpeed}'
          : a.radar!.typeLabel;
    }
    final accent = !hasAlert
        ? SG.violet
        : a.overLimit
            ? SG.red
            : SG.orange;
    // 1.29.28: tocar no card do radar abre as opções dele (ex.: "Este
    // radar é da outra pista").
    return GestureDetector(
      onTap: hasAlert ? () => _showRadar(a.radar!) : null,
      child: Container(
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
      message: tr('Atualizando radares'),
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
                  child: Text(running ? tr('PARAR') : tr('INICIAR'),
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

/// Uma mensagem na conversa com um colega (1.33.0: pode ser de voz).
class _ChatItem {
  final bool mine;
  final String text;
  final int at;
  final String? audio; // arquivo .m4a
  final int durMs;
  /// Minhas mensagens (1.37.0): id no Firebase e se já foi entregue
  /// (✓ enviada, ✓✓ entregue, como no WhatsApp).
  final String? docId;
  bool delivered = false;
  _ChatItem(this.mine, this.text, this.at,
      {this.audio, this.durMs = 0, this.docId});

  /// Guardado no celular por 7 dias (1.38.0).
  Map<String, dynamic> toJson() => {
        'mine': mine, 'text': text, 'at': at,
        if (audio != null) 'audio': audio, 'dur': durMs,
        if (docId != null) 'doc': docId, 'ok': delivered,
      };

  static _ChatItem fromJson(Map m) {
    var audio = m['audio'] as String?;
    // Áudio já apagado do celular (mais de 7 dias): fica só o texto.
    if (audio != null && !File(audio).existsSync()) audio = null;
    return _ChatItem(m['mine'] == true, m['text']?.toString() ?? '',
        m['at'] as int? ?? 0,
        audio: audio, durMs: m['dur'] as int? ?? 0, docId: m['doc'] as String?)
      ..delivered = m['ok'] == true;
  }
}
