import 'package:flutter/material.dart';

@immutable
class AdaptivePageMetrics {
  final bool isTablet;
  final bool expanded;
  final double contentMaxWidth;
  final EdgeInsets pagePadding;
  final double toolbarHeight;
  final double titleSize;
  final double backButtonSize;
  final double backIconSize;
  final double sectionGap;
  final double cardGap;
  final double cardRadius;
  final double cardPadding;
  final double iconBoxSize;
  final double iconSize;
  final double bodyFontSize;
  final double labelFontSize;
  final double buttonHeight;

  const AdaptivePageMetrics({
    required this.isTablet,
    required this.expanded,
    required this.contentMaxWidth,
    required this.pagePadding,
    required this.toolbarHeight,
    required this.titleSize,
    required this.backButtonSize,
    required this.backIconSize,
    required this.sectionGap,
    required this.cardGap,
    required this.cardRadius,
    required this.cardPadding,
    required this.iconBoxSize,
    required this.iconSize,
    required this.bodyFontSize,
    required this.labelFontSize,
    required this.buttonHeight,
  });

  factory AdaptivePageMetrics.forWidth(double width) {
    if (width >= 720) {
      final expanded = width >= 1024;
      return AdaptivePageMetrics(
        isTablet: true,
        expanded: expanded,
        contentMaxWidth: expanded ? 1160 : 920,
        pagePadding: EdgeInsets.fromLTRB(
          expanded ? 28 : 24,
          expanded ? 24 : 20,
          expanded ? 28 : 24,
          32,
        ),
        toolbarHeight: expanded ? 60 : 56,
        titleSize: expanded ? 22 : 20,
        backButtonSize: expanded ? 52 : 48,
        backIconSize: expanded ? 34 : 32,
        sectionGap: expanded ? 22 : 18,
        cardGap: expanded ? 16 : 14,
        cardRadius: expanded ? 22 : 20,
        cardPadding: expanded ? 20 : 18,
        iconBoxSize: expanded ? 52 : 48,
        iconSize: expanded ? 30 : 28,
        bodyFontSize: expanded ? 16 : 15,
        labelFontSize: expanded ? 14 : 13,
        buttonHeight: expanded ? 54 : 50,
      );
    }

    return const AdaptivePageMetrics(
      isTablet: false,
      expanded: false,
      contentMaxWidth: double.infinity,
      pagePadding: EdgeInsets.fromLTRB(16, 16, 16, 24),
      toolbarHeight: 44,
      titleSize: 18,
      backButtonSize: 44,
      backIconSize: 30,
      sectionGap: 12,
      cardGap: 12,
      cardRadius: 16,
      cardPadding: 16,
      iconBoxSize: 44,
      iconSize: 28,
      bodyFontSize: 14,
      labelFontSize: 12,
      buttonHeight: 48,
    );
  }
}
