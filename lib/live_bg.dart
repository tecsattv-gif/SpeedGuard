import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'live_service.dart';

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
    await _notif.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    _ready = true;
  }

  static Future<void> notify(String nick, String cc) async {
    try {
      await _init();
      await _notif.show(
        _nid++,
        'Grupo SpeedGuard',
        '$nick está ${LiveService.inCountry(cc)}',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'grupo_fronteira',
            'Grupo: fronteiras',
            channelDescription:
                'Avisa quando um colega do grupo entra em outro país',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
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
      final p = await SharedPreferences.getInstance();
      if (p.getString('vehicle') != 'truck') return true;
      final live = LiveService();
      await live.load();
      if (!live.hasGroup) return true;
      if (!await live.refresh()) return true;
      for (final (nick, cc) in await live.borderEvents()) {
        await LiveBorder.notify(nick, cc);
      }
    } catch (_) {}
    return true;
  });
}
