// lib/features/controller/controller_home_page.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ble/ble_manager.dart';
import '../../core/routes/app_routes.dart';
import '../../core/ui/language_controller.dart';
import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/gamepad_app_bar.dart';
import '../gamepad/gamepad_4_button_page.dart';
import '../gamepad/gamepad_mode_edit.dart';
import '../info/info_page.dart';
import '../joystick/joystick/presentation/joystick.dart';

class ControllerHomePage extends StatefulWidget {
  const ControllerHomePage({super.key});

  @override
  State<ControllerHomePage> createState() => _ControllerHomePageState();
}

class _ControllerHomePageState extends State<ControllerHomePage> {
  StreamSubscription<bool>? _connSub;
  bool _connected = false;
  bool _openingMode = false;
  bool _reconnecting = false;

  @override
  void initState() {
    super.initState();
    _connected = BleManager.instance.isConnected;
    _connSub = BleManager.instance.connectionStream.listen((connected) {
      if (!mounted) return;
      setState(() => _connected = connected);
    });
  }

  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }

  String _connectedName() {
    final name = BleManager.instance.currentDeviceName;
    if (name != null && name.isNotEmpty) return name;
    final id = BleManager.instance.currentDeviceId;
    if (id != null && id.isNotEmpty) return id;
    return 'Unknown';
  }

  Future<void> _openMode(_ControlMenuItem item) async {
    if (_openingMode) return;
    setState(() => _openingMode = true);
    HapticFeedback.selectionClick();
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => item.page),
      );
    } finally {
      if (mounted) {
        setState(() => _openingMode = false);
      }
    }
  }

  Future<void> _reconnectLastDevice() async {
    if (_reconnecting || _connected) return;
    setState(() => _reconnecting = true);
    HapticFeedback.selectionClick();
    try {
      await BleManager.instance.autoConnectLastDevice(
        source: 'control_modes_reconnect',
      );
    } finally {
      if (mounted) {
        setState(() => _reconnecting = false);
      }
    }
  }

  Widget _buildReconnectChild(bool isThai) {
    final label = _reconnecting
        ? (isThai ? 'เชื่อมต่อ...' : 'Connecting...')
        : (isThai ? 'เชื่อมต่ออีกครั้ง' : 'Reconnect');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_reconnecting) ...[
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 6),
        ],
        Text(label),
      ],
    );
  }

  void _handleBack() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    navigator.pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
  }

  Widget _buildPlainBackButton() {
    final metrics = GamepadAppBarMetrics.forWidth(
      MediaQuery.of(context).size.width,
    );
    return AppBackButton(
      width: metrics.iconButtonExtent,
      height: metrics.controlHeight,
      iconSize: metrics.iconSize + 12,
      onPressed: _handleBack,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: LanguageController.isThai,
      builder: (context, isThai, _) {
        final items = _modeItems(isThai);
        final scheme = Theme.of(context).colorScheme;
        final appBarMetrics = GamepadAppBarMetrics.forWidth(
          MediaQuery.of(context).size.width,
        );

        return Scaffold(
          appBar: GamepadUnifiedAppBar(
            toolbarHeight: appBarMetrics.toolbarExtent,
            leading: _buildPlainBackButton(),
            title: isThai ? 'โหมดการควบคุม' : 'Control Modes',
            centerTitle: true,
            titleStyle: TextStyle(
              fontSize: appBarMetrics.toolbarExtent >= 60
                  ? 22
                  : (appBarMetrics.toolbarExtent >= 56 ? 20 : 18),
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
              color: scheme.onSurface,
            ),
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final metrics = _ControlModesMetrics.forWidth(
                constraints.maxWidth,
              );

              return SingleChildScrollView(
                padding: metrics.pagePadding,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: metrics.contentMaxWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildConnectionBar(context, isThai, metrics),
                        SizedBox(height: metrics.sectionGap),
                        _buildModeGrid(context, items, metrics),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  List<_ControlMenuItem> _modeItems(bool isThai) {
    return [
      _ControlMenuItem(
        title: isThai ? 'Gamepad Mode Edit' : 'Gamepad Mode Edit',
        subtitle: isThai
            ? 'ควบคุม 8 ปุ่ม ปรับแต่งตำแหน่งได้'
            : '8-button layout with editable controls',
        iconBuilder: (_, size) => _ControlModeAssetIcon(
          assetPath: 'assets/icons/control_mode_gamepad_8.png',
          size: size,
        ),
        accent: const Color(0xFF8B5CF6),
        page: const GamepadModeEdit(),
      ),
      _ControlMenuItem(
        title: isThai ? 'Gamepad (4 Buttons)' : 'Gamepad (4 Buttons)',
        subtitle: isThai
            ? 'ควบคุมทิศทางแบบ 4 ปุ่ม'
            : 'Simple 4-button directional control',
        iconBuilder: (_, size) => _ControlModeAssetIcon(
          assetPath: 'assets/icons/control_mode_gamepad_4.png',
          size: size,
        ),
        accent: const Color(0xFF3B82F6),
        page: const Gamepad4ButtonPage(),
      ),
      _ControlMenuItem(
        title: isThai ? 'Joystick Mode' : 'Joystick Mode',
        subtitle: isThai
            ? 'ควบคุมด้วยสติ๊กอิสระ'
            : 'Free-form analog stick control',
        iconBuilder: (_, size) => _ControlModeAssetIcon(
          assetPath: 'assets/icons/control_mode_joystick.png',
          size: size,
        ),
        accent: const Color(0xFF6D28D9),
        page: const JoystickPage(),
      ),
      _ControlMenuItem(
        title: isThai ? 'คู่มือ' : 'Guide',
        subtitle: isThai ? 'วิธีใช้งานและการตั้งค่า' : 'Usage and setup guide',
        iconBuilder: (_, size) => _ControlModeAssetIcon(
          assetPath: 'assets/icons/control_mode_guide.png',
          size: size,
        ),
        accent: const Color(0xFF06B6D4),
        page: const InfoPage(),
      ),
    ];
  }

  Widget _buildConnectionBar(
    BuildContext context,
    bool isThai,
    _ControlModesMetrics metrics,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final connected = _connected;
    final statusColor = connected ? const Color(0xFF22C55E) : scheme.error;
    final text = connected
        ? (isThai
              ? 'เชื่อมต่ออยู่กับ: ${_connectedName()}'
              : 'Connected to: ${_connectedName()}')
        : (isThai ? 'ยังไม่ได้เชื่อมต่อ' : 'Not connected');

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(metrics.connectionRadius),
      ),
      child: Padding(
        padding: metrics.connectionPadding,
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              width: metrics.statusDotSize,
              height: metrics.statusDotSize,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            SizedBox(width: metrics.statusGap),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: Text(
                  text,
                  key: ValueKey<String>(text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: metrics.connectionFontSize,
                    fontWeight: FontWeight.w600,
                    color: connected ? scheme.onSurface : scheme.error,
                  ),
                ),
              ),
            ),
            if (!connected)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: FilledButton.tonal(
                  key: ValueKey<bool>(_reconnecting),
                  onPressed: _reconnecting ? null : _reconnectLastDevice,
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: metrics.reconnectPadding,
                    textStyle: TextStyle(
                      fontSize: metrics.reconnectFontSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: _buildReconnectChild(isThai),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeGrid(
    BuildContext context,
    List<_ControlMenuItem> items,
    _ControlModesMetrics metrics,
  ) {
    if (metrics.columns == 1) {
      return Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            SizedBox(
              width: double.infinity,
              child: _ControlMenuCard(
                item: items[i],
                metrics: metrics,
                enabled: !_openingMode,
                onTap: () => _openMode(items[i]),
              ),
            ),
            if (i != items.length - 1) SizedBox(height: metrics.cardGap),
          ],
        ],
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: metrics.columns,
        mainAxisSpacing: metrics.cardGap,
        crossAxisSpacing: metrics.cardGap,
        mainAxisExtent: metrics.cardHeight,
      ),
      itemBuilder: (context, index) {
        return _ControlMenuCard(
          item: items[index],
          metrics: metrics,
          enabled: !_openingMode,
          onTap: () => _openMode(items[index]),
        );
      },
    );
  }
}

@immutable
class _ControlModesMetrics {
  final int columns;
  final double contentMaxWidth;
  final EdgeInsets pagePadding;
  final double sectionGap;
  final double cardGap;
  final double cardHeight;
  final EdgeInsets cardPadding;
  final double cardRadius;
  final double iconBoxSize;
  final double iconGlowSize;
  final double iconSize;
  final double titleFontSize;
  final double subtitleFontSize;
  final double chevronSize;
  final double titleGap;
  final double subtitleGap;
  final EdgeInsets connectionPadding;
  final double connectionRadius;
  final double statusDotSize;
  final double statusGap;
  final double connectionFontSize;
  final EdgeInsets reconnectPadding;
  final double reconnectFontSize;

  const _ControlModesMetrics({
    required this.columns,
    required this.contentMaxWidth,
    required this.pagePadding,
    required this.sectionGap,
    required this.cardGap,
    required this.cardHeight,
    required this.cardPadding,
    required this.cardRadius,
    required this.iconBoxSize,
    required this.iconGlowSize,
    required this.iconSize,
    required this.titleFontSize,
    required this.subtitleFontSize,
    required this.chevronSize,
    required this.titleGap,
    required this.subtitleGap,
    required this.connectionPadding,
    required this.connectionRadius,
    required this.statusDotSize,
    required this.statusGap,
    required this.connectionFontSize,
    required this.reconnectPadding,
    required this.reconnectFontSize,
  });

  factory _ControlModesMetrics.forWidth(double width) {
    if (width >= 720) {
      final expanded = width >= 1024;
      return _ControlModesMetrics(
        columns: 2,
        contentMaxWidth: expanded ? 1160 : 920,
        pagePadding: EdgeInsets.fromLTRB(
          expanded ? 28 : 24,
          expanded ? 24 : 20,
          expanded ? 28 : 24,
          32,
        ),
        sectionGap: expanded ? 22 : 18,
        cardGap: expanded ? 18 : 16,
        cardHeight: expanded ? 168 : 154,
        cardPadding: EdgeInsets.fromLTRB(
          expanded ? 24 : 20,
          expanded ? 22 : 18,
          expanded ? 22 : 20,
          expanded ? 20 : 18,
        ),
        cardRadius: expanded ? 20 : 18,
        iconBoxSize: expanded ? 60 : 54,
        iconGlowSize: expanded ? 34 : 30,
        iconSize: expanded ? 52 : 46,
        titleFontSize: expanded ? 20 : 18,
        subtitleFontSize: expanded ? 16 : 15,
        chevronSize: expanded ? 30 : 28,
        titleGap: expanded ? 16 : 14,
        subtitleGap: expanded ? 18 : 14,
        connectionPadding: EdgeInsets.symmetric(
          horizontal: expanded ? 22 : 18,
          vertical: expanded ? 16 : 14,
        ),
        connectionRadius: expanded ? 22 : 20,
        statusDotSize: expanded ? 11 : 10,
        statusGap: expanded ? 14 : 12,
        connectionFontSize: expanded ? 16 : 15,
        reconnectPadding: EdgeInsets.symmetric(
          horizontal: expanded ? 18 : 16,
          vertical: expanded ? 10 : 8,
        ),
        reconnectFontSize: expanded ? 15 : 14,
      );
    }

    return const _ControlModesMetrics(
      columns: 1,
      contentMaxWidth: double.infinity,
      pagePadding: EdgeInsets.fromLTRB(16, 12, 16, 24),
      sectionGap: 14,
      cardGap: 10,
      cardHeight: 108,
      cardPadding: EdgeInsets.fromLTRB(14, 12, 14, 12),
      cardRadius: 12,
      iconBoxSize: 42,
      iconGlowSize: 24,
      iconSize: 40,
      titleFontSize: 16,
      subtitleFontSize: 13,
      chevronSize: 22,
      titleGap: 10,
      subtitleGap: 10,
      connectionPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      connectionRadius: 16,
      statusDotSize: 8,
      statusGap: 8,
      connectionFontSize: 13,
      reconnectPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      reconnectFontSize: 12,
    );
  }
}

class _ControlMenuItem {
  final String title;
  final String subtitle;
  final Widget Function(Color accent, double size) iconBuilder;
  final Color accent;
  final Widget page;

  const _ControlMenuItem({
    required this.title,
    required this.subtitle,
    required this.iconBuilder,
    required this.accent,
    required this.page,
  });
}

class _ControlMenuCard extends StatefulWidget {
  final _ControlMenuItem item;
  final _ControlModesMetrics metrics;
  final bool enabled;
  final VoidCallback onTap;

  const _ControlMenuCard({
    required this.item,
    required this.metrics,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_ControlMenuCard> createState() => _ControlMenuCardState();
}

class _ControlMenuCardState extends State<_ControlMenuCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = widget.item.accent;
    final metrics = widget.metrics;
    final glowColor = accent.withAlpha(isDark ? 74 : 44);
    final glowBlur =
        (isDark ? 13.0 : 9.0) * (metrics.iconBoxSize / 42).clamp(1.0, 1.45);
    final glowSpread = isDark ? 1.0 : 0.0;

    final gradient = LinearGradient(
      colors: [accent.withAlpha(20), accent.withAlpha(7)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return AnimatedScale(
      scale: _pressed && widget.enabled ? 0.98 : 1.0,
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        opacity: widget.enabled ? 1.0 : 0.62,
        duration: const Duration(milliseconds: 120),
        child: Card(
          margin: EdgeInsets.zero,
          elevation: 1,
          shadowColor: accent.withAlpha(32),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(metrics.cardRadius),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(metrics.cardRadius),
            onTap: widget.enabled ? widget.onTap : null,
            onTapDown: widget.enabled ? (_) => _setPressed(true) : null,
            onTapCancel: () => _setPressed(false),
            onTapUp: (_) => _setPressed(false),
            child: Ink(
              height: metrics.cardHeight,
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(metrics.cardRadius),
                border: Border.all(
                  color: scheme.outlineVariant.withAlpha(80),
                  width: 0.8,
                ),
              ),
              child: Padding(
                padding: metrics.cardPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: metrics.iconBoxSize,
                          height: metrics.iconBoxSize,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: glowColor,
                                      blurRadius: glowBlur,
                                      spreadRadius: glowSpread,
                                    ),
                                  ],
                                ),
                                child: SizedBox(
                                  width: metrics.iconGlowSize,
                                  height: metrics.iconGlowSize,
                                ),
                              ),
                              widget.item.iconBuilder(accent, metrics.iconSize),
                            ],
                          ),
                        ),
                        SizedBox(width: metrics.titleGap),
                        Expanded(
                          child: Text(
                            widget.item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: metrics.titleFontSize,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        SizedBox(width: metrics.titleGap * 0.6),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: metrics.chevronSize,
                          color: accent.withAlpha(isDark ? 150 : 120),
                        ),
                      ],
                    ),
                    SizedBox(height: metrics.subtitleGap),
                    Flexible(
                      child: Text(
                        widget.item.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: metrics.subtitleFontSize,
                          height: 1.25,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ControlModeAssetIcon extends StatelessWidget {
  final String assetPath;
  final double size;

  const _ControlModeAssetIcon({required this.assetPath, required this.size});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}
