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

  /// 1.42.3: versão do Android (API). 0 = não deu para saber.
  static int sdk = 0;

  /// Android 7 ou mais antigo (ex.: GPS Garmin, Android 6).
  static bool get oldAndroid => sdk > 0 && sdk < 26;

  /// Bipe do próprio Android, para quando o tocador de som falha.
  static Future<void> tone() async {
    try {
      await _ch.invokeMethod('tone');
    } catch (_) {}
  }

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
    try {
      sdk = await _ch.invokeMethod<int>('sdk') ?? 0;
    } catch (_) {
      sdk = 0;
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
