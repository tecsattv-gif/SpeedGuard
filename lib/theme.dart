import 'package:flutter/material.dart';

/// Paleta do SpeedGuard (mesmas cores da tela de abertura).
class SG {
  static const bg = Color(0xFF14081F); // roxo quase preto
  static const surface = Color(0xFF221236); // cartões
  static const surfaceHigh = Color(0xFF2E1850); // botões secundários
  static const violet = Color(0xFF8C50FF); // anel do velocímetro
  static const violetLight = Color(0xFFB794FF);
  static const pink = Color(0xFFFF46A0);
  static const red = Color(0xFFFF2846);
  static const orange = Color(0xFFFF7A2F);

  /// Escolha do usuário em Configurações (Automático, Claro ou Escuro).
  static final mode = ValueNotifier<ThemeMode>(ThemeMode.system);

  /// Tema em uso agora (atualizado pelo MaterialApp a cada mudança).
  static bool dark = true;

  // Cores que mudam com o tema (o painel flutuante e a abertura ficam
  // sempre escuros e usam as constantes acima).
  static Color get page => dark ? bg : const Color(0xFFF5F0FC);
  static Color get card => dark ? surface : Colors.white;
  static Color get cardHigh => dark ? surfaceHigh : const Color(0xFFECE2FB);
  static Color get accent => dark ? violetLight : const Color(0xFF6A35D9);
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
  static const deep = LinearGradient(
    colors: [Color(0xFF3C1460), bg],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static List<BoxShadow> glow(Color c, [double r = 14]) =>
      [BoxShadow(color: c.withValues(alpha: 0.55), blurRadius: r)];

  static ThemeData theme() {
    const scheme = ColorScheme(
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
      surfaceContainerLow: Color(0xFF1A0C2A),
      surfaceContainer: surface,
      surfaceContainerHigh: surfaceHigh,
      surfaceContainerHighest: Color(0xFF3A2063),
      secondaryContainer: surfaceHigh,
      onSecondaryContainer: violetLight,
      primaryContainer: Color(0xFF5A0E2A),
      onPrimaryContainer: Colors.white,
      outline: Color(0x668C50FF),
      outlineVariant: Color(0x338C50FF),
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
          side: const BorderSide(color: Color(0x668C50FF)),
        ),
      ),
      dialogTheme: const DialogThemeData(backgroundColor: surface),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        showDragHandle: true,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: surfaceHigh,
        contentTextStyle: TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? violet : null),
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: pink, linearTrackColor: surfaceHigh),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: violet,
        foregroundColor: Colors.white,
      ),
    );
  }
  static ThemeData lightTheme() {
    const pageL = Color(0xFFF5F0FC);
    const highL = Color(0xFFECE2FB);
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFFE0103A),
      onPrimary: Colors.white,
      secondary: Color(0xFF6A35D9),
      onSecondary: Colors.white,
      tertiary: pink,
      onTertiary: Colors.white,
      error: red,
      onError: Colors.white,
      surface: Colors.white,
      onSurface: Color(0xFF1E1230),
      surfaceContainerLowest: pageL,
      surfaceContainerLow: Color(0xFFFAF7FE),
      surfaceContainer: Colors.white,
      surfaceContainerHigh: highL,
      surfaceContainerHighest: Color(0xFFE2D4F8),
      secondaryContainer: highL,
      onSecondaryContainer: Color(0xFF4A1F8C),
      primaryContainer: Color(0xFFFFD9E0),
      onPrimaryContainer: Color(0xFF5A0E2A),
      outline: Color(0x996A35D9),
      outlineVariant: Color(0x446A35D9),
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
          side: const BorderSide(color: Color(0x666A35D9)),
        ),
      ),
      dialogTheme: const DialogThemeData(backgroundColor: Colors.white),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        showDragHandle: true,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Color(0xFF2E1850),
        contentTextStyle: TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? violet : null),
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: pink, linearTrackColor: highL),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: violet,
        foregroundColor: Colors.white,
      ),
    );
  }
}
