// lib/main.dart
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'core/routes/app_routes.dart';
import 'core/utils/orientation_utils.dart';
import 'core/ui/gamepad_skin.dart';
import 'core/ui/theme_controller.dart';
import 'core/ui/language_controller.dart';

TextStyle? _withFonts(
  TextStyle? style,
  String family,
  List<String> fallback,
) {
  if (style == null) return null;
  return style.copyWith(
    fontFamily: family,
    fontFamilyFallback: fallback,
  );
}

TextTheme _applyFonts(
  TextTheme base,
  String family,
  List<String> fallback,
) {
  return base.copyWith(
    displayLarge: _withFonts(base.displayLarge, family, fallback),
    displayMedium: _withFonts(base.displayMedium, family, fallback),
    displaySmall: _withFonts(base.displaySmall, family, fallback),
    headlineLarge: _withFonts(base.headlineLarge, family, fallback),
    headlineMedium: _withFonts(base.headlineMedium, family, fallback),
    headlineSmall: _withFonts(base.headlineSmall, family, fallback),
    titleLarge: _withFonts(base.titleLarge, family, fallback),
    titleMedium: _withFonts(base.titleMedium, family, fallback),
    titleSmall: _withFonts(base.titleSmall, family, fallback),
    bodyLarge: _withFonts(base.bodyLarge, family, fallback),
    bodyMedium: _withFonts(base.bodyMedium, family, fallback),
    bodySmall: _withFonts(base.bodySmall, family, fallback),
    labelLarge: _withFonts(base.labelLarge, family, fallback),
    labelMedium: _withFonts(base.labelMedium, family, fallback),
    labelSmall: _withFonts(base.labelSmall, family, fallback),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeController.init();
  await LanguageController.init();
  await OrientationUtils.applyStartupOrientation();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF6750A4);
    const fontFamily = 'Roboto';
    const fontFallback = ['Kanit'];
    final lightScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    );
    final darkScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    );

    return ValueListenableBuilder<bool>(
      valueListenable: LanguageController.isThai,
      builder: (context, _, __) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: ThemeController.mode,
          builder: (context, mode, _) {
            final lightTextTheme = _applyFonts(
              ThemeData.light().textTheme.apply(
                    bodyColor: lightScheme.onSurface,
                    displayColor: lightScheme.onSurface,
                  ),
              fontFamily,
              fontFallback,
            );
            final darkTextTheme = _applyFonts(
              ThemeData.dark().textTheme.apply(
                    bodyColor: darkScheme.onSurface,
                    displayColor: darkScheme.onSurface,
                  ),
              fontFamily,
              fontFallback,
            );

            return MaterialApp(
              title: 'PrinceBot Controller',
              debugShowCheckedModeBanner: false,
              themeMode: mode,
              theme: ThemeData(
                colorScheme: lightScheme,
                useMaterial3: true,
                extensions: const <ThemeExtension<dynamic>>[
                  GamepadSkin.light(),
                ],
                fontFamily: fontFamily,
                fontFamilyFallback: fontFallback,
                textTheme: lightTextTheme,
                iconTheme: IconThemeData(color: lightScheme.onSurface),
                appBarTheme: AppBarTheme(
                  foregroundColor: lightScheme.onSurface,
                  iconTheme: IconThemeData(color: lightScheme.onSurface),
                  titleTextStyle: lightTextTheme.titleLarge?.copyWith(
                    color: lightScheme.onSurface,
                    fontFamily: fontFamily,
                    fontFamilyFallback: fontFallback,
                  ),
                ),
                pageTransitionsTheme: const PageTransitionsTheme(
                  builders: {
                    TargetPlatform.android: CupertinoPageTransitionsBuilder(),
                    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                    TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
                    TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
                    TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
                  },
                ),
              ),
              darkTheme: ThemeData(
                colorScheme: darkScheme,
                useMaterial3: true,
                extensions: const <ThemeExtension<dynamic>>[
                  GamepadSkin.dark(),
                ],
                fontFamily: fontFamily,
                fontFamilyFallback: fontFallback,
                textTheme: darkTextTheme,
                iconTheme: IconThemeData(color: darkScheme.onSurface),
                appBarTheme: AppBarTheme(
                  foregroundColor: darkScheme.onSurface,
                  iconTheme: IconThemeData(color: darkScheme.onSurface),
                  titleTextStyle: darkTextTheme.titleLarge?.copyWith(
                    color: darkScheme.onSurface,
                    fontFamily: fontFamily,
                    fontFamilyFallback: fontFallback,
                  ),
                ),
                pageTransitionsTheme: const PageTransitionsTheme(
                  builders: {
                    TargetPlatform.android: CupertinoPageTransitionsBuilder(),
                    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                    TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
                    TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
                    TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
                  },
                ),
              ),
              initialRoute: AppRoutes.home,
              onGenerateRoute: AppRoutes.onGenerateRoute,
            );
          },
        );
      },
    );
  }
}
