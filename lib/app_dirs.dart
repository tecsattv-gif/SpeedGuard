import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 1.45.1: pastas do app pedidas direto ao Android (MainActivity), sem o
/// plugin path_provider. No TacoGuard (19/11/2026) uma versão nova do
/// path_provider_android, baixada sozinha na compilação, passou a falhar
/// ("ClassNotFoundException: Landroid/content/Context;"): o app abria sem
/// os dados e não gravava nada. Aqui é prevenção.
///
/// As pastas são as mesmas de antes (app_flutter, files e cache). Fora da
/// tela principal (tarefa em segundo plano, bolha) o canal não existe:
/// usa os caminhos guardados da última vez.
class AppDirs {
  static const _ch = MethodChannel('speedguard/boot');
  static const _pkg = '/data/user/0/com.tecsattv.speedguard';
  static String? _docs, _support, _temp;

  static Future<void> _init() async {
    if (_docs != null && _support != null && _temp != null) return;
    try {
      final m = await _ch.invokeMapMethod<String, String>('dirs');
      _docs = m?['docs'];
      _support = m?['support'];
      _temp = m?['temp'];
      if (_docs != null && _support != null && _temp != null) {
        final p = await SharedPreferences.getInstance();
        await p.setString('dir_docs', _docs!);
        await p.setString('dir_support', _support!);
        await p.setString('dir_temp', _temp!);
        return;
      }
    } catch (_) {}
    try {
      final p = await SharedPreferences.getInstance();
      _docs ??= p.getString('dir_docs');
      _support ??= p.getString('dir_support');
      _temp ??= p.getString('dir_temp');
    } catch (_) {}
    _docs ??= '$_pkg/app_flutter';
    _support ??= '$_pkg/files';
    _temp ??= '$_pkg/cache';
  }

  static Future<Directory> _dir(String path) async {
    final d = Directory(path);
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// Igual ao getApplicationDocumentsDirectory() de antes.
  static Future<Directory> docs() async {
    await _init();
    return _dir(_docs!);
  }

  /// Igual ao getApplicationSupportDirectory() de antes.
  static Future<Directory> support() async {
    await _init();
    return _dir(_support!);
  }

  /// Igual ao getTemporaryDirectory() de antes.
  static Future<Directory> temp() async {
    await _init();
    return _dir(_temp!);
  }
}
