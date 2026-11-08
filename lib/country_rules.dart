import 'i18n.dart';

/// Como o app se comporta em cada país, conforme a lei local.
enum RadarMode {
  /// Mostra radares no mapa e avisa a distância exata.
  full,

  /// Não mostra a posição dos radares; só avisa "zona de perigo".
  dangerZone,

  /// Alertas desligados (app proibido no país).
  disabled,
}

class CountryRule {
  final String _name;
  final RadarMode mode;
  final String? _notice;
  String get name => tr(_name);
  String? get notice => _notice == null ? null : tr(_notice!);
  const CountryRule(this._name, this.mode, [this._notice]);
}

/// Regras especiais. Países fora desta lista usam o modo completo.
/// IMPORTANTE: revisar a legislação antes de publicar na loja.
const Map<String, CountryRule> specialRules = {
  'ch': CountryRule(
    'Suíça',
    RadarMode.disabled,
    'Na Suíça os avisos de radar são proibidos por lei. '
        'Os alertas ficam desligados enquanto você estiver no país.',
  ),
  'de': CountryRule(
    'Alemanha',
    RadarMode.full,
    'Na Alemanha o motorista não pode usar alertas de radar ao dirigir. '
        'Uso permitido apenas por passageiros.',
  ),
};

CountryRule ruleFor(String? countryCode) {
  if (countryCode == null) {
    return const CountryRule('Detectando país…', RadarMode.full);
  }
  return specialRules[countryCode.toLowerCase()] ??
      CountryRule(countryCode.toUpperCase(), RadarMode.full);
}
