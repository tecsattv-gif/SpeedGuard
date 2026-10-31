import 'dart:async';
import 'dart:convert';

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
import 'community_service.dart';
import 'country_rules.dart';
import 'firebase_config.dart';
import 'models.dart';
import 'overlay.dart';
import 'radar_service.dart';
import 'speed_picker.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SpeedGuardApp());
}

/// Ponto de entrada da bolha flutuante (roda separado do app).
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: OverlayBubble(),
  ));
}

class SpeedGuardApp extends StatelessWidget {
  const SpeedGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SpeedGuard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFE53935), brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const HomePage(),
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
  bool _voice = true;
  bool _discreet = false;
  bool _bubble = false;
  bool _overlayShown = false;
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

  List<Radar> get _allRadars => [..._service.all, ..._community.radars];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Respostas vindas da bolha flutuante.
    _overlaySub = FlutterOverlayWindow.overlayListener.listen((event) {
      try {
        final m = jsonDecode(event.toString()) as Map;
        if (m['answer'] is bool) _answer(m['answer'] as bool);
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
    _discreet = p.getBool('discreet') ?? false;
    _bubble = p.getBool('bubble') ?? false;
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
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (_running && _bubble) _showBubble();
    } else if (state == AppLifecycleState.resumed) {
      _closeBubble();
    }
  }

  Future<void> _showBubble() async {
    if (_overlayShown) return;
    try {
      if (!await FlutterOverlayWindow.isPermissionGranted()) return;
      await FlutterOverlayWindow.showOverlay(
        height: kPanelH,
        width: kPanelW,
        alignment: OverlayAlignment.topLeft,
        enableDrag: true,
        positionGravity: PositionGravity.none,
        overlayTitle: 'SpeedGuard',
        overlayContent: 'Bolha de radares ativa',
      );
      _overlayShown = true;
      _sendBubble();
    } catch (_) {}
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

  Future<void> _stop() async {
    await _sub?.cancel();
    _sub = null;
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
    if (st.speak != null) {
      HapticFeedback.heavyImpact();
      if (_voice) {
        _tts.speak(_discreet
            ? (st.speak!.startsWith('Reduza') ? 'Reduza.' : 'Radar.')
            : st.speak!);
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
      if (_voice) _tts.speak('O radar móvel ainda está aí? Responda na tela.');
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
      if (_voice) _tts.speak('Você entrou em ${_rule.name}.');
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
    setState(() => _loading = false);
    if (n == null) {
      _snack('Sem conexão para baixar radares. Usando os já salvos.');
    }
  }

  Future<void> _report() async {
    if (_pos == null) {
      _snack('Aguarde o sinal do GPS para reportar.');
      return;
    }
    final choice = await showDialog<SpeedChoice>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null) return;
    await _submitReport(mobile: choice.mobile, limit: choice.limit);
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
        if (_voice) _tts.speak('Sem sinal de GPS. Radar não salvo.');
      } else {
        _snack('Aguarde o sinal do GPS para reportar.');
      }
      return;
    }
    final dir = pos.speed > 2.5 ? pos.heading : null;
    var shared = false;
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
      if (_voice) _tts.speak('Radar reportado. Obrigado!');
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
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('Alertas por voz'),
                value: _voice,
                onChanged: (v) async {
                  final p = await SharedPreferences.getInstance();
                  await p.setBool('voice', v);
                  setSheet(() => _voice = v);
                  setState(() {});
                },
              ),
              SwitchListTile(
                title: const Text('Modo discreto'),
                subtitle: const Text('Só vibra e diz "Radar", sem detalhes'),
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
                title: Text('SpeedGuard 1.2'),
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
    final color = r.type == 'usuario'
        ? Colors.orange
        : (r.type == 'movel' || r.type == 'comunidade')
            ? Colors.purple
        : r.type == 'semaforo'
            ? Colors.amber.shade700
            : Colors.red;
    return GestureDetector(
      onTap: () => _showRadar(r),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 3),
        ),
        alignment: Alignment.center,
        child: r.maxSpeed != null
            ? Text('${r.maxSpeed}',
                style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 13))
            : Icon(Icons.photo_camera, size: 16, color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.tecsattv.speedguard',
              ),
              if (showRadars)
                MarkerLayer(
                  markers: [
                    for (final r in _allRadars)
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
                    width: 40,
                    height: 40,
                    child: Transform.rotate(
                      angle: (pos.heading < 0 ? 0 : pos.heading) *
                          3.14159265 /
                          180,
                      child: const Icon(Icons.navigation,
                          color: Colors.blueAccent, size: 36),
                    ),
                  ),
                ]),
              const SimpleAttributionWidget(
                source: Text('OpenStreetMap'),
              ),
            ],
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
                      Expanded(child: _alertCard(a)),
                    ],
                  ),
                  if (_ask != null) _askCard(),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: LinearProgressIndicator(),
                    ),
                ],
              ),
            ),
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
      floatingActionButton: _follow
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
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              IconButton.filledTonal(
                tooltip: 'Configurações',
                onPressed: _settings,
                icon: const Icon(Icons.settings),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: _running ? Colors.grey.shade700 : null,
                  ),
                  onPressed: _running ? _stop : _start,
                  icon: Icon(_running ? Icons.stop : Icons.play_arrow),
                  label: Text(_running ? 'PARAR' : 'INICIAR',
                      style: const TextStyle(fontSize: 18)),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Reportar radar aqui',
                onPressed: _report,
                icon: const Icon(Icons.add_location_alt),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _askCard() {
    return Card(
      color: Colors.purple.shade700,
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
                        backgroundColor: Colors.green.shade700,
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
                        backgroundColor: Colors.red.shade700,
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
    return Card(
      color: hasAlert
          ? (a.overLimit ? Colors.red.shade700 : Colors.orange.shade800)
          : Theme.of(context).colorScheme.surfaceContainerHigh,
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
        color: over ? Colors.red : Colors.black87,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24, width: 2),
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
          const Text('km/h',
              style: TextStyle(fontSize: 12, color: Colors.white70)),
        ],
      ),
    );
  }
}
