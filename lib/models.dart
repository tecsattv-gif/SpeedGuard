/// Uma via perto de um radar/park, gravada na base própria (1.29.0,
/// tools/road_match.py): tipo, número, nome, mão única e rumo do trecho.
class RoadRef {
  final double d; // distância do ponto até a via (m)
  final String hw; // highway=*
  final String ref;
  final String name;
  final int ow; // 1 = mão única no sentido dos pontos, -1 = ao contrário, 0 = dupla
  final double b; // rumo do trecho (sentido dos pontos)
  /// Lado da via em que o ponto fica (1.29.11): 1 = à direita do sentido dos
  /// pontos, -1 = à esquerda, 0 = em cima da via / não se sabe.
  final int s;
  const RoadRef(this.d, this.hw, this.ref, this.name, this.ow, this.b,
      [this.s = 0]);

  static List<RoadRef> list(dynamic raw) {
    if (raw is! List) return const [];
    final out = <RoadRef>[];
    for (final e in raw) {
      if (e is! Map) continue;
      out.add(RoadRef(
        (e['d'] as num?)?.toDouble() ?? 0,
        e['h']?.toString() ?? '',
        e['r']?.toString() ?? '',
        e['n']?.toString() ?? '',
        (e['o'] as num?)?.toInt() ?? 0,
        (e['b'] as num?)?.toDouble() ?? 0,
        (e['s'] as num?)?.toInt() ?? 0,
      ));
    }
    return out;
  }

  Map<String, dynamic> toJson() =>
      {'d': d, 'h': hw, 'r': ref, 'n': name, 'o': ow, 'b': b, if (s != 0) 's': s};

  bool get isLink => hw.endsWith('_link');

  /// Sentido do trânsito (mão única) ou null (mão dupla).
  double? get dir => ow == 0 ? null : (ow == 1 ? b : (b + 180) % 360);

  /// Números da via (ref) ou, sem número, o nome — normalizados.
  Set<String> get ids {
    String norm(String v) => v.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    final out = <String>{
      for (final r in ref.split(';'))
        if (r.trim().isNotEmpty) 'R:${norm(r)}'
    };
    if (out.isEmpty && name.trim().isNotEmpty) out.add('N:${norm(name)}');
    return out;
  }
}

/// Um radar (fixo, de semáforo, móvel ou reportado pelo usuário).
class Radar {
  final String id;
  final double lat;
  final double lon;
  final int? maxSpeed; // km/h
  final String type; // fixo, semaforo, movel, usuario, comunidade,
  // fila, acidente, obra, perigo, policia (avisos: somem após 6 h)
  final double? direction; // graus (0 = norte), se conhecido
  final int? checkAfter; // ms; após essa data, pergunta se o radar móvel ainda está lá
  /// Vias perto do radar (base própria, 1.29.0); vazio = não se sabe.
  final List<RoadRef> roads;
  /// Velocidade média: 'start' (início do trecho), 'end' (fim) ou null.
  final String? section;
  /// Sentido do trânsito que o radar fiscaliza (graus), quando a base sabe
  /// com certeza (relação de fiscalização ou direction=forward/backward).
  final double? travel;
  /// Radar marcado para os dois sentidos (direction=both).
  final bool both;

  const Radar({
    required this.id,
    required this.lat,
    required this.lon,
    this.maxSpeed,
    this.type = 'fixo',
    this.direction,
    this.checkAfter,
    this.roads = const [],
    this.section,
    this.travel,
    this.both = false,
  });

  bool get isSectionEnd => type == 'media' && section == 'end';

  /// Aviso de trânsito (fila, acidente, obra, perigo, polícia), não radar.
  bool get isEvent => const {'fila', 'acidente', 'obra', 'perigo', 'policia'}.contains(type);

  String get typeLabel {
    switch (type) {
      case 'semaforo':
        return 'Radar de semáforo';
      case 'movel':
        return 'Radar móvel';
      case 'media':
        return section == 'end'
            ? 'Fim da velocidade média'
            : 'Radar de velocidade média';
      case 'usuario':
        return 'Reportado por você';
      case 'comunidade':
        return 'Radar reportado';
      case 'fila':
        return 'Fila';
      case 'acidente':
        return 'Acidente';
      case 'obra':
        return 'Obras';
      case 'perigo':
        return 'Perigo';
      case 'policia':
        return 'Polícia';
      default:
        return 'Radar fixo';
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'lat': lat,
        'lon': lon,
        'maxSpeed': maxSpeed,
        'type': type,
        'direction': direction,
        'checkAfter': checkAfter,
        if (roads.isNotEmpty) 'rd': [for (final r in roads) r.toJson()],
        if (section != null) 'section': section,
        if (travel != null) 'travel': travel,
        if (both) 'both': true,
      };

  factory Radar.fromJson(Map<String, dynamic> j) => Radar(
        id: j['id'] as String,
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        maxSpeed: j['maxSpeed'] as int?,
        type: (j['type'] as String?) ?? 'fixo',
        direction: (j['direction'] as num?)?.toDouble(),
        checkAfter: j['checkAfter'] as int?,
        roads: RoadRef.list(j['rd']),
        section: j['section'] as String?,
        travel: (j['travel'] as num?)?.toDouble(),
        both: j['both'] == true,
      );

  /// Converte um nó do OpenStreetMap (Overpass) em Radar.
  static Radar? fromOsm(Map<String, dynamic> el) {
    final lat = (el['lat'] as num?)?.toDouble();
    final lon = (el['lon'] as num?)?.toDouble();
    if (lat == null || lon == null) return null;
    final tags = (el['tags'] as Map?)?.cast<String, dynamic>() ?? {};
    // Radar de semáforo: marcado de vários jeitos no OpenStreetMap.
    final kinds = [
      tags['enforcement'],
      tags['speed_camera'],
      tags['camera:type'],
      tags['surveillance:type'],
    ].map((v) => v?.toString().toLowerCase() ?? '').join(';');
    String type = 'fixo';
    if (kinds.contains('traffic_signals') || kinds.contains('red_light')) {
      type = 'semaforo';
    }
    if (kinds.contains('average_speed')) type = 'media';
    if (tags['mobile'] == 'yes') type = 'movel';
    return Radar(
      id: 'osm_${el['id']}',
      lat: lat,
      lon: lon,
      maxSpeed: _parseSpeed(tags['maxspeed']?.toString()),
      type: type,
      direction: _parseDirection(tags['direction']?.toString() ??
          tags['camera:direction']?.toString()),
      roads: RoadRef.list(el['rd']),
      section: tags['section']?.toString(),
      travel: (el['td'] as num?)?.toDouble(),
      both: RegExp(r'both|forward;backward|backward;forward')
          .hasMatch(tags['direction']?.toString().toLowerCase() ?? ''),
    );
  }

  static int? _parseSpeed(String? v) {
    if (v == null) return null;
    final m = RegExp(r'(\d+)').firstMatch(v);
    if (m == null) return null;
    final n = int.parse(m.group(1)!);
    // "mph" -> converte para km/h
    return v.contains('mph') ? (n * 1.609).round() : n;
  }

  static double? _parseDirection(String? v) {
    if (v == null) return null;
    final first = v.split(';').first.trim();
    final n = double.tryParse(first);
    if (n != null) return n % 360;
    const cardinal = {
      'N': 0.0, 'NE': 45.0, 'E': 90.0, 'SE': 135.0,
      'S': 180.0, 'SW': 225.0, 'W': 270.0, 'NW': 315.0,
    };
    return cardinal[first.toUpperCase()];
  }
}
