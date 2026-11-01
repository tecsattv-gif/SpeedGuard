import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'theme.dart';

/// Vídeo tutorial (Configurações → Tutorial). O vídeo vai dentro do app,
/// então funciona sem internet.
class TutorialPage extends StatefulWidget {
  const TutorialPage({super.key});

  @override
  State<TutorialPage> createState() => _TutorialPageState();
}

class _TutorialPageState extends State<TutorialPage> {
  final _video = VideoPlayerController.asset('assets/tutorial.mp4');
  bool _ready = false;
  bool _controls = true;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _video.addListener(() {
      if (mounted) setState(() {});
    });
    _video.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _video.play();
      _autoHide();
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    _video.dispose();
    super.dispose();
  }

  void _autoHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && _video.value.isPlaying) setState(() => _controls = false);
    });
  }

  void _tap() {
    setState(() => _controls = !_controls);
    if (_controls) _autoHide();
  }

  void _playPause() {
    final v = _video.value;
    if (v.isPlaying) {
      _video.pause();
    } else {
      if (v.position >= v.duration) _video.seekTo(Duration.zero);
      _video.play();
    }
    _autoHide();
  }

  void _skip(int seconds) {
    final v = _video.value;
    var t = v.position + Duration(seconds: seconds);
    if (t < Duration.zero) t = Duration.zero;
    if (t > v.duration) t = v.duration;
    _video.seekTo(t);
    _autoHide();
  }

  static String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final v = _video.value;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Tutorial'),
      ),
      body: !_ready
          ? Center(child: CircularProgressIndicator(color: SG.violet))
          : GestureDetector(
              onTap: _tap,
              behavior: HitTestBehavior.opaque,
              child: Stack(
                children: [
                  Center(
                    child: AspectRatio(
                      aspectRatio: v.aspectRatio,
                      child: VideoPlayer(_video),
                    ),
                  ),
                  if (_controls)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black38,
                        child: Column(
                          children: [
                            const Spacer(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  iconSize: 40,
                                  color: Colors.white,
                                  icon: const Icon(Icons.replay_10),
                                  onPressed: () => _skip(-10),
                                ),
                                const SizedBox(width: 24),
                                Container(
                                  decoration: BoxDecoration(
                                    gradient: SG.hot,
                                    shape: BoxShape.circle,
                                  ),
                                  child: IconButton(
                                    iconSize: 48,
                                    color: Colors.white,
                                    icon: Icon(v.isPlaying
                                        ? Icons.pause
                                        : Icons.play_arrow),
                                    onPressed: _playPause,
                                  ),
                                ),
                                const SizedBox(width: 24),
                                IconButton(
                                  iconSize: 40,
                                  color: Colors.white,
                                  icon: const Icon(Icons.forward_10),
                                  onPressed: () => _skip(10),
                                ),
                              ],
                            ),
                            const Spacer(),
                            SafeArea(
                              top: false,
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                child: Row(
                                  children: [
                                    Text(_fmt(v.position),
                                        style: const TextStyle(
                                            color: Colors.white)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: VideoProgressIndicator(
                                        _video,
                                        allowScrubbing: true,
                                        colors: VideoProgressColors(
                                          playedColor: SG.pink,
                                          bufferedColor: Colors.white24,
                                          backgroundColor: Colors.white12,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(_fmt(v.duration),
                                        style: const TextStyle(
                                            color: Colors.white)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
