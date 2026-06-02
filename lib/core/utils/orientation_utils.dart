// lib/core/utils/orientation_utils.dart
import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart';

class OrientationUtils {
  static const double tabletShortestSide = 600.0;

  static Future<void> setLandscape() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  static Future<void> setPortrait() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  static Future<void> reset() async {
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  static Future<void> setLandscapeOnly() async {
    return setLandscape();
  }

  static Future<void> setPortraitOnly() async {
    return setPortrait();
  }

  static Future<void> setAuto() async {
    return reset();
  }

  static bool isTabletLikeStartupView() {
    final views = PlatformDispatcher.instance.views;
    if (views.isEmpty) return false;

    final view = views.first;
    final shortestSide =
        view.physicalSize.shortestSide / view.devicePixelRatio;
    return shortestSide >= tabletShortestSide;
  }

  static bool shouldStartPortraitOnly() {
    if (!Platform.isIOS) return false;
    return !isTabletLikeStartupView();
  }

  static Future<void> applyStartupOrientation() async {
    if (!Platform.isIOS) return;
    if (shouldStartPortraitOnly()) {
      await setPortraitOnly();
      return;
    }
    await setAuto();
  }

  static Future<void> restoreAfterControl({required bool isTablet}) async {
    return isTablet ? setAuto() : setPortraitOnly();
  }
}
