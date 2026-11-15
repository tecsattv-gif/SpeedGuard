import 'package:flutter/services.dart';

/// 1.42.0: "Iniciar com o Android (minimizado)".
/// O BootReceiver (Android) abre o app quando o aparelho liga; aqui o Dart
/// descobre isso e pede para minimizar depois de ligar o monitoramento.
class BootStart {
  static const _ch = MethodChannel('speedguard/boot');

  /// true quando esta abertura do app veio de ligar o aparelho.
  static bool fromBoot = false;

  /// Chamar uma vez no main(), antes do runApp.
  static Future<void> init() async {
    try {
      fromBoot = await _ch.invokeMethod<bool>('consumeBoot') ?? false;
    } catch (_) {
      fromBoot = false;
    }
  }

  /// Minimiza o app (como apertar o botão Início).
  static Future<void> minimize() async {
    try {
      await _ch.invokeMethod('moveToBack');
    } catch (_) {}
  }
}
