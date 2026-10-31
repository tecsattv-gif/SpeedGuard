import 'package:flutter/material.dart';

/// Uma paleta de cores do app (escolhida em Configurações → Cores).
class AppPalette {
  final String name;
  final Color main; // anel do velocímetro, bordas, destaques
  final Color light; // ícones e textos de destaque no escuro
  final Color bg; // fundo escuro
  final Color surface; // cartões no escuro
  final Color surfaceHigh; // botões secundários no escuro
  final Color deepTop; // topo dos degradês escuros
  final Color lightAccent; // destaque no modo claro
  final Color lightBg; // fundo no modo claro

  const AppPalette(this.name,
      {required this.main,
      required this.light,
      required this.bg,
      required this.surface,
      required this.surfaceHigh,
      required this.deepTop,
      required this.lightAccent,
      required this.lightBg});

  static const all = [
    AppPalette('Roxo',
        main: Color(0xFF8C50FF),
        light: Color(0xFFB794FF),
        bg: Color(0xFF14081F),
        surface: Color(0xFF221236),
        surfaceHigh: Color(0xFF2E1850),
        deepTop: Color(0xFF3C1460),
        lightAccent: Color(0xFF6A35D9),
        lightBg: Color(0xFFF5F0FC)),
    AppPalette('Azul',
        main: Color(0xFF3D7BFF),
        light: Color(0xFF8DB3FF),
        bg: Color(0xFF07101F),
        surface: Color(0xFF102036),
        surfaceHigh: Color(0xFF172C50),
        deepTop: Color(0xFF14305F),
        lightAccent: Color(0xFF1D5BD8),
        lightBg: Color(0xFFEEF3FC)),
    AppPalette('Verde',
        main: Color(0xFF22C55E),
        light: Color(0xFF86EFAC),
        bg: Color(0xFF06140C),
        surface: Color(0xFF0E2418),
        surfaceHigh: Color(0xFF153522),
        deepTop: Color(0xFF154A2A),
        lightAccent: Color(0xFF15803D),
        lightBg: Color(0xFFEEF8F1)),
    AppPalette('Laranja',
        main: Color(0xFFFF8A1F),
        light: Color(0xFFFFC078),
        bg: Color(0xFF170D05),
        surface: Color(0xFF2A180A),
        surfaceHigh: Color(0xFF3D230F),
        deepTop: Color(0xFF5A3010),
        lightAccent: Color(0xFFC2410C),
        lightBg: Color(0xFFFCF3EB)),
    AppPalette('Vermelho',
        main: Color(0xFFE53950),
        light: Color(0xFFFF8A9A),
        bg: Color(0xFF180609),
        surface: Color(0xFF2C0E14),
        surfaceHigh: Color(0xFF40141D),
        deepTop: Color(0xFF5C1424),
        lightAccent: Color(0xFFBE123C),
        lightBg: Color(0xFFFCEEF0)),
    AppPalette('Grafite',
        main: Color(0xFF9CA3AF),
        light: Color(0xFFD1D5DB),
        bg: Color(0xFF0E0F12),
        surface: Color(0xFF1C1E23),
        surfaceHigh: Color(0xFF2A2D34),
        deepTop: Color(0xFF33363E),
        lightAccent: Color(0xFF4B5563),
        lightBg: Color(0xFFF2F3F5)),
  ];

  static AppPalette byName(String? n) =>
      all.firstWhere((p) => p.name == n, orElse: () => all.first);
}

/// Cores do SpeedGuard. As de alerta (vermelho, rosa, laranja) são fixas;
/// as demais seguem a paleta escolhida.
class SG {
  static const pink = Color(0xFFFF46A0);
  static const red = Color(0xFFFF2846);
  static const orange = Color(0xFFFF7A2F);

  /// Paleta escolhida em Configurações (padrão: Roxo).
  static final palette = ValueNotifier<AppPalette>(AppPalette.all.first);
  static AppPalette get _p => palette.value;

  static Color get bg => _p.bg;
  static Color get surface => _p.surface;
  static Color get surfaceHigh => _p.surfaceHigh;
  static Color get violet => _p.main;
  static Color get violetLight => _p.light;
  static Color get outline => _p.main.withValues(alpha: 0.6);
  static Color get line => _p.main.withValues(alpha: 0.33);

  /// Escolha do usuário em Configurações (Automático, Claro ou Escuro).
  static final mode = ValueNotifier<ThemeMode>(ThemeMode.system);

  /// Tema em uso agora (atualizado pelo MaterialApp a cada mudança).
  static bool dark = true;

  // Cores que mudam com o tema claro/escuro (o painel flutuante e a
  // abertura ficam sempre escuros).
  static Color get page => dark ? bg : _p.lightBg;
  static Color get card => dark ? surface : Colors.white;
  static Color get cardHigh => dark
      ? surfaceHigh
      : Color.alphaBlend(_p.lightAccent.withValues(alpha: 0.13), Colors.white);
  static Color get accent => dark ? violetLight : _p.lightAccent;
  static Color get text => dark ? Colors.white : const Color(0xFF1E1230);
  static Color get textSoft =>
      dark ? Colors.white70 : const Color(0xFF5B4C70);

  /// Degradê principal (botão INICIAR, destaques).
  static const hot = LinearGradient(
    colors: [red, pink],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  /// Degradê escuro (velocímetro, painel).
  static LinearGradient get deep => LinearGradient(
        colors: [_p.deepTop, bg],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );

  static List<BoxShadow> glow(Color c, [double r = 14]) =>
      [BoxShadow(color: c.withValues(alpha: 0.55), blurRadius: r)];

  static ThemeData theme() {
    final scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: red,
      onPrimary: Colors.white,
      secondary: violet,
      onSecondary: Colors.white,
      tertiary: pink,
      onTertiary: Colors.white,
      error: red,
      onError: Colors.white,
      surface: surface,
      onSurface: Colors.white,
      surfaceContainerLowest: bg,
      surfaceContainerLow: Color.lerp(bg, surface, 0.5)!,
      surfaceContainer: surface,
      surfaceContainerHigh: surfaceHigh,
      surfaceContainerHighest: Color.lerp(surfaceHigh, violet, 0.15)!,
      secondaryContainer: surfaceHigh,
      onSecondaryContainer: violetLight,
      primaryContainer: const Color(0xFF5A0E2A),
      onPrimaryContainer: Colors.white,
      outline: violet.withValues(alpha: 0.4),
      outlineVariant: violet.withValues(alpha: 0.2),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: violet.withValues(alpha: 0.4)),
        ),
      ),
      dialogTheme: DialogThemeData(backgroundColor: surface),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        showDragHandle: true,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHigh,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? violet : null),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
          color: pink, linearTrackColor: surfaceHigh),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: violet,
        foregroundColor: Colors.white,
      ),
    );
  }

  static ThemeData lightTheme() {
    final acc = _p.lightAccent;
    final pageL = _p.lightBg;
    final highL = Color.alphaBlend(acc.withValues(alpha: 0.13), Colors.white);
    final scheme = ColorScheme(
      brightness: Brightness.light,
      primary: const Color(0xFFE0103A),
      onPrimary: Colors.white,
      secondary: acc,
      onSecondary: Colors.white,
      tertiary: pink,
      onTertiary: Colors.white,
      error: red,
      onError: Colors.white,
      surface: Colors.white,
      onSurface: const Color(0xFF1E1230),
      surfaceContainerLowest: pageL,
      surfaceContainerLow:
          Color.alphaBlend(acc.withValues(alpha: 0.03), Colors.white),
      surfaceContainer: Colors.white,
      surfaceContainerHigh: highL,
      surfaceContainerHighest:
          Color.alphaBlend(acc.withValues(alpha: 0.2), Colors.white),
      secondaryContainer: highL,
      onSecondaryContainer: Color.lerp(acc, Colors.black, 0.35)!,
      primaryContainer: const Color(0xFFFFD9E0),
      onPrimaryContainer: const Color(0xFF5A0E2A),
      outline: acc.withValues(alpha: 0.6),
      outlineVariant: acc.withValues(alpha: 0.27),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: pageL,
      canvasColor: pageL,
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: acc.withValues(alpha: 0.4)),
        ),
      ),
      dialogTheme: const DialogThemeData(backgroundColor: Colors.white),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        showDragHandle: true,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _p.surfaceHigh,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? violet : null),
      ),
      progressIndicatorTheme:
          ProgressIndicatorThemeData(color: pink, linearTrackColor: highL),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: violet,
        foregroundColor: Colors.white,
      ),
    );
  }
}
