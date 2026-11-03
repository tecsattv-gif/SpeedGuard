/// Vigia a velocidade acima do limite e decide o que avisar.
///
/// Igual ao limitador do caminhão: passou do limite, o motorista tem
/// 30 segundos para voltar. Desde a 1.27.2 são só dois avisos sonoros:
/// ao passar ("Limite de 90 excedido.") e aos 20 s ("só tem 10
/// segundos"). Aos 30 s não fala mais nada: o velocímetro fica vermelho
/// com "VELOCIDADE EXCEDIDA" embaixo até voltar ao limite.
class SpeedWatch {
  DateTime? _since; // desde quando está acima
  int _step = 0; // 0 nada, 1 avisou ao passar, 2 aos 20 s, 3 aos 30 s

  /// Segundos acima do limite (null se está dentro do limite).
  int? get seconds =>
      _since == null ? null : DateTime.now().difference(_since!).inSeconds;

  /// Passou dos 30 s acima do limite.
  bool get exceeded => (seconds ?? 0) >= 30;

  void reset() {
    _since = null;
    _step = 0;
  }

  /// Chamado a cada leitura. Devolve o aviso de agora (ou null):
  /// 1 = passou do limite, 2 = aos 20 s, 3 = aos 30 s (só vibra, sem som).
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
      return SpeedEvent(1, 'Limite de $limit excedido.');
    }
    if (_step == 1 && s >= 20) {
      _step = 2;
      return SpeedEvent(
          2, 'Atenção. Você só tem 10 segundos para voltar aos $limit.');
    }
    if (_step == 2 && s >= 30) {
      _step = 3;
      return const SpeedEvent(3, null);
    }
    return null;
  }
}

class SpeedEvent {
  final int step;
  final String? text; // null = sem som
  const SpeedEvent(this.step, this.text);
}
