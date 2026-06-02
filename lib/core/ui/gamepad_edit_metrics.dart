import 'dart:math' as math;

import 'package:flutter/material.dart';

class GamepadEditMetrics {
  static const double safeEdgePad = 12.0;
  static const double safeTopEdgePad = 4.0;
  static const double edgeWarnThresholdPx = 12.0;
  static const double maxPanelUnit = 520.0;
  static const double phoneLandscapeAspect = 844.0 / 390.0;

  static double panelUnit(Size panel) {
    return math.min(panel.width, panel.height).clamp(0.0, maxPanelUnit);
  }

  static double sizePx(Size panel, double sizeFactor) {
    return sizeFactor * panelUnit(panel);
  }

  static double finiteDouble(double? value, double fallback) {
    if (value == null || !value.isFinite) return fallback;
    return value;
  }

  static double clampUnit(double? value, double fallback) {
    return finiteDouble(value, fallback).clamp(0.0, 1.0).toDouble();
  }

  static double maxCircleSizeFactorForPanel(
    Size panel, {
    required double minSize,
    required double maxSize,
    double leftPadding = safeEdgePad,
    double topPadding = safeTopEdgePad,
    double rightPadding = safeEdgePad,
    double bottomPadding = safeEdgePad,
  }) {
    final unit = panelUnit(panel);
    if (unit <= 0) return minSize;
    final usableWidth = math.max(0.0, panel.width - leftPadding - rightPadding);
    final usableHeight = math.max(
      0.0,
      panel.height - topPadding - bottomPadding,
    );
    final cap = math.min(usableWidth, usableHeight) / unit;
    if (!cap.isFinite || cap <= 0) return minSize;
    return math.min(maxSize, cap);
  }

  static double maxScaleForBaseSize(
    Size panel, {
    required double baseSize,
    required double minSize,
    required double maxSize,
    double leftPadding = safeEdgePad,
    double topPadding = safeEdgePad,
    double rightPadding = safeEdgePad,
    double bottomPadding = safeEdgePad,
  }) {
    if (baseSize <= 0 || !baseSize.isFinite) return minSize;
    final usableWidth = math.max(0.0, panel.width - leftPadding - rightPadding);
    final usableHeight = math.max(
      0.0,
      panel.height - topPadding - bottomPadding,
    );
    final cap = math.min(usableWidth, usableHeight) / baseSize;
    if (!cap.isFinite || cap <= 0) return minSize;
    return math.min(maxSize, cap);
  }

  static double safeCenterCoordinate({
    required double value,
    required double extent,
    required double itemExtent,
    required double leadingPadding,
    required double trailingPadding,
  }) {
    final min = leadingPadding + itemExtent / 2;
    final max = extent - trailingPadding - itemExtent / 2;
    if (!min.isFinite || !max.isFinite || max < min) {
      return extent / 2;
    }
    return value.clamp(min, max).toDouble();
  }

  static double fittedCircleDiameter(
    double desiredDiameter,
    Size panel, {
    double leftPadding = safeEdgePad,
    double topPadding = safeEdgePad,
    double rightPadding = safeEdgePad,
    double bottomPadding = safeEdgePad,
  }) {
    if (!desiredDiameter.isFinite || desiredDiameter <= 0) return 0;
    final usableWidth = math.max(0.0, panel.width - leftPadding - rightPadding);
    final usableHeight = math.max(
      0.0,
      panel.height - topPadding - bottomPadding,
    );
    final maxDiameter = math.min(usableWidth, usableHeight);
    if (!maxDiameter.isFinite || maxDiameter <= 0) return desiredDiameter;
    return math.min(desiredDiameter, maxDiameter);
  }

  static Rect defaultLayoutFrame(Size panel) {
    final unit = panelUnit(panel);
    final frameWidth = math.min(panel.width, unit * phoneLandscapeAspect);
    final frameHeight = math.min(panel.height, unit);
    final left = (panel.width - frameWidth) / 2;
    final top = (panel.height - frameHeight) / 2;
    return Rect.fromLTWH(left, top, frameWidth, frameHeight);
  }
}
