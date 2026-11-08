import 'dart:convert';
import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'live_service.dart';
import 'i18n.dart';

/// Aviso de fronteira do grupo (1.29.47).
///
/// Com o app aberto, minimizado ou monitorando, o aviso sai na hora (a cada
/// 30 s). Com o app fechado, o Android acorda este código de tempos em
/// tempos (a cada ~15–30 min, quando o sistema deixa) para conferir o grupo.
class LiveBorder {
  static const task = 'speedguard_grupo';
  static final _notif = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static int _nid = 7000;

  static Future<void> _init() async {
    if (_ready) return;
    await _notif.initialize(
        const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher')),
        onDidReceiveNotificationResponse: (r) => _tapped(r.payload));
    _ready = true;
  }

  /// 1.34.0: toque na notificação de mensagem abre o app direto na conversa
  /// com quem mandou. A tela principal registra aqui o que fazer.
  static void Function(String from, String nick)? onOpenChat;

  static void _tapped(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final m = jsonDecode(payload) as Map;
      final from = m['chat'];
      if (from is! String || from.isEmpty) return;
      onOpenChat?.call(from, '${m['nick'] ?? ''}');
    } catch (_) {}
  }

  /// Chamado quando o app abre: liga o toque nas notificações e, se o app
  /// foi aberto (estava fechado) pelo toque numa mensagem, abre a conversa.
  static Future<void> listenTaps(
      void Function(String from, String nick) open) async {
    onOpenChat = open;
    try {
      await _init();
      final d = await _notif.getNotificationAppLaunchDetails();
      if (d?.didNotificationLaunchApp == true) {
        _tapped(d!.notificationResponse?.payload);
      }
    } catch (_) {}
  }

  /// Uma notificação por colega: a mensagem nova substitui a anterior dele.
  static int _chatNid(String from) => 8000 + (from.hashCode & 0x3ff);

  /// Abriu a conversa: tira da barra a notificação daquele colega.
  static Future<void> clearChat(String from) async {
    try {
      await _init();
      await _notif.cancel(_chatNid(from));
    } catch (_) {}
  }

  static Future<void> notify(String nick, String cc) async {
    try {
      await _init();
      await _notif.show(
        _nid++,
        tr('Grupo SpeedGuard'),
        tr('{0} está {1}', [nick, LiveService.inCountry(cc)]),
        NotificationDetails(
          android: AndroidNotificationDetails(
            'grupo_fronteira',
            tr('Grupo: fronteiras'),
            channelDescription:
                tr('Avisa quando um colega do grupo entra em outro país'),
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (_) {}
  }

  /// Mensagem direta de um colega (1.32.0).
  /// 1.34.0: com [from] (id do aparelho de quem mandou), o toque na
  /// notificação — ou no botão Responder/Ouvir — abre a conversa com ele.
  static Future<void> notifyMsg(String nick, String text,
      {String? from, bool voice = false}) async {
    try {
      await _init();
      await _notif.show(
        from == null ? _nid++ : _chatNid(from),
        tr('Mensagem de {0}', [nick.isEmpty ? tr('Um colega') : nick]),
        text,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'grupo_mensagens',
            tr('Grupo: mensagens'),
            channelDescription:
                tr('Mensagens dos colegas do grupo'),
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.message,
            autoCancel: true,
            ticker: text,
            subText: from == null ? null : tr('Toque para abrir a conversa'),
            actions: from == null
                ? null
                : [
                    AndroidNotificationAction(
                        'abrir', voice ? tr('Ouvir') : tr('Responder'),
                        showsUserInterface: true),
                  ],
          ),
        ),
        payload: from == null ? null : jsonEncode({'chat': from, 'nick': nick}),
      );
    } catch (_) {}
  }

  /// Android 13+: pede permissão de notificação.
  static Future<void> askPermission() async {
    try {
      await _init();
      await _notif
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {}
  }

  /// Liga/desliga a conferência em segundo plano.
  static Future<void> schedule(bool on) async {
    try {
      await Workmanager().initialize(liveBgDispatcher);
      if (on) {
        await Workmanager().registerPeriodicTask(task, task,
            frequency: const Duration(minutes: 15),
            existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
            constraints: Constraints(networkType: NetworkType.connected));
      } else {
        await Workmanager().cancelByUniqueName(task);
      }
    } catch (_) {}
  }
}

@pragma('vm:entry-point')
void liveBgDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      DartPluginRegistrant.ensureInitialized();
      await loadLang();
      final p = await SharedPreferences.getInstance();
      if (p.getString('vehicle') != 'truck') return true;
      final live = LiveService();
      await live.load();
      if (!live.hasGroup) return true;
      final got = await live.inbox();
      for (final m in got) {
        await LiveBorder.notifyMsg(
            m.nick, m.isVoice ? tr('🎤 Mensagem de voz') : m.text,
            from: m.from, voice: m.isVoice);
      }
      // Guarda para aparecer na conversa quando o app abrir (1.33.0).
      await LiveService.savePending(got);
      if (!await live.refresh()) return true;
      for (final (nick, cc) in await live.borderEvents()) {
        await LiveBorder.notify(nick, cc);
      }
    } catch (_) {}
    return true;
  });
}
