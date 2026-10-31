/// Um radar (fixo, de semáforo, móvel ou reportado pelo usuário).
class Radar {
  final String id;
  final double lat;
  final double lon;
  final int? maxSpeed; // km/h
  final String type; // fixo, semaforo, movel, usuario
  final double? direction; // graus (0 = norte), se conhecido
  final int? expiresAt; // ms; radares móveis da comunidade expiram

  const Radar({
    required this.id,
    required this.lat,
    required this.lon,
    this.maxSpeed,
    this.type = 'fixo',
    this.direction,
    this.expiresAt,
  });

  String get typeLabel {
    switch (type) {
      case 'semaforo':
        return 'Radar de semáforo';
      case 'movel':
        return 'Radar móvel';
      case 'usuario':
        return 'Reportado por você';
      case 'comunidade':
        return 'Radar reportado';
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
        'expiresAt': expiresAt,
      };

  factory Radar.fromJson(Map<String, dynamic> j) => Radar(
        id: j['id'] as String,
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        maxSpeed: j['maxSpeed'] as int?,
        type: (j['type'] as String?) ?? 'fixo',
        direction: (j['direction'] as num?)?.toDouble(),
        expiresAt: j['expiresAt'] as int?,
      );

  /// Converte um nó do OpenStreetMap (Overpass) em Radar.
  static Radar? fromOsm(Map<String, dynamic> el) {
    final lat = (el['lat'] as num?)?.toDouble();
    final lon = (el['lon'] as num?)?.toDouble();
    if (lat == null || lon == null) return null;
    final tags = (el['tags'] as Map?)?.cast<String, dynamic>() ?? {};
    final enforcement = tags['enforcement']?.toString();
    String type = 'fixo';
    if (enforcement == 'traffic_signals') type = 'semaforo';
    if (tags['mobile'] == 'yes') type = 'movel';
    return Radar(
      id: 'osm_${el['id']}',
      lat: lat,
      lon: lon,
      maxSpeed: _parseSpeed(tags['maxspeed']?.toString()),
      type: type,
      direction: _parseDirection(tags['direction']?.toString() ??
          tags['camera:direction']?.toString()),
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
