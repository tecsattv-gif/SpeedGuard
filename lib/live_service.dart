import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_config.dart';

/// Um motorista do grupo no mapa.
class LiveMember {
  final String id;
  String nick;
  Uint8List? photo;
  int photoAt = -1; // versão da foto baixada
  double lat, lon, heading, kmh;
  int updatedAt;
  // Para andar suave no mapa entre uma posição e outra.
  double fromLat, fromLon;
  int receivedAt;
  LiveMember(this.id, this.nick, this.photo, this.lat, this.lon, this.heading,
      this.kmh, this.updatedAt)
      : fromLat = lat,
        fromLon = lon,
        receivedAt = DateTime.now().millisecondsSinceEpoch;

  /// Posição desenhada agora (desliza da anterior até a nova em 30 s).
  (double, double) get shown {
    final t = ((DateTime.now().millisecondsSinceEpoch - receivedAt) /
            LiveService.every.inMilliseconds)
        .clamp(0.0, 1.0);
    return (fromLat + (lat - fromLat) * t, fromLon + (lon - fromLon) * t);
  }
}

/// Localização em grupo (1.29.43): quem liga "Compartilhar" manda a posição
/// a cada 30 s para a coleção `live` do Firebase; quem tem o mesmo código
/// de grupo vê os outros no mapa. O código vai como "impressão digital"
/// (hash), nunca o texto. Some do mapa 5 min sem sinal ou ao desligar.
class LiveService {
  static const every = Duration(seconds: 30);
  static const staleMs = 5 * 60 * 1000;

  bool sharing = false;
  String nick = '';
  String group = ''; // código digitado
  Uint8List? photo;
  final Map<String, LiveMember> members = {};
  String? _id;
  bool rulesMissing = false;

  String get _base =>
      'https://firestore.googleapis.com/v1/projects/$firebaseProjectId'
      '/databases/(default)/documents';

  /// Hash do código do grupo (FNV-1a 64 bits, em hexadecimal).
  static String groupKey(String code) {
    final s = code.trim().toLowerCase();
    var h = BigInt.parse('cbf29ce484222325', radix: 16);
    final prime = BigInt.parse('100000001b3', radix: 16);
    final mask = (BigInt.one << 64) - BigInt.one;
    for (final b in utf8.encode(s)) {
      h = ((h ^ BigInt.from(b)) * prime) & mask;
    }
    return 'g${h.toRadixString(16).padLeft(16, '0')}';
  }

  bool get hasGroup => group.trim().length >= 4;

  Future<String> _deviceId() async {
    if (_id != null) return _id!;
    final p = await SharedPreferences.getInstance();
    var id = p.getString('deviceId');
    if (id == null) {
      const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
      final r = math.Random.secure();
      id = List.generate(20, (_) => chars[r.nextInt(chars.length)]).join();
      await p.setString('deviceId', id);
    }
    return _id = id;
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    sharing = p.getBool('live_sharing') ?? false;
    nick = p.getString('live_nick') ?? '';
    group = p.getString('live_group') ?? '';
    final ph = p.getString('live_photo');
    photo = ph == null ? null : base64Decode(ph);
    await _deviceId();
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('live_sharing', sharing);
    await p.setString('live_nick', nick);
    await p.setString('live_group', group);
    if (photo != null) {
      await p.setString('live_photo', base64Encode(photo!));
    } else {
      await p.remove('live_photo');
    }
  }

  /// Foto reduzida para 80×80 (PNG pequeno) para ir no Firebase.
  static Future<Uint8List?> shrink(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final f = await codec.getNextFrame();
      final src = f.image;
      final side = math.min(src.width, src.height).toDouble();
      final rec = ui.PictureRecorder();
      final c = ui.Canvas(rec);
      const out = 80.0;
      c.drawImageRect(
          src,
          ui.Rect.fromLTWH((src.width - side) / 2, (src.height - side) / 2,
              side, side),
          const ui.Rect.fromLTWH(0, 0, out, out),
          ui.Paint()..filterQuality = ui.FilterQuality.medium);
      final img = await rec.endRecording().toImage(out.toInt(), out.toInt());
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// Manda a sua posição (e a foto/apelido, quando [withPhoto]).
  Future<bool> push(double lat, double lon, double heading, double kmh,
      {bool withPhoto = false}) async {
    if (!communityEnabled || !sharing || !hasGroup) return false;
    final id = await _deviceId();
    final fields = <String, dynamic>{
      'group': {'stringValue': groupKey(group)},
      'nick': {
        'stringValue': nick.length > 30 ? nick.substring(0, 30) : nick
      },
      'lat': {'doubleValue': lat},
      'lon': {'doubleValue': lon},
      'heading': {'doubleValue': heading < 0 ? 0 : heading},
      'speed': {'doubleValue': kmh},
      'updatedAt': {
        'integerValue': '${DateTime.now().millisecondsSinceEpoch}'
      },
      if (withPhoto) ...{
        'photo': {'stringValue': photo == null ? '' : base64Encode(photo!)},
        'photoAt': {
          'integerValue': '${DateTime.now().millisecondsSinceEpoch}'
        },
      },
    };
    final mask = fields.keys.map((k) => 'updateMask.fieldPaths=$k').join('&');
    try {
      final r = await http
          .patch(Uri.parse('$_base/live/$id?$mask&key=$firebaseApiKey'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'fields': fields}))
          .timeout(const Duration(seconds: 20));
      rulesMissing = r.statusCode == 403;
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Parou de compartilhar: some do mapa dos outros na hora.
  Future<void> remove() async {
    if (!communityEnabled) return;
    final id = await _deviceId();
    try {
      await http
          .delete(Uri.parse('$_base/live/$id?key=$firebaseApiKey'))
          .timeout(const Duration(seconds: 15));
    } catch (_) {}
  }

  /// Baixa só a foto de um motorista (quando ela muda).
  Future<void> _photo(LiveMember m) async {
    try {
      final r = await http
          .get(Uri.parse('$_base/live/${m.id}?mask.fieldPaths=photo'
              '&key=$firebaseApiKey'))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return;
      final ph = ((jsonDecode(r.body) as Map)['fields']?['photo']
                  as Map?)?['stringValue']
              ?.toString() ??
          '';
      m.photo = ph.isEmpty ? null : base64Decode(ph);
      onPhoto?.call();
    } catch (_) {}
  }

  /// Chamado quando chega a foto de alguém (para redesenhar o mapa).
  void Function()? onPhoto;

  /// Baixa os motoristas do seu grupo (menos você).
  Future<bool> refresh() async {
    if (!communityEnabled || !hasGroup) {
      members.clear();
      return false;
    }
    final id = await _deviceId();
    final body = {
      'structuredQuery': {
        'from': [
          {'collectionId': 'live'}
        ],
        'where': {
          'fieldFilter': {
            'field': {'fieldPath': 'group'},
            'op': 'EQUAL',
            'value': {'stringValue': groupKey(group)}
          }
        },
        // Sem a foto (pesada): ela só é baixada quando muda (photoAt).
        'select': {
          'fields': [
            for (final k in [
              'nick', 'lat', 'lon', 'heading', 'speed', 'updatedAt', 'photoAt'
            ])
              {'fieldPath': k}
          ]
        },
        'limit': 200,
      }
    };
    try {
      final r = await http
          .post(Uri.parse('$_base:runQuery?key=$firebaseApiKey'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode == 403) rulesMissing = true;
      if (r.statusCode != 200) return false;
      final now = DateTime.now().millisecondsSinceEpoch;
      final seen = <String>{};
      for (final item in jsonDecode(utf8.decode(r.bodyBytes)) as List) {
        final doc = (item as Map)['document'] as Map?;
        if (doc == null) continue;
        final docId = doc['name'].toString().split('/').last;
        if (docId == id) continue;
        final f = (doc['fields'] as Map).cast<String, dynamic>();
        num? n(String k) {
          final v = f[k] as Map?;
          final raw = v?['doubleValue'] ?? v?['integerValue'];
          return raw is num ? raw : num.tryParse('$raw');
        }

        String s(String k) => (f[k] as Map?)?['stringValue']?.toString() ?? '';
        final at = n('updatedAt')?.toInt() ?? 0;
        final lat = n('lat')?.toDouble(), lon = n('lon')?.toDouble();
        if (lat == null || lon == null || now - at > staleMs) continue;
        seen.add(docId);
        final pAt = n('photoAt')?.toInt() ?? 0;
        var m = members[docId];
        if (m == null) {
          m = members[docId] = LiveMember(
              docId,
              s('nick'),
              null,
              lat,
              lon,
              n('heading')?.toDouble() ?? 0,
              n('speed')?.toDouble() ?? 0,
              at);
        } else {
          final (sl, so) = m.shown;
          m
            ..fromLat = sl
            ..fromLon = so
            ..lat = lat
            ..lon = lon
            ..heading = n('heading')?.toDouble() ?? m.heading
            ..kmh = n('speed')?.toDouble() ?? m.kmh
            ..updatedAt = at
            ..nick = s('nick')
            ..receivedAt = now;
        }
        if (pAt != m.photoAt) {
          m.photoAt = pAt;
          _photo(m);
        }
      }
      members.removeWhere((k, _) => !seen.contains(k));
      return true;
    } catch (_) {
      return false;
    }
  }
}
