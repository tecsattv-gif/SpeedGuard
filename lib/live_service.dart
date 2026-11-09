import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_config.dart';
import 'i18n.dart';

/// Um motorista do grupo no mapa.
class LiveMember {
  final String id;
  String nick;
  String country = ''; // ISO2 (1.29.47)
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

/// Mensagem direta entre colegas do grupo (1.32.0).
class LiveMsg {
  final String id, from, nick, text;
  final int at;

  /// Mensagem de voz (1.33.0): arquivo .m4a salvo no aparelho e duração.
  final String? audioPath;
  final int durMs;
  LiveMsg(this.id, this.from, this.nick, this.text, this.at,
      {this.audioPath, this.durMs = 0});

  bool get isVoice => audioPath != null;

  Map<String, dynamic> toJson() => {
        'id': id, 'from': from, 'nick': nick, 'text': text, 'at': at,
        if (audioPath != null) 'audio': audioPath, 'dur': durMs,
      };
  static LiveMsg fromJson(Map m) => LiveMsg(
      '${m['id']}', '${m['from']}', '${m['nick']}', '${m['text']}',
      (m['at'] as num?)?.toInt() ?? 0,
      audioPath: m['audio'] as String?,
      durMs: (m['dur'] as num?)?.toInt() ?? 0);
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
  /// A regra do Firebase ainda não aceita o país (falta publicar).
  bool countryRuleMissing = false;

  Future<bool> push(double lat, double lon, double heading, double kmh,
      {bool withPhoto = false, String? country}) async {
    final ok = await _push(lat, lon, heading, kmh,
        withPhoto: withPhoto,
        country: countryRuleMissing ? null : country);
    if (!ok && rulesMissing && country != null && !countryRuleMissing) {
      // Regra antiga (sem "country"): manda sem o país.
      countryRuleMissing = true;
      return _push(lat, lon, heading, kmh, withPhoto: withPhoto);
    }
    return ok;
  }

  Future<bool> _push(double lat, double lon, double heading, double kmh,
      {bool withPhoto = false, String? country}) async {
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
      if (country != null && country.isNotEmpty)
        'country': {'stringValue': country.toLowerCase()},
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

  /// Colegas que mudaram de país desde a última olhada (1.29.47): lista de
  /// (apelido, país). O último país de cada um fica guardado no aparelho,
  /// então cada travessia avisa uma vez só (app aberto ou em segundo plano).
  Future<List<(String, String)>> borderEvents() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    Map<String, dynamic> last;
    try {
      last = jsonDecode(p.getString('live_countries') ?? '{}') as Map<String, dynamic>;
    } catch (_) {
      last = {};
    }
    final out = <(String, String)>[];
    for (final m in members.values) {
      if (m.country.isEmpty) continue;
      final before = last[m.id] as String?;
      if (before != null && before != m.country) {
        out.add((m.nick.isEmpty ? tr('Um colega') : m.nick, m.country));
      }
      last[m.id] = m.country;
    }
    await p.setString('live_countries', jsonEncode(last));
    return out;
  }

  /// "na França 🇫🇷", "em Portugal 🇵🇹"…
  static String inCountry(String cc) {
    final c = cc.toLowerCase();
    final (name, prep) = _names[c] ?? (c.toUpperCase(), 'em');
    final flag = c.length == 2
        ? String.fromCharCodes(
            c.toUpperCase().codeUnits.map((u) => u - 0x41 + 0x1F1E6))
        : '';
    // Preposição ("na", "em"…) só em português; nos outros idiomas
    // a frase já traz a sua ("is in", "está en", "est en").
    final p = appLang == 'pt' ? '$prep ' : '';
    return '$p$name $flag'.trim();
  }

  static String countryName(String cc) =>
      (_names[cc.toLowerCase()] ?? (cc.toUpperCase(), '')).$1;

  static Map<String, (String, String)> get _names => {
    'pt': (tr('Portugal'), 'em'), 'es': (tr('Espanha'), 'na'), 'fr': (tr('França'), 'na'),
    'de': (tr('Alemanha'), 'na'), 'it': (tr('Itália'), 'na'), 'be': (tr('Bélgica'), 'na'),
    'nl': (tr('Holanda'), 'na'), 'lu': (tr('Luxemburgo'), 'em'), 'ch': (tr('Suíça'), 'na'),
    'at': (tr('Áustria'), 'na'), 'pl': (tr('Polônia'), 'na'), 'cz': (tr('Chéquia'), 'na'),
    'sk': (tr('Eslováquia'), 'na'), 'hu': (tr('Hungria'), 'na'),
    'si': (tr('Eslovênia'), 'na'), 'hr': (tr('Croácia'), 'na'), 'ro': (tr('Romênia'), 'na'),
    'bg': (tr('Bulgária'), 'na'), 'gr': (tr('Grécia'), 'na'), 'dk': (tr('Dinamarca'), 'na'),
    'se': (tr('Suécia'), 'na'), 'no': (tr('Noruega'), 'na'), 'fi': (tr('Finlândia'), 'na'),
    'gb': (tr('Reino Unido'), 'no'), 'ie': (tr('Irlanda'), 'na'), 'ad': (tr('Andorra'), 'em'),
    'mc': (tr('Mônaco'), 'em'), 'li': (tr('Liechtenstein'), 'em'),
    'rs': (tr('Sérvia'), 'na'), 'ba': (tr('Bósnia'), 'na'), 'me': (tr('Montenegro'), 'em'),
    'mk': (tr('Macedônia do Norte'), 'na'), 'al': (tr('Albânia'), 'na'),
    'lt': (tr('Lituânia'), 'na'), 'lv': (tr('Letônia'), 'na'), 'ee': (tr('Estônia'), 'na'),
    'ua': (tr('Ucrânia'), 'na'), 'md': (tr('Moldávia'), 'na'), 'tr': (tr('Turquia'), 'na'),
    'ma': (tr('Marrocos'), 'em'), 'br': (tr('Brasil'), 'no'), 'ar': (tr('Argentina'), 'na'),
    'uy': (tr('Uruguai'), 'no'), 'py': (tr('Paraguai'), 'no'), 'cl': (tr('Chile'), 'no'),
    'bo': (tr('Bolívia'), 'na'), 'pe': (tr('Peru'), 'no'), 'us': (tr('Estados Unidos'), 'nos'),
    'ca': (tr('Canadá'), 'no'), 'mx': (tr('México'), 'no'),
  };

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
              'nick', 'lat', 'lon', 'heading', 'speed', 'updatedAt', 'photoAt',
              'country'
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
        final cc = s('country');
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
        m.country = cc;
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

  // ---------- Mensagens diretas (1.32.0) ----------

  /// A regra `msgs` ainda não foi publicada no Firebase.
  bool msgRulesMissing = false;

  /// Mensagem de voz: no máximo 60 s e ~300 KB (limite da regra `msgs`).
  static const voiceMaxSec = 60;
  static const voiceMaxBytes = 300000;

  /// Manda [text] (com emojis) para o colega [toId] (id do aparelho dele).
  /// Com [audio] (1.33.0) vai também a gravação (AAC/m4a) e a duração; o
  /// texto serve de aviso para quem ainda tem versão sem voz.
  /// Devolve o id do documento no Firebase (para os tiques de entregue,
  /// 1.37.0) ou null se não enviou.
  Future<String?> sendMsg(String toId, String text,
      {Uint8List? audio, int durMs = 0}) async {
    if (!communityEnabled || !hasGroup) return null;
    final t = text.trim();
    if (t.isEmpty) return null;
    if (audio != null && audio.length > voiceMaxBytes) return null;
    final id = await _deviceId();
    final fields = {
      'to': {'stringValue': toId},
      'from': {'stringValue': id},
      'group': {'stringValue': groupKey(group)},
      'nick': {
        'stringValue': nick.length > 30 ? nick.substring(0, 30) : nick
      },
      'text': {'stringValue': t.length > 300 ? t.substring(0, 300) : t},
      'at': {'integerValue': '${DateTime.now().millisecondsSinceEpoch}'},
      if (audio != null) 'audio': {'bytesValue': base64Encode(audio)},
      if (audio != null) 'dur': {'integerValue': '$durMs'},
    };
    try {
      final r = await http
          .post(Uri.parse('$_base/msgs?key=$firebaseApiKey'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'fields': fields}))
          .timeout(Duration(seconds: audio == null ? 20 : 45));
      msgRulesMissing = r.statusCode == 403;
      if (r.statusCode != 200) return null;
      final name = (jsonDecode(utf8.decode(r.bodyBytes)) as Map)['name'];
      return name.toString().split('/').last;
    } catch (_) {
      return null;
    }
  }

  /// Tiques de entregue (1.37.0): quem recebe apaga a mensagem do Firebase
  /// assim que ela chega no aparelho dele. Então, se o documento sumiu
  /// (404), a mensagem foi entregue. true = entregue, false = ainda não,
  /// null = sem internet (tenta de novo depois).
  Future<bool?> delivered(String docId) async {
    try {
      final r = await http
          .get(Uri.parse('$_base/msgs/$docId?key=$firebaseApiKey'))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 404) return true;
      if (r.statusCode == 200) return false;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Mensagens que chegaram para você (do seu grupo). Cada uma é apagada do
  /// Firebase depois de baixada, então só chega uma vez; com mais de 24 h
  /// é apagada sem mostrar.
  Future<List<LiveMsg>> inbox() async {
    if (!communityEnabled || !hasGroup) return const [];
    final id = await _deviceId();
    final body = {
      'structuredQuery': {
        'from': [
          {'collectionId': 'msgs'}
        ],
        'where': {
          'fieldFilter': {
            'field': {'fieldPath': 'to'},
            'op': 'EQUAL',
            'value': {'stringValue': id}
          }
        },
        'limit': 30,
      }
    };
    try {
      final r = await http
          .post(Uri.parse('$_base:runQuery?key=$firebaseApiKey'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode == 403) msgRulesMissing = true;
      if (r.statusCode != 200) return const [];
      final now = DateTime.now().millisecondsSinceEpoch;
      final out = <LiveMsg>[];
      for (final item in jsonDecode(utf8.decode(r.bodyBytes)) as List) {
        final doc = (item as Map)['document'] as Map?;
        if (doc == null) continue;
        final docId = doc['name'].toString().split('/').last;
        final f = (doc['fields'] as Map).cast<String, dynamic>();
        String s(String k) => (f[k] as Map?)?['stringValue']?.toString() ?? '';
        final at = int.tryParse(
                '${(f['at'] as Map?)?['integerValue'] ?? 0}') ??
            0;
        // Apaga do Firebase (já foi entregue).
        http
            .delete(Uri.parse('$_base/msgs/$docId?key=$firebaseApiKey'))
            .timeout(const Duration(seconds: 15))
            .catchError((_) => http.Response('', 0));
        if (s('group') != groupKey(group)) continue;
        if (now - at > 24 * 3600 * 1000) continue;
        // Mensagem de voz (1.33.0): grava o áudio num arquivo do aparelho.
        String? audioPath;
        var dur = 0;
        final b64 = (f['audio'] as Map?)?['bytesValue']?.toString();
        if (b64 != null && b64.isNotEmpty) {
          try {
            final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/voice');
            await dir.create(recursive: true);
            final file = File('${dir.path}/$docId.m4a');
            await file.writeAsBytes(base64Decode(b64));
            audioPath = file.path;
            dur = int.tryParse('${(f['dur'] as Map?)?['integerValue'] ?? 0}') ?? 0;
          } catch (_) {}
        }
        out.add(LiveMsg(docId, s('from'), s('nick'), s('text'), at,
            audioPath: audioPath, durMs: dur));
      }
      out.sort((a, b) => a.at.compareTo(b.at));
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Mensagens que chegaram com o app fechado (serviço em segundo plano):
  /// ficam guardadas para entrar na conversa quando o app abrir (1.33.0).
  static Future<void> savePending(List<LiveMsg> msgs) async {
    if (msgs.isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload();
      final list = (jsonDecode(p.getString('msg_pending') ?? '[]') as List)
        ..addAll(msgs.map((m) => m.toJson()));
      while (list.length > 100) {
        list.removeAt(0);
      }
      await p.setString('msg_pending', jsonEncode(list));
    } catch (_) {}
  }

  static Future<List<LiveMsg>> takePending() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload();
      final raw = p.getString('msg_pending');
      if (raw == null) return const [];
      await p.remove('msg_pending');
      return [for (final m in jsonDecode(raw) as List) LiveMsg.fromJson(m as Map)];
    } catch (_) {
      return const [];
    }
  }

  /// Apaga áudios recebidos/enviados com mais de 7 dias.
  static Future<void> cleanVoice() async {
    try {
      final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/voice');
      if (!await dir.exists()) return;
      final old = DateTime.now().subtract(const Duration(days: 7));
      await for (final e in dir.list()) {
        if (e is File && (await e.lastModified()).isBefore(old)) {
          await e.delete();
        }
      }
    } catch (_) {}
  }
}
