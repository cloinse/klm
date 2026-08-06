import 'package:flutter/material.dart';

@immutable
class KlmColors extends ThemeExtension<KlmColors> {
  const KlmColors({
    required this.sidebar,
    required this.card,
    required this.border,
    required this.control,
    required this.controlBorder,
    required this.iconTileStart,
    required this.iconTileEnd,
    required this.iconForeground,
    required this.navigationSelectedBackground,
    required this.navigationSelectedForeground,
    required this.navigationSelectedBorder,
    required this.accentButtonBackground,
    required this.accentButtonForeground,
    required this.accentButtonBorder,
    required this.secondaryText,
    required this.tertiaryText,
    required this.mutedIcon,
  });

  final Color sidebar;
  final Color card;
  final Color border;
  final Color control;
  final Color controlBorder;
  final Color iconTileStart;
  final Color iconTileEnd;
  final Color iconForeground;
  final Color navigationSelectedBackground;
  final Color navigationSelectedForeground;
  final Color navigationSelectedBorder;
  final Color accentButtonBackground;
  final Color accentButtonForeground;
  final Color accentButtonBorder;
  final Color secondaryText;
  final Color tertiaryText;
  final Color mutedIcon;

  static const dark = KlmColors(
    sidebar: Color(0xFF0E141C),
    card: Color(0xFF121923),
    border: Color(0xFF222C38),
    control: Color(0xFF141B24),
    controlBorder: Color(0xFF273241),
    iconTileStart: Color(0xFF303946),
    iconTileEnd: Color(0xFF1D2530),
    iconForeground: Color(0xFFB5BEC8),
    navigationSelectedBackground: Color(0xFF312719),
    navigationSelectedForeground: Color(0xFFFFC65A),
    navigationSelectedBorder: Color(0xFF6F5626),
    accentButtonBackground: Color(0xFF3A2D16),
    accentButtonForeground: Color(0xFFF3C76B),
    accentButtonBorder: Color(0xFF6B5124),
    secondaryText: Color(0xFF8995A3),
    tertiaryText: Color(0xFF6F7B89),
    mutedIcon: Color(0xFF8793A0),
  );

  static const light = KlmColors(
    sidebar: Color(0xFFF6F7FA),
    card: Color(0xFFFFFFFF),
    border: Color(0xFFE3E7ED),
    control: Color(0xFFFFFFFF),
    controlBorder: Color(0xFFDDE3EA),
    iconTileStart: Color(0xFFE9EEF4),
    iconTileEnd: Color(0xFFDDE5EE),
    iconForeground: Color(0xFF536171),
    navigationSelectedBackground: Color(0xFFFFF7EA),
    navigationSelectedForeground: Color(0xFF725B35),
    navigationSelectedBorder: Color(0xFFE7C47E),
    accentButtonBackground: Color(0xFFFFEFD0),
    accentButtonForeground: Color(0xFF694718),
    accentButtonBorder: Color(0xFFE7B65B),
    secondaryText: Color(0xFF5F6C7A),
    tertiaryText: Color(0xFF74808D),
    mutedIcon: Color(0xFF647180),
  );

  @override
  KlmColors copyWith({
    Color? sidebar,
    Color? card,
    Color? border,
    Color? control,
    Color? controlBorder,
    Color? iconTileStart,
    Color? iconTileEnd,
    Color? iconForeground,
    Color? navigationSelectedBackground,
    Color? navigationSelectedForeground,
    Color? navigationSelectedBorder,
    Color? accentButtonBackground,
    Color? accentButtonForeground,
    Color? accentButtonBorder,
    Color? secondaryText,
    Color? tertiaryText,
    Color? mutedIcon,
  }) => KlmColors(
    sidebar: sidebar ?? this.sidebar,
    card: card ?? this.card,
    border: border ?? this.border,
    control: control ?? this.control,
    controlBorder: controlBorder ?? this.controlBorder,
    iconTileStart: iconTileStart ?? this.iconTileStart,
    iconTileEnd: iconTileEnd ?? this.iconTileEnd,
    iconForeground: iconForeground ?? this.iconForeground,
    navigationSelectedBackground:
        navigationSelectedBackground ?? this.navigationSelectedBackground,
    navigationSelectedForeground:
        navigationSelectedForeground ?? this.navigationSelectedForeground,
    navigationSelectedBorder:
        navigationSelectedBorder ?? this.navigationSelectedBorder,
    accentButtonBackground:
        accentButtonBackground ?? this.accentButtonBackground,
    accentButtonForeground:
        accentButtonForeground ?? this.accentButtonForeground,
    accentButtonBorder: accentButtonBorder ?? this.accentButtonBorder,
    secondaryText: secondaryText ?? this.secondaryText,
    tertiaryText: tertiaryText ?? this.tertiaryText,
    mutedIcon: mutedIcon ?? this.mutedIcon,
  );

  @override
  KlmColors lerp(covariant KlmColors? other, double t) {
    if (other == null) return this;
    return KlmColors(
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      card: Color.lerp(card, other.card, t)!,
      border: Color.lerp(border, other.border, t)!,
      control: Color.lerp(control, other.control, t)!,
      controlBorder: Color.lerp(controlBorder, other.controlBorder, t)!,
      iconTileStart: Color.lerp(iconTileStart, other.iconTileStart, t)!,
      iconTileEnd: Color.lerp(iconTileEnd, other.iconTileEnd, t)!,
      iconForeground: Color.lerp(iconForeground, other.iconForeground, t)!,
      navigationSelectedBackground: Color.lerp(
        navigationSelectedBackground,
        other.navigationSelectedBackground,
        t,
      )!,
      navigationSelectedForeground: Color.lerp(
        navigationSelectedForeground,
        other.navigationSelectedForeground,
        t,
      )!,
      navigationSelectedBorder: Color.lerp(
        navigationSelectedBorder,
        other.navigationSelectedBorder,
        t,
      )!,
      accentButtonBackground: Color.lerp(
        accentButtonBackground,
        other.accentButtonBackground,
        t,
      )!,
      accentButtonForeground: Color.lerp(
        accentButtonForeground,
        other.accentButtonForeground,
        t,
      )!,
      accentButtonBorder: Color.lerp(
        accentButtonBorder,
        other.accentButtonBorder,
        t,
      )!,
      secondaryText: Color.lerp(secondaryText, other.secondaryText, t)!,
      tertiaryText: Color.lerp(tertiaryText, other.tertiaryText, t)!,
      mutedIcon: Color.lerp(mutedIcon, other.mutedIcon, t)!,
    );
  }
}

extension KlmThemeContext on BuildContext {
  KlmColors get klmColors => Theme.of(this).extension<KlmColors>()!;
}

ThemeData buildKlmTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  const accent = Color(0xFFF2B544);
  final colors = dark ? KlmColors.dark : KlmColors.light;
  final colorScheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: brightness,
    surface: dark ? const Color(0xFF111821) : const Color(0xFFF7F9FC),
  );
  final base = ThemeData(brightness: brightness, useMaterial3: true);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: dark
        ? const Color(0xFF0B0F14)
        : const Color(0xFFF7F9FC),
    canvasColor: colorScheme.surface,
    dividerColor: colors.border,
    textTheme: base.textTheme.apply(
      bodyColor: dark ? const Color(0xFFE7EBEF) : const Color(0xFF1B2530),
      displayColor: dark ? const Color(0xFFF7F9FA) : const Color(0xFF101820),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.control,
      hintStyle: TextStyle(color: colors.secondaryText),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.controlBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.controlBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: accent, width: 1.4),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF26303C) : const Color(0xFF26303C),
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
    ),
    extensions: <ThemeExtension<dynamic>>[colors],
  );
}
