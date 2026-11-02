/// Fila única para o Overpass (OpenStreetMap).
///
/// O servidor aceita só 2 buscas ao mesmo tempo por aparelho. Radares,
/// limite da via, parks e parks da rota pediam juntos, o servidor recusava
/// (erro 429) e a lista de parks ficava vazia. Agora uma busca espera a
/// outra terminar.
class OverpassGate {
  static Future<void> _last = Future.value();

  static Future<T> run<T>(Future<T> Function() job) {
    final prev = _last;
    final done = prev.then((_) => job());
    _last = done.then((_) {}, onError: (_) {});
    return done;
  }
}
