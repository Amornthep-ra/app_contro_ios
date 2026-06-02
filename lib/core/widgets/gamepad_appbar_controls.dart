import 'package:flutter/material.dart';

import 'app_back_button.dart';
import 'gamepad_app_bar.dart';

Color _opacity(Color color, double opacity) =>
    color.withAlpha((opacity * 255).round());

class GamepadGlassTopPill extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Key? pillKey;
  final EdgeInsets padding;

  const GamepadGlassTopPill({
    super.key,
    required this.child,
    this.onTap,
    this.pillKey,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final metrics = GamepadAppBarMetrics.forWidth(
      MediaQuery.of(context).size.width,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: pillKey,
        borderRadius: BorderRadius.circular(999),
        overlayColor: WidgetStatePropertyAll(
          _opacity(cs.primary, isDark ? 0.10 : 0.06),
        ),
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: metrics.controlHeight),
          height: metrics.controlHeight,
          padding: padding,
          decoration: BoxDecoration(
            color: _opacity(
              isDark ? const Color(0xFF0F172A) : Colors.white,
              isDark ? 0.88 : 0.84,
            ),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: _opacity(
                isDark ? const Color(0xFF38BDF8) : cs.outline,
                isDark ? 0.24 : 0.20,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: _opacity(Colors.black, isDark ? 0.22 : 0.06),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class GamepadActionPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;
  final Key? pillKey;
  final bool iconOnly;
  final bool compact;

  const GamepadActionPill({
    super.key,
    required this.label,
    required this.icon,
    required this.accent,
    required this.onTap,
    this.pillKey,
    this.iconOnly = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final enabled = onTap != null;
    final metrics = GamepadAppBarMetrics.forWidth(
      MediaQuery.of(context).size.width,
    );
    final wide = metrics.controlHeight >= 42;
    final horizontalPadding = compact
        ? (iconOnly ? (wide ? 10.0 : 8.0) : (wide ? 12.0 : 10.0))
        : (iconOnly ? (wide ? 12.0 : 10.0) : (wide ? 14.0 : 12.0));
    final iconSize = compact
        ? (wide ? metrics.iconSize - 4 : 13.0)
        : (wide ? metrics.iconSize - 3 : 14.0);
    final iconOnlySize = compact
        ? (wide ? metrics.iconSize - 2 : 15.0)
        : (wide ? metrics.iconSize : 16.0);
    final fontSize = compact
        ? (wide ? metrics.telemetryLabelFontSize - 1 : 10.0)
        : (wide ? metrics.telemetryLabelFontSize : 11.0);
    final gap = compact ? (wide ? 6.0 : 5.0) : (wide ? 8.0 : 6.0);
    final textColor =
        Color.lerp(
          accent,
          isDark ? Colors.white : theme.colorScheme.onSurface,
          0.4,
        ) ??
        Colors.white;

    return Opacity(
      opacity: enabled ? 1 : 0.46,
      child: GamepadGlassTopPill(
        pillKey: pillKey,
        onTap: onTap,
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: 0,
        ),
        child: iconOnly
            ? Icon(icon, size: iconOnlySize, color: accent)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: iconSize, color: accent),
                  SizedBox(width: gap),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class GamepadAppBarActionItem {
  final Key? key;
  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;
  final bool iconOnly;
  final bool compact;
  final bool compactOnNarrow;

  const GamepadAppBarActionItem({
    this.key,
    required this.label,
    required this.icon,
    required this.accent,
    required this.onTap,
    this.iconOnly = false,
    this.compact = false,
    this.compactOnNarrow = true,
  });
}

class GamepadAppBarActionGroup extends StatelessWidget {
  final List<GamepadAppBarActionItem> items;
  final double gap;
  final double compactBreakpoint;

  const GamepadAppBarActionGroup({
    super.key,
    required this.items,
    required this.gap,
    this.compactBreakpoint = 720,
  });

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < compactBreakpoint;
    final children = <Widget>[
      for (final item in items)
        Tooltip(
          message: item.label,
          child: GamepadActionPill(
            pillKey: item.key,
            label: item.label,
            icon: item.icon,
            accent: item.accent,
            onTap: item.onTap,
            iconOnly: item.iconOnly || (isNarrow && item.compactOnNarrow),
            compact: item.compact || isNarrow,
          ),
        ),
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < children.length; i++) ...[
          children[i],
          if (i != children.length - 1) SizedBox(width: gap),
        ],
      ],
    );
  }
}

class GamepadAppBarBackButton extends StatelessWidget {
  final Key? buttonKey;
  final VoidCallback onPressed;
  final GamepadAppBarMetrics? metrics;

  const GamepadAppBarBackButton({
    super.key,
    this.buttonKey,
    required this.onPressed,
    this.metrics,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedMetrics =
        metrics ??
        GamepadAppBarMetrics.forWidth(MediaQuery.of(context).size.width);

    return AppBackButton(
      buttonKey: buttonKey,
      width: resolvedMetrics.iconButtonExtent,
      height: resolvedMetrics.controlHeight,
      iconSize: resolvedMetrics.iconSize + 13,
      borderRadius: BorderRadius.circular(resolvedMetrics.iconButtonExtent / 2),
      onPressed: onPressed,
    );
  }
}

class GamepadSpeedTogglePill extends StatelessWidget {
  final Key? pillKey;
  final bool expanded;
  final VoidCallback onTap;
  final Color accent;
  final String label;

  const GamepadSpeedTogglePill({
    super.key,
    this.pillKey,
    required this.expanded,
    required this.onTap,
    required this.accent,
    this.label = 'SPD',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final metrics = GamepadAppBarMetrics.forWidth(
      MediaQuery.of(context).size.width,
    );
    final textColor =
        Color.lerp(
          accent,
          isDark ? Colors.white : theme.colorScheme.onSurface,
          0.35,
        ) ??
        Colors.white;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: GamepadGlassTopPill(
        pillKey: pillKey,
        onTap: onTap,
        padding: EdgeInsets.symmetric(
          horizontal: metrics.controlHeight >= 42 ? 14 : 12,
          vertical: 0,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.speed_rounded,
              size: metrics.iconSize - 2,
              color: accent,
            ),
            SizedBox(width: metrics.labelIconGap),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: metrics.controlHeight >= 42 ? 82 : 64,
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: metrics.telemetryLabelFontSize,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                ),
              ),
            ),
            SizedBox(width: metrics.controlHeight >= 42 ? 6 : 4),
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: metrics.iconSize - 2,
              color: textColor,
            ),
          ],
        ),
      ),
    );
  }
}

class GamepadToolIconPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback? onTap;
  final Key? pillKey;
  final bool active;

  const GamepadToolIconPill({
    super.key,
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
    this.pillKey,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final enabled = onTap != null;
    final fallback = isDark
        ? Colors.white38
        : theme.colorScheme.onSurface.withAlpha((0.35 * 255).round());
    final iconColor = enabled
        ? (active
              ? accent
              : (Color.lerp(
                      accent,
                      isDark ? Colors.white : theme.colorScheme.onSurface,
                      0.28,
                    ) ??
                    accent))
        : fallback;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: GamepadGlassTopPill(
        pillKey: pillKey,
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: iconColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: iconColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GamepadSizeToolPill extends StatelessWidget {
  final Key? pillKey;
  final bool isThai;
  final bool enabled;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;

  const GamepadSizeToolPill({
    super.key,
    this.pillKey,
    required this.isThai,
    required this.enabled,
    this.onDecrease,
    this.onIncrease,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const accent = Color(0xFF38BDF8);
    final fallback = isDark
        ? Colors.white38
        : theme.colorScheme.onSurface.withAlpha((0.35 * 255).round());
    final color = enabled
        ? (Color.lerp(
                accent,
                isDark ? Colors.white : theme.colorScheme.onSurface,
                0.32,
              ) ??
              accent)
        : fallback;

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: GamepadGlassTopPill(
        pillKey: pillKey,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isThai ? 'ขนาด' : 'Size',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled ? onDecrease : null,
              child: Padding(
                padding: const EdgeInsets.all(1),
                child: Icon(Icons.remove, size: 14, color: color),
              ),
            ),
            const SizedBox(width: 2),
            InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled ? onIncrease : null,
              child: Padding(
                padding: const EdgeInsets.all(1),
                child: Icon(Icons.add, size: 14, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
