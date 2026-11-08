import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'theme.dart';
import 'i18n.dart';

/// Atualização do app pelo próprio app (1.27.0).
///
/// Cada build do GitHub publica o APK numa "Release" (v1.27.0 etc.). O app
/// pergunta ao GitHub qual é a última, compara com a versão instalada e, se
/// houver uma nova, pergunta ao usuário. Com "Atualizar", baixa o APK e abre
/// o instalador do Android, que pede a confirmação final. Como o APK sai
/// sempre com a mesma chave, instala por cima sem perder nada.
class UpdateInfo {
  final String version;
  final String apkUrl;
  final int size;
  const UpdateInfo(this.version, this.apkUrl, this.size);
}

class UpdateService {
  static const _api =
      'https://api.github.com/repos/tecsattv-gif/SpeedGuard/releases/latest';

  /// Ao voltar para o app (já aberto), procura de novo no máximo a cada
  /// 30 min — para não perguntar a cada troca com o Google Maps/Waze.
  static const resumeEvery = Duration(minutes: 30);
  static DateTime? _lastCheck;
  static bool _asking = false;

  /// Versão instalada (ex.: "1.27.0").
  static Future<String> installed() async =>
      (await PackageInfo.fromPlatform()).version;

  /// "1.26.10" > "1.26.9".
  static bool newer(String a, String b) {
    List<int> p(String v) => v
        .replaceAll(RegExp(r'^[vV]'), '')
        .split('+')
        .first
        .split('.')
        .map((x) => int.tryParse(x) ?? 0)
        .toList();
    final x = p(a), y = p(b);
    for (var i = 0; i < 3; i++) {
      final ai = i < x.length ? x[i] : 0, bi = i < y.length ? y[i] : 0;
      if (ai != bi) return ai > bi;
    }
    return false;
  }

  /// Última versão publicada, se for mais nova que a instalada.
  static Future<UpdateInfo?> check() async {
    final r = await http.get(Uri.parse(_api), headers: {
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'SpeedGuard (tecsattv-gif/SpeedGuard)',
    }).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) return null;
    final m = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
    final tag = m['tag_name']?.toString() ?? '';
    final assets = (m['assets'] as List?) ?? [];
    Map? apk;
    for (final a in assets) {
      if ((a as Map)['name'].toString().endsWith('.apk')) apk = a;
    }
    if (apk == null) return null;
    final version = tag.replaceAll(RegExp(r'^[vV]'), '');
    if (!newer(version, await installed())) return null;
    return UpdateInfo(version, apk['browser_download_url'].toString(),
        (apk['size'] as num?)?.toInt() ?? 0);
  }

  /// Verificação automática (1.29.13): toda vez que o app é aberto, se
  /// houver versão nova aparece a mensagem com o botão **Atualizar** (como
  /// nos outros apps). "Agora não" só adia: na próxima abertura pergunta de
  /// novo. [resumed] = voltou para o app que já estava aberto.
  static Future<void> autoCheck(BuildContext context,
      {bool resumed = false}) async {
    if (_asking) return;
    final now = DateTime.now();
    if (resumed &&
        _lastCheck != null &&
        now.difference(_lastCheck!) < resumeEvery) {
      return;
    }
    _lastCheck = now;
    UpdateInfo? info;
    try {
      info = await check();
    } catch (_) {
      return;
    }
    if (info == null || !context.mounted || _asking) return;
    _asking = true;
    try {
      await ask(context, info);
    } finally {
      _asking = false;
    }
  }

  /// Botão "Procurar atualização" em Configurações.
  static Future<void> manualCheck(BuildContext context) async {
    UpdateInfo? info;
    String? error;
    try {
      info = await check();
    } catch (_) {
      error = tr('Sem conexão para procurar atualização.');
    }
    if (!context.mounted) return;
    if (info == null) {
      final v = await installed();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error ?? tr('Você já está na versão mais nova ({0}).', [v]))));
      return;
    }
    await ask(context, info);
  }

  /// Pergunta ao usuário e, se ele aceitar, baixa e abre o instalador.
  static Future<bool?> ask(BuildContext context, UpdateInfo info) async {
    final current = await installed();
    if (!context.mounted) return null;
    final mb = info.size > 0 ? ' (${(info.size / 1048576).round()} MB)' : '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Nova versão do SpeedGuard')),
        content: Text(tr('A versão {0} está disponível (você tem a {1}).\n\nQuer baixar{2} e instalar agora? Suas configurações e radares reportados continuam.', [info.version, current, mb])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Agora não'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Atualizar'))),
        ],
      ),
    );
    if (ok == true && context.mounted) await _install(context, info);
    return ok;
  }

  static Future<void> _install(BuildContext context, UpdateInfo info) async {
    final progress = ValueNotifier<double?>(null);
    var cancelled = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Baixando {0}…', [info.version])),
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (_, v, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: v, color: SG.accent),
              const SizedBox(height: 10),
              Text(v == null ? tr('Conectando…') : '${(v * 100).round()}%'),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () {
                cancelled = true;
                Navigator.pop(ctx);
              },
              child: Text(tr('Cancelar'))),
        ],
      ),
    );
    final client = http.Client();
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/SpeedGuard-${info.version}.apk');
      final res = await client.send(http.Request('GET', Uri.parse(info.apkUrl)));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final total = res.contentLength ?? info.size;
      final sink = file.openWrite();
      var got = 0;
      await for (final chunk in res.stream) {
        if (cancelled) break;
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) progress.value = got / total;
      }
      await sink.close();
      if (cancelled) return;
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      // Abre o instalador do Android. Na 1ª vez ele pede para liberar
      // "Instalar apps desconhecidos" para o SpeedGuard.
      final r = await OpenFilex.open(file.path,
          type: 'application/vnd.android.package-archive');
      if (r.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr('Não foi possível abrir o instalador: {0}', [r.message]))));
      }
    } catch (_) {
      if (cancelled || !context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('Falha ao baixar a atualização. Tente de novo.'))));
    } finally {
      client.close();
    }
  }
}
