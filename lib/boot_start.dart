import 'package:flutter/services.dart';

/// 1.42.0: "Iniciar com o Android (minimizado)".
/// O BootReceiver (Android) abre o app quando o aparelho liga; aqui o Dart
/// descobre isso e pede para minimizar depois de ligar o monitoramento.
class BootStart {
  static const _ch = MethodChannel('speedguard/boot');

  /// true quando esta abertura do app veio de ligar o aparelho.
  static bool fromBoot = false;

  /// 1.42.1: o app abriu nos primeiros minutos depois de o aparelho ligar
  /// (ex.: o Garmin reabre sozinho o último app, sem passar pelo BootReceiver).
  static bool nearBoot = false;

  /// 1.42.1: o aviso de "aparelho ligou" chegou com o app já aberto.
  static void Function()? onBoot;

  /// Chamar uma vez no main(), antes do runApp.
  static Future<void> init() async {
    try {
      fromBoot = await _ch.invokeMethod<bool>('consumeBoot') ?? false;
    } catch (_) {
      fromBoot = false;
    }
    try {
      final secs = await _ch.invokeMethod<int>('sinceBoot');
      nearBoot = secs != null && secs < 180;
    } catch (_) {
      nearBoot = false;
    }
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'boot') onBoot?.call();
    });
  }

  /// Minimiza o app (como apertar o botão Início).
  static Future<void> minimize() async {
    try {
      await _ch.invokeMethod('moveToBack');
    } catch (_) {}
  }
}
