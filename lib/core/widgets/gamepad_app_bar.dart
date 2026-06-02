import 'dart:ui';

import 'package:flutter/material.dart';

Color _opacity(Color color, double opacity) =>
    color.withAlpha((opacity * 255).round());

@immutable
class GamepadAppBarMetrics {
  static const double toolbarHeight = 44.0;

  final double toolbarExtent;
  final double controlHeight;
  final double iconButtonExtent;
  final double labelButtonWidth;
  final double controlGap;
  final double sectionGap;
  final EdgeInsets contentPadding;
  final double iconSize;
  final BorderRadius borderRadius;
  final double labelIconGap;
  final double telemetryLabelFontSize;
  final double telemetryValueFontSize;
  final double telemetryValueMaxWidth;

  const GamepadAppBarMetrics({
    required this.toolbarExtent,
    required this.controlHeight,
    required this.iconButtonExtent,
    required this.labelButtonWidth,
    required this.controlGap,
    required this.sectionGap,
    required this.contentPadding,
    required this.iconSize,
    required this.borderRadius,
    required this.labelIconGap,
    required this.telemetryLabelFontSize,
    required this.telemetryValueFontSize,
    required this.telemetryValueMaxWidth,
  });

  factory GamepadAppBarMetrics.forWidth(double width) {
    final wide = width >= 720;
    final expanded = width >= 1024;
    final ultra = width >= 1200;
    final toolbarExtent = expanded ? 60.0 : (wide ? 56.0 : toolbarHeight);
    final controlHeight = expanded ? 44.0 : (wide ? 42.0 : 34.0);

    return GamepadAppBarMetrics(
      toolbarExtent: toolbarExtent,
      controlHeight: controlHeight,
      iconButtonExtent: controlHeight,
      labelButtonWidth: ultra
          ? 126.0
          : (expanded ? 116.0 : (wide ? 108.0 : 88.0)),
      controlGap: expanded ? 9.0 : (wide ? 8.0 : 5.0),
      sectionGap: expanded ? 12.0 : (wide ? 10.0 : 6.0),
      contentPadding: EdgeInsets.symmetric(
        horizontal: expanded ? 12 : (wide ? 11 : 8),
        vertical: wide ? 7 : 5,
      ),
      iconSize: expanded ? 21.0 : (wide ? 20.0 : 16.0),
      borderRadius: BorderRadius.circular(999),
      labelIconGap: expanded ? 7.0 : (wide ? 6.0 : 5.0),
      telemetryLabelFontSize: expanded ? 14.0 : (wide ? 13.0 : 11.0),
      telemetryValueFontSize: expanded ? 14.0 : (wide ? 13.0 : 11.0),
      telemetryValueMaxWidth: ultra
          ? 62.0
          : (expanded ? 58.0 : (wide ? 54.0 : 44.0)),
    );
  }

  double get leadingWidth => iconButtonExtent + sectionGap;

  double get titleSpacing => controlGap;
}

class GamepadUnifiedAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final Widget? leading;
  final Widget? toolbarContent;
  final Widget? speedToggle;
  final Widget? cmdChip;
  final Widget? drvChip;
  final Widget? trnChip;
  final Widget? bleBadge;
  final Widget? flexibleSpace;
  final Widget Function(double gap)? actionsBuilder;
  final List<Widget>? actions;
  final double? actionsMaxWidth;
  final String? title;
  final TextStyle? titleStyle;
  final EdgeInsetsGeometry toolbarPadding;
  final bool centerTitle;
  final bool useGlassBackground;
  final double? toolbarHeight;

  const GamepadUnifiedAppBar({
    super.key,
    this.leading,
    this.toolbarContent,
    this.speedToggle,
    this.cmdChip,
    this.drvChip,
    this.trnChip,
    this.bleBadge,
    this.flexibleSpace,
    this.actionsBuilder,
    this.actions,
    this.actionsMaxWidth,
    this.title,
    this.titleStyle,
    this.toolbarPadding = const EdgeInsets.symmetric(horizontal: 12),
    this.centerTitle = false,
    this.useGlassBackground = true,
    this.toolbarHeight,
  });

  @override
  Size get preferredSize =>
      Size.fromHeight(toolbarHeight ?? GamepadAppBarMetrics.toolbarHeight);

  bool get _hasTelemetry =>
      speedToggle != null ||
      cmdChip != null ||
      drvChip != null ||
      trnChip != null;

  bool get _usesUnifiedControlLayout => _hasTelemetry || bleBadge != null;

  Widget _buildGlassBackground(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final baseColor = isDark
        ? _opacity(const Color(0xFF111827), 0.94)
        : _opacity(
            Color.lerp(const Color(0xFFF8FAFC), cs.surface, 0.55) ?? cs.surface,
            0.97,
          );
    final border = _opacity(
      isDark ? const Color(0xFF38BDF8) : cs.outline,
      isDark ? 0.28 : 0.16,
    );
    final topLine = _opacity(Colors.white, isDark ? 0.1 : 0.45);
    final bottomLine = _opacity(
      isDark ? const Color(0xFF38BDF8) : cs.outline,
      isDark ? 0.32 : 0.18,
    );

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: baseColor,
            border: Border(
              top: BorderSide(color: topLine, width: 0.8),
              bottom: BorderSide(color: border, width: 0.9),
            ),
            boxShadow: [
              BoxShadow(
                color: _opacity(Colors.black, isDark ? 0.24 : 0.08),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(height: 1, color: bottomLine),
          ),
        ),
      ),
    );
  }

  Widget? _buildTelemetryRow(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final metrics = GamepadAppBarMetrics.forWidth(width);

    final chipWidgets = <Widget>[
      if (cmdChip != null) cmdChip!,
      if (drvChip != null) drvChip!,
      if (trnChip != null) trnChip!,
    ];

    final telemetryChildren = <Widget>[
      if (speedToggle != null) speedToggle!,
      if (speedToggle != null && chipWidgets.isNotEmpty)
        SizedBox(width: metrics.controlGap),
      for (int i = 0; i < chipWidgets.length; i++) ...[
        SizedBox(child: chipWidgets[i]),
        if (i != chipWidgets.length - 1) SizedBox(width: metrics.controlGap),
      ],
    ];

    if (telemetryChildren.isEmpty) {
      return null;
    }

    return Row(mainAxisSize: MainAxisSize.min, children: telemetryChildren);
  }

  Widget? _buildTrailingControls(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final metrics = GamepadAppBarMetrics.forWidth(width);
    final trailingChildren = <Widget>[if (bleBadge != null) bleBadge!];

    final builtActions = actionsBuilder != null
        ? actionsBuilder!(metrics.controlGap)
        : (actions != null && actions!.isNotEmpty
              ? Row(mainAxisSize: MainAxisSize.min, children: actions!)
              : null);

    if (builtActions != null) {
      if (trailingChildren.isNotEmpty) {
        trailingChildren.add(SizedBox(width: metrics.controlGap));
      }
      trailingChildren.add(builtActions);
    }

    if (trailingChildren.isEmpty) {
      return null;
    }

    return Row(mainAxisSize: MainAxisSize.min, children: trailingChildren);
  }

  Widget _buildUnifiedToolbar(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final metrics = GamepadAppBarMetrics.forWidth(width);
    final telemetryRow = _buildTelemetryRow(context);
    final trailingControls = _buildTrailingControls(context);
    final combinedChildren = <Widget>[
      if (telemetryRow != null) telemetryRow,
      if (telemetryRow != null && trailingControls != null)
        SizedBox(width: metrics.sectionGap),
      if (trailingControls != null) trailingControls,
    ];

    return SizedBox(
      height: metrics.controlHeight,
      child: Padding(
        padding: EdgeInsets.only(right: metrics.sectionGap),
        child: Align(
          alignment: telemetryRow != null && trailingControls != null
              ? Alignment.center
              : Alignment.centerLeft,
          child: combinedChildren.isEmpty
              ? const SizedBox.shrink()
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: telemetryRow != null && trailingControls != null
                      ? Alignment.center
                      : Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: combinedChildren,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildStandardTitle(BuildContext context) {
    if (_hasTelemetry) {
      final telemetryRow = _buildTelemetryRow(context);
      return telemetryRow == null
          ? const SizedBox.shrink()
          : FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: telemetryRow,
            );
    }
    if (title != null && title!.trim().isNotEmpty) {
      return Text(title!, style: titleStyle);
    }
    return const SizedBox.shrink();
  }

  List<Widget> _buildStandardActions(BuildContext context) {
    if (actionsBuilder != null) {
      final width = MediaQuery.of(context).size.width;
      final metrics = GamepadAppBarMetrics.forWidth(width);
      final maxWidth =
          actionsMaxWidth ?? (width < 640 ? width * 0.42 : width * 0.48);
      final actionsWidget = actionsBuilder!(metrics.controlGap);
      return [
        Padding(
          padding: EdgeInsets.only(right: metrics.sectionGap),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: actionsWidget,
            ),
          ),
        ),
      ];
    }
    return actions ?? const [];
  }

  Widget _buildTitleWidget(BuildContext context) {
    if (toolbarContent != null) {
      return Padding(padding: toolbarPadding, child: toolbarContent);
    }
    if (_usesUnifiedControlLayout) {
      return _buildUnifiedToolbar(context);
    }
    return _buildStandardTitle(context);
  }

  List<Widget> _buildActions(BuildContext context) {
    if (toolbarContent != null) {
      return const [];
    }
    if (_usesUnifiedControlLayout) {
      return const [];
    }
    return _buildStandardActions(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final metrics = GamepadAppBarMetrics.forWidth(
      MediaQuery.of(context).size.width,
    );
    final resolvedToolbarHeight =
        toolbarHeight ?? GamepadAppBarMetrics.toolbarHeight;
    final flexSpace =
        flexibleSpace ??
        (useGlassBackground ? _buildGlassBackground(context) : null);

    return AppBar(
      automaticallyImplyLeading: false,
      toolbarHeight: resolvedToolbarHeight,
      elevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      foregroundColor: cs.onSurface,
      centerTitle: centerTitle,
      titleSpacing: toolbarContent == null ? metrics.titleSpacing : 0,
      flexibleSpace: flexSpace,
      leading: leading,
      leadingWidth: leading != null ? metrics.leadingWidth : null,
      title: _buildTitleWidget(context),
      actions: _buildActions(context),
    );
  }
}
