import 'i18n.dart';
/// Vigia a velocidade acima do limite e decide o que avisar.
///
/// Igual ao limitador do caminhão: passou do limite, o motorista tem
/// 30 segundos para voltar. Desde a 1.28.7: ao passar só o aviso na tela
/// (velocímetro vermelho e contagem), aos 20 s "Atenção." e aos 30 s
/// "Velocidade excedida. Tempo excedido." (uma vez); o velocímetro fica
/// vermelho com "VELOCIDADE EXCEDIDA" até voltar ao limite.
class SpeedWatch {
  DateTime? _since; // desde quando está acima
  int _step = 0; // 0 nada, 1 avisou ao passar, 2 faltando 10 s, 3 no fim

  /// Duração da contagem em segundos (1.43.0: escolhida nas Configurações,
  /// de 30 a 60; o padrão do app é 30).
  int total = 30;

  /// Segundos acima do limite (null se está dentro do limite).
  int? get seconds =>
      _since == null ? null : DateTime.now().difference(_since!).inSeconds;

  /// Acabou a contagem acima do limite.
  bool get exceeded => (seconds ?? 0) >= total;

  void reset() {
    _since = null;
    _step = 0;
  }

  /// Chamado a cada leitura. Devolve o aviso de agora (ou null):
  /// 1 = passou do limite (sem som), 2 = aos 20 s, 3 = aos 30 s.
  SpeedEvent? update({required int speed, required int? limit}) {
    if (limit == null || speed <= limit) {
      reset();
      return null;
    }
    final now = DateTime.now();
    _since ??= now;
    final s = now.difference(_since!).inSeconds;
    // Espera 2 s acima antes do 1º aviso (evita aviso por oscilação do GPS).
    if (_step == 0 && s >= 2) {
      _step = 1;
      // 1.28.7: ao passar não fala nada (só o aviso na tela).
      return const SpeedEvent(1, null);
    }
    if (_step == 1 && s >= total - 10) {
      _step = 2;
      // 1.28.6: aos 20 s fala só "Atenção." (antes a frase dos 10 segundos).
      return SpeedEvent(2, tr('Atenção.'));
    }
    if (_step == 2 && s >= total) {
      _step = 3;
      return SpeedEvent(3, tr('Velocidade excedida. Tempo excedido.'));
    }
    return null;
  }
}

class SpeedEvent {
  final int step;
  final String? text; // null = sem som
  const SpeedEvent(this.step, this.text);
}
