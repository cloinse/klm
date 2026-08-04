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
    secondaryText: Color(0xFF8995A3),
    tertiaryText: Color(0xFF6F7B89),
    mutedIcon: Color(0xFF8793A0),
  );

  static const light = KlmColors(
    sidebar: Color(0xFFF0F3F7),
    card: Color(0xFFFFFFFF),
    border: Color(0xFFD7DEE7),
    control: Color(0xFFFFFFFF),
    controlBorder: Color(0xFFCCD5E0),
    iconTileStart: Color(0xFFE9EEF4),
    iconTileEnd: Color(0xFFDDE5EE),
    iconForeground: Color(0xFF536171),
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
