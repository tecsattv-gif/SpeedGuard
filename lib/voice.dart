import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

/// Voz dos avisos (1.42.1).
///
/// Alguns aparelhos (ex.: GPS Garmin dēzlCam, Android 6) não têm motor de
/// voz do Android, ou têm um sem o idioma escolhido: o aviso falado ficava
/// mudo. Aqui o app confere se existe voz para o idioma; se não existe,
/// [ok] fica falso e cada aviso falado vira um bipe ([onNoVoice]), para o
/// aviso nunca passar em silêncio.
class Voice {
  final _tts = FlutterTts();

  /// Existe voz instalada capaz de falar o idioma do app.
  bool ok = true;

  /// Por que não fala: 'engine' (sem motor de voz) ou 'lang' (sem o idioma).
  String? reason;

  /// Chamado no lugar da fala quando não há voz (número do bipe).
  void Function(int beep)? onNoVoice;

  static const _wait = Duration(seconds: 4);

  /// 1.42.3: confere se cada fala começa mesmo. Em Android antigo (ex.:
  /// Garmin) o aparelho pode dizer que tem voz e ficar mudo: se a fala não
  /// começa em 3 s, toca o bipe e passa a usar só bipes.
  bool verify = false;
  bool _silent = false; // conferido: a voz não sai neste aparelho

  /// 1.42.5 (Garmin): nunca tenta falar; todo aviso sai em bipe. No Garmin
  /// o aparelho às vezes respondia que tinha voz (ao voltar para o app, a
  /// conferência refeita religava a fala) e o aviso de radar ficava mudo.
  bool _beepOnly = false;
  bool get beepOnly => _beepOnly;
  set beepOnly(bool v) {
    _beepOnly = v;
    if (v) {
      ok = false;
      reason = 'engine';
    }
  }
  int _startedSeq = 0, _seq = 0;

  Voice() {
    try {
      _tts.setStartHandler(() => _startedSeq = _seq);
    } catch (_) {}
  }

  /// Mesma língua em outros países, para quando a voz exata não existe.
  static const _alt = {
    'pt': ['pt-BR', 'pt-PT'],
    'en': ['en-GB', 'en-US'],
    'es': ['es-ES', 'es-US', 'es-MX'],
    'fr': ['fr-FR', 'fr-CA'],
  };

  /// Escolhe a voz do idioma e confere se o aparelho consegue falar.
  Future<void> setLanguage(String lang) async {
    final base = lang.split('-').first;
    final tries = <String>{lang, ...?_alt[base]};
    if (_silent || _beepOnly) return;
    try {
      final engines = await _tts.getEngines.timeout(_wait);
      if (engines is List && engines.isEmpty) {
        ok = false;
        reason = 'engine';
        return;
      }
      for (final l in tries) {
        final has = await _tts.isLanguageAvailable(l).timeout(_wait);
        if (has == true) {
          await _tts.setLanguage(l).timeout(_wait);
          ok = true;
          reason = null;
          return;
        }
      }
      ok = false;
      reason = 'lang';
    } on TimeoutException {
      // O motor de voz não respondeu: trata como sem voz.
      ok = false;
      reason = 'engine';
    } catch (_) {
      // Não deu para conferir: segue como antes (tenta falar).
      ok = true;
      reason = null;
      try {
        await _tts.setLanguage(lang).timeout(_wait);
      } catch (_) {}
    }
  }

  Future<void> setSpeechRate(double r) => _safe(() => _tts.setSpeechRate(r));
  Future<void> setVolume(double v) => _safe(() => _tts.setVolume(v));
  Future<void> awaitSpeakCompletion(bool b) =>
      _safe(() => _tts.awaitSpeakCompletion(b));
  Future<void> stop() => _safe(() => _tts.stop());

  /// Fala o aviso; sem voz no aparelho toca o bipe [beep] (0 = nada).
  Future<void> speak(String text, {int beep = 1}) async {
    if (!ok || _beepOnly) {
      if (beep > 0) onNoVoice?.call(beep);
      return;
    }
    final seq = ++_seq;
    await _safe(() => _tts.speak(text));
    if (!verify) return;
    Timer(const Duration(seconds: 3), () {
      // Outra fala veio depois, ou esta começou: tudo certo.
      if (seq != _seq || _startedSeq == seq) return;
      _silent = true;
      ok = false;
      reason = 'engine';
      if (beep > 0) onNoVoice?.call(beep);
    });
  }

  Future<void> _safe(Future<dynamic> Function() f) async {
    try {
      await f().timeout(_wait);
    } catch (_) {}
  }
}
