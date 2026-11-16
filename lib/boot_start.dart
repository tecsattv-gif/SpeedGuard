import 'dart:typed_data';

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

  /// Android 6 ou mais antigo (ex.: GPS Garmin dēzlCam).
  /// 1.42.7: antes pegava também o Android 7 (API 24/25) e mudava o bipe e
  /// a voz dele sem querer; o Android 7 em diante fica como sempre foi.
  static bool get oldAndroid => sdk > 0 && sdk < 24;

  /// 1.42.4: fabricante, marca e modelo do aparelho (minúsculas).
  static String maker = '';

  /// 1.42.4: GPS Garmin (dēzlCam): pelo fabricante/modelo ou, se o
  /// aparelho não informar, pelo build para Android 6 (feito para ele).
  static bool get garmin =>
      maker.contains('garmin') ||
      maker.contains('dezl') ||
      (const bool.fromEnvironment('SG_LEGACY') && sdk < 24);

  /// Bipe do próprio Android, para quando o tocador de som falha.
  static Future<void> tone() async {
    try {
      await _ch.invokeMethod('tone');
    } catch (_) {}
  }

  /// 1.42.6 (Garmin): toca um bipe do app (arquivo WAV) direto pelo
  /// Android, no volume máximo e reforçado. false = não deu para tocar.
  static Future<bool> beep(Uint8List wav, double volume) async {
    try {
      return await _ch.invokeMethod<bool>(
              'beep', {'wav': wav, 'volume': volume}) ??
          false;
    } catch (_) {
      return false;
    }
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
    try {
      maker = (await _ch.invokeMethod<String>('maker') ?? '').toLowerCase();
    } catch (_) {
      maker = '';
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
