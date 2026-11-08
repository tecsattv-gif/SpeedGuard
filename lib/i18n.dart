import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'i18n_data.dart';

/// Idiomas do app (1.30.0). O texto em português é a própria chave:
/// tr('Salvar') devolve "Save" em inglês, "Guardar" em espanhol etc.
/// Se faltar tradução, aparece o português.
const Map<String, String> kLangs = {
  'pt': 'Português',
  'en': 'English',
  'es': 'Español',
  'fr': 'Français',
};

/// Idioma em uso ('pt', 'en', 'es' ou 'fr').
String appLang = 'pt';

/// Escolha salva: '' = automático (idioma do celular).
String langChoice = '';

/// Avisa a tela principal para redesenhar tudo quando o idioma muda.
final langNotifier = ValueNotifier<String>('pt');

String _systemLang() {
  final c = ui.PlatformDispatcher.instance.locale.languageCode.toLowerCase();
  return kLangs.containsKey(c) ? c : 'en';
}

/// Lê o idioma salvo. Chamar no início de cada parte do app (tela principal,
/// painel flutuante e serviço em segundo plano rodam separados).
Future<void> loadLang() async {
  try {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    langChoice = p.getString('lang') ?? '';
  } catch (_) {}
  appLang = kLangs.containsKey(langChoice) ? langChoice : _systemLang();
  langNotifier.value = appLang;
}

/// Troca o idioma ('' = automático) e salva.
Future<void> setLang(String choice) async {
  langChoice = choice;
  appLang = kLangs.containsKey(choice) ? choice : _systemLang();
  final p = await SharedPreferences.getInstance();
  await p.setString('lang', choice);
  langNotifier.value = appLang;
}

/// Traduz [pt]. {0}, {1}… são trocados pelos valores de [args].
String tr(String pt, [List<Object?> args = const []]) {
  var s = appLang == 'pt' ? pt : (kTr[appLang]?[pt] ?? pt);
  for (var i = 0; i < args.length; i++) {
    s = s.replaceAll('{$i}', '${args[i] ?? ''}');
  }
  return s;
}

/// Voz do aviso falado no idioma escolhido.
String get ttsLang => const {
      'pt': 'pt-BR',
      'en': 'en-GB',
      'es': 'es-ES',
      'fr': 'fr-FR',
    }[appLang] ??
    'pt-BR';
