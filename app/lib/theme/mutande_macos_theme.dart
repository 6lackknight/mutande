import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';

/// Stone surface tokens shared by Material content + macos_ui shell.
abstract final class MutandeColors {
  static const stone50 = Color(0xFFFAFAF9);
  static const stone100 = Color(0xFFF5F5F4);
  static const stone200 = Color(0xFFE7E5E4);
  static const stone400 = Color(0xFFA8A29E);
  static const stone500 = Color(0xFF78716C);
  static const stone600 = Color(0xFF57534E);
  static const stone800 = Color(0xFF292524);
  static const bronze = Color(0xFF92400E);
  static const amber = Color(0xFFB45309);
  static const emerald = Color(0xFF166534);
}

/// Material theme for Threads / Agents / Contacts content (mutande stone).
ThemeData mutandeMaterialTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: MutandeColors.bronze,
      brightness: Brightness.light,
      surface: MutandeColors.stone50,
    ),
    scaffoldBackgroundColor: MutandeColors.stone100,
    appBarTheme: const AppBarTheme(
      backgroundColor: MutandeColors.stone50,
      foregroundColor: Color(0xFF44403C),
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: MutandeColors.stone50,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: MutandeColors.stone200),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: MutandeColors.stone600,
        foregroundColor: MutandeColors.stone50,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MutandeColors.stone50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: const TextStyle(color: MutandeColors.stone400),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: MutandeColors.stone200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: MutandeColors.stone200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: MutandeColors.bronze, width: 1.5),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: MutandeColors.stone200),
      ),
    ),
  );
}

/// macos_ui shell theme — native chrome, stone-tinted canvas.
MacosThemeData mutandeMacosTheme() {
  final base = MacosThemeData.light();
  return base.copyWith(
    primaryColor: MutandeColors.bronze,
    canvasColor: MutandeColors.stone100,
    pushButtonTheme: PushButtonThemeData(
      color: MutandeColors.stone800,
      disabledColor: MutandeColors.stone200,
    ),
    iconTheme: const MacosIconThemeData(
      color: MutandeColors.stone600,
      size: 18,
    ),
    dividerColor: MutandeColors.stone200,
    helpButtonTheme: const HelpButtonThemeData(
      color: MutandeColors.stone500,
      disabledColor: MutandeColors.stone400,
    ),
  );
}

/// Applies MacosTheme + Material Theme so shell chrome and content coexist.
Widget mutandeThemeBridge({required Widget child}) {
  return MacosTheme(
    data: mutandeMacosTheme(),
    child: Theme(
      data: mutandeMaterialTheme(),
      child: DefaultTextStyle(
        style: mutandeMaterialTheme().textTheme.bodyMedium!,
        child: Material(
          // Material ink/text fields need an ancestor Material.
          color: MutandeColors.stone100,
          child: ScaffoldMessenger(child: child),
        ),
      ),
    ),
  );
}
