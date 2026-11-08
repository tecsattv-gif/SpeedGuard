import 'dart:async';

import 'package:flutter/material.dart';
import 'i18n.dart';

/// Tela de abertura: arte do SpeedGuard + créditos, por 2,5 segundos.
class SplashScreen extends StatefulWidget {
  final Widget next;
  const SplashScreen({super.key, required this.next});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 2500), _go);
  }

  void _go() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (_, __, ___) => widget.next,
      transitionsBuilder: (_, a, __, child) =>
          FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14081F),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/splash.png', fit: BoxFit.cover),
          Positioned(
            left: 16,
            right: 16,
            bottom: 36,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tr('Desenvolvido por'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60, fontSize: 13)),
                  SizedBox(height: 2),
                  Text('Luiz Alberto Cardoso',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5)),
                  SizedBox(height: 2),
                  Text('tecsattv@gmail.com',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
