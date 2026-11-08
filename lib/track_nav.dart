import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'i18n.dart';

/// Curva da rota gravada: onde (m desde o início) e para que lado.
class TrackTurn {
  final double at;
  final double angle; // + direita, − esquerda (graus)
  const TrackTurn(this.at, this.angle);

  bool get right => angle > 0;
  double get abs => angle.abs();

  String get phrase {
    final side = right ? 'direita' : 'esquerda';
    if (abs >= 150) return tr('faça o retorno');
    if (abs >= 110) return tr('vire bem à {0}', [tr(side)]);
    if (abs >= 60) return tr('vire à {0}', [tr(side)]);
    return tr('mantenha-se à {0}', [tr(side)]);
  }

  IconData get icon {
    if (abs >= 150) return right ? Icons.u_turn_right : Icons.u_turn_left;
    if (abs >= 110) return right ? Icons.turn_sharp_right : Icons.turn_sharp_left;
    if (abs >= 60) return right ? Icons.turn_right : Icons.turn_left;
    return right ? Icons.turn_slight_right : Icons.turn_slight_left;
  }
}

/// Navegação pela rota gravada (1.29.38): acha as curvas pelo desenho da
/// rota e avisa antes de cada uma; avisa quando sai da rota e quando chega.
class TrackNav {
  final List<(double, double)> pts;
  final List<double> cum;
  late final List<TrackTurn> turns = _findTurns();

  TrackNav(this.pts, this.cum);

  double get total => cum.isEmpty ? 0 : cum.last;

  static double _bearing((double, double) a, (double, double) b) {
    final la1 = a.$1 * math.pi / 180, la2 = b.$1 * math.pi / 180;
    final dl = (b.$2 - a.$2) * math.pi / 180;
    final y = math.sin(dl) * math.cos(la2);
    final x = math.cos(la1) * math.sin(la2) -
        math.sin(la1) * math.cos(la2) * math.cos(dl);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  static double _delta(double from, double to) {
    var d = (to - from) % 360;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return d;
  }

  /// Ponto [m] metros antes/depois do índice [i].
  int _back(int i, double m) {
    var j = i;
    while (j > 0 && cum[i] - cum[j] < m) {
      j--;
    }
    return j;
  }

  int _fwd(int i, double m) {
    var j = i;
    while (j < pts.length - 1 && cum[j] - cum[i] < m) {
      j++;
    }
    return j;
  }

  /// Curva = mudança de rumo de mais de 35° entre os 60 m antes e os 60 m
  /// depois de um ponto. Fica o ponto de maior mudança de cada trecho.
  List<TrackTurn> _findTurns() {
    if (pts.length < 3) return const [];
    final cand = <(int, double)>[];
    for (var i = 1; i < pts.length - 1; i++) {
      final a = _back(i, 60), b = _fwd(i, 60);
      if (a == i || b == i) continue;
      final d = _delta(_bearing(pts[a], pts[i]), _bearing(pts[i], pts[b]));
      if (d.abs() >= 35) cand.add((i, d));
    }
    final out = <TrackTurn>[];
    var k = 0;
    while (k < cand.length) {
      var best = cand[k];
      var j = k + 1;
      while (j < cand.length &&
          cum[cand[j].$1] - cum[cand[j - 1].$1] < 50 &&
          cand[j].$2.sign == best.$2.sign) {
        if (cand[j].$2.abs() > best.$2.abs()) best = cand[j];
        j++;
      }
      // Curva total do trecho (60 m antes até 60 m depois).
      final i = best.$1;
      final d = _delta(_bearing(pts[_back(i, 60)], pts[i]),
          _bearing(pts[i], pts[_fwd(i, 60)]));
      if (out.isEmpty || cum[i] - out.last.at > 80) out.add(TrackTurn(cum[i], d));
      k = j;
    }
    return out;
  }

  /// Próxima curva depois de [progress] metros.
  TrackTurn? next(double progress) {
    for (final t in turns) {
      if (t.at > progress + 15) return t;
    }
    return null;
  }

  /// Avisos de voz já dados ("<curva>@<faixa>").
  final Set<String> said = {};

  /// Frase para falar agora, ou null. Faixas: 1000 m (só acima de 70 km/h),
  /// 400 m, 150 m e "agora" (40 m).
  String? speak(double progress, double kmh) {
    final t = next(progress);
    if (t == null) return null;
    final d = t.at - progress;
    // Da faixa mais perto para a mais longe: vale a menor que contém d.
    final stages = <(double, String)>[
      (40, tr('Agora')),
      (150, tr('Em 150 metros')),
      (400, tr('Em 400 metros')),
      if (kmh > 70) (1000, tr('Em 1 quilômetro')),
    ];
    for (final (lim, txt) in stages) {
      if (d <= lim) {
        // Só a faixa mais perto que ainda não falou.
        final key = '${t.at.round()}@$lim';
        if (said.contains(key)) return null;
        said.add(key);
        // Não fala faixas maiores já passadas de uma vez.
        for (final (l2, _) in stages) {
          if (l2 > lim) said.add('${t.at.round()}@$l2');
        }
        final verb = t.phrase;
        return lim == 40
            ? '${verb[0].toUpperCase()}${verb.substring(1)}.'
            : '$txt, $verb.';
      }
    }
    return null;
  }
}

/// Inverte a rota (para fazer o caminho de volta).
List<(double, double)> reversedTrack(List<(double, double)> p) =>
    p.reversed.toList();
