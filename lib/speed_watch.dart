/// Vigia a velocidade acima do limite e decide o que falar.
///
/// Igual ao limitador do caminhão: passou do limite, o motorista tem
/// 30 segundos para voltar. Aviso ao passar, aos 20 s ("só tem 10
/// segundos") e aos 30 s ("velocidade excedida"), que se repete a cada
/// 30 s enquanto continuar acima.
class SpeedWatch {
  DateTime? _since; // desde quando está acima
  int _step = 0; // 0 nada, 1 avisou ao passar, 2 aos 20 s, 3+ aos 30 s…

  /// Segundos acima do limite (null se está dentro do limite).
  int? get seconds =>
      _since == null ? null : DateTime.now().difference(_since!).inSeconds;

  void reset() {
    _since = null;
    _step = 0;
  }

  /// Chamado a cada leitura. Devolve a frase a falar agora (ou null).
  String? update({required int speed, required int? limit}) {
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
      return 'Limite de $limit excedido.';
    }
    if (_step == 1 && s >= 20) {
      _step = 2;
      return 'Atenção. Você só tem 10 segundos para voltar aos $limit.';
    }
    if (_step >= 2 && s >= 30 + (_step - 2) * 30) {
      _step++;
      return 'Velocidade excedida. Volte para os $limit.';
    }
    return null;
  }
}
