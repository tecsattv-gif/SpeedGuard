import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

/// Bolha flutuante mostrada por cima de outros apps (Maps, Waze...).
/// Recebe do app principal: velocidade, distância e limite do radar.
class OverlayBubble extends StatefulWidget {
  const OverlayBubble({super.key});
  @override
  State<OverlayBubble> createState() => _OverlayBubbleState();
}

class _OverlayBubbleState extends State<OverlayBubble> {
  int _speed = 0;
  double? _dist;
  int? _limit;
  bool _over = false;
  bool _ask = false;

  @override
  void initState() {
    super.initState();
    FlutterOverlayWindow.overlayListener.listen((event) {
      try {
        final m = jsonDecode(event.toString()) as Map;
        setState(() {
          _speed = (m['speed'] as num?)?.toInt() ?? 0;
          _dist = (m['dist'] as num?)?.toDouble();
          _limit = (m['limit'] as num?)?.toInt();
          _over = m['over'] == true;
          _ask = m['ask'] == true;
        });
      } catch (_) {}
    });
  }

  void _reply(bool v) {
    FlutterOverlayWindow.shareData(jsonEncode({'answer': v}));
    setState(() => _ask = false);
  }

  Widget _round(IconData icon, Color c, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
      );

  Widget _askBubble() => Material(
        color: Colors.transparent,
        child: Center(
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.purple.shade700,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white70, width: 2),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Radar ainda\nestá aí?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _round(Icons.check, Colors.green.shade700,
                        () => _reply(true)),
                    const SizedBox(width: 6),
                    _round(Icons.close, Colors.red.shade700,
                        () => _reply(false)),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_ask) return _askBubble();
    final alert = _dist != null;
    final color = _over
        ? Colors.red.shade700
        : alert
            ? Colors.orange.shade800
            : const Color(0xEE1E1E1E);
    final d = _dist;
    return Material(
      color: Colors.transparent,
      child: Center(
        child: Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white70, width: 2),
            boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black45)],
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$_speed',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      height: 1)),
              const Text('km/h',
                  style: TextStyle(color: Colors.white70, fontSize: 11)),
              if (d != null)
                Text(
                  d >= 1000
                      ? '📷 ${(d / 1000).toStringAsFixed(1)} km'
                      : '📷 ${d.round()} m',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
              if (d != null && _limit != null)
                Text('limite $_limit',
                    style:
                        const TextStyle(color: Colors.white, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}
