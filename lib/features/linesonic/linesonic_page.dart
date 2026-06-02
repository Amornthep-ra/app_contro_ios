// lib/features/linesonic/linesonic_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ble/ble_manager.dart';
import '../../core/ui/adaptive_page_metrics.dart';
import '../../core/ui/language_controller.dart';
import '../bluetooth/bluetooth_ble_page.dart';
import 'linesonic_pid_page.dart';
import 'linesonic_sensor_page.dart';

class LineSonicPage extends StatefulWidget {
  const LineSonicPage({super.key});

  @override
  State<LineSonicPage> createState() => _LineSonicPageState();
}

class _LineSonicPageState extends State<LineSonicPage> {
  bool _openingPage = false;
  bool _openingBlePage = false;

  String _t(bool isThai, String th, String en) => isThai ? th : en;

  Widget _lineSonicIcon(String name, {double size = 28}) {
    return Image.asset(
      'assets/icons/HomeUnified/$name',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }

  Widget _buildPlainBackButton(bool isThai) {
    final metrics = AdaptivePageMetrics.forWidth(
      MediaQuery.of(context).size.width,
    );
    return SizedBox(
      width: metrics.backButtonSize,
      height: metrics.backButtonSize,
      child: IconButton(
        tooltip: _t(isThai, 'กลับ', 'Back'),
        icon: Icon(Icons.chevron_left_rounded, size: metrics.backIconSize),
        onPressed: () {
          HapticFeedback.selectionClick();
          Navigator.maybePop(context);
        },
        padding: EdgeInsets.zero,
        splashRadius: 22,
      ),
    );
  }

  Future<void> _openBlePage() async {
    if (_openingBlePage) return;
    _openingBlePage = true;
    HapticFeedback.selectionClick();
    try {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const BluetoothBlePage()));
    } finally {
      _openingBlePage = false;
    }
  }

  Widget _buildBleBadge(bool isThai) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final metrics = AdaptivePageMetrics.forWidth(
      MediaQuery.of(context).size.width,
    );

    return StreamBuilder<BleConnectionStatus>(
      stream: BleManager.instance.statusStream,
      initialData: BleManager.instance.connectionStatus,
      builder: (context, snapshot) {
        final status = snapshot.data ?? BleConnectionStatus.disconnected;
        final connected = status == BleConnectionStatus.connected;
        final reconnecting = status == BleConnectionStatus.reconnecting;
        final failed = status == BleConnectionStatus.reconnectFailed;
        final accent = connected
            ? const Color(0xFF16A34A)
            : reconnecting
            ? const Color(0xFFF59E0B)
            : failed
            ? const Color(0xFFDC2626)
            : const Color(0xFFEF4444);
        final icon = connected
            ? Icons.bluetooth_connected_rounded
            : reconnecting
            ? Icons.bluetooth_searching_rounded
            : Icons.bluetooth_disabled_rounded;
        final label = connected
            ? 'BLE On'
            : reconnecting
            ? 'Reconnecting...'
            : failed
            ? 'Failed'
            : 'BLE Off';

        return Padding(
          padding: EdgeInsets.only(right: metrics.isTablet ? 18 : 12),
          child: Tooltip(
            message: _t(
              isThai,
              'เปิดหน้าการเชื่อมต่อ BLE',
              'Open BLE connection',
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: _openBlePage,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  height: metrics.isTablet ? 42 : 34,
                  constraints: BoxConstraints(
                    maxWidth: metrics.isTablet ? 150 : 112,
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: metrics.isTablet ? 12 : 8,
                  ),
                  decoration: BoxDecoration(
                    color: Color.lerp(
                      scheme.surface,
                      accent,
                      isDark ? 0.18 : 0.09,
                    ),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color:
                          Color.lerp(
                            scheme.outlineVariant,
                            accent,
                            isDark ? 0.42 : 0.32,
                          ) ??
                          scheme.outlineVariant,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: metrics.isTablet ? 20 : 15,
                        color: accent,
                      ),
                      SizedBox(width: metrics.isTablet ? 6 : 4),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: metrics.isTablet ? 14 : 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                            color:
                                Color.lerp(
                                  accent,
                                  scheme.onSurface,
                                  isDark ? 0.25 : 0.42,
                                ) ??
                                scheme.onSurface,
                          ),
                        ),
                      ),
                      SizedBox(width: metrics.isTablet ? 6 : 4),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: accent.withAlpha(90),
                              blurRadius: 6,
                              spreadRadius: 0.5,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openPage(Widget page) async {
    if (_openingPage) return;
    setState(() => _openingPage = true);
    HapticFeedback.selectionClick();
    try {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    } finally {
      if (mounted) {
        setState(() => _openingPage = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: LanguageController.isThai,
      builder: (context, isThai, _) {
        final scheme = Theme.of(context).colorScheme;
        final metrics = AdaptivePageMetrics.forWidth(
          MediaQuery.of(context).size.width,
        );
        final items = [
          _LineSonicItem(
            title: _t(isThai, 'ปรับค่า PID', 'PID Tuning'),
            subtitle: _t(
              isThai,
              'ปรับค่า PID การเคลื่อนที่ผ่าน BLE',
              'Tune motion PID over BLE',
            ),
            iconAsset: 'LineSonic-PID Tuning.png',
            page: const LineSonicPidPage(),
          ),
          _LineSonicItem(
            title: _t(isThai, 'อ่านเซนเซอร์', 'Read Sensor'),
            subtitle: _t(
              isThai,
              'อ่านค่าจากเซนเซอร์บนบอร์ด',
              'Read sensor values from board',
            ),
            iconAsset: 'LineSonic-Read Sensor.png',
            page: const LineSonicSensorPage(),
          ),
        ];

        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            toolbarHeight: metrics.toolbarHeight,
            elevation: 0,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: scheme.onSurface,
            leading: Navigator.of(context).canPop()
                ? _buildPlainBackButton(isThai)
                : null,
            centerTitle: true,
            title: Text(
              'LineSonic',
              style: TextStyle(
                fontSize: metrics.titleSize,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
                color: scheme.onSurface,
              ),
            ),
            actions: [_buildBleBadge(isThai)],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: metrics.contentMaxWidth),
              child: ListView.separated(
                padding: metrics.pagePadding,
                itemCount: items.length,
                separatorBuilder: (_, __) => SizedBox(height: metrics.cardGap),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _LineSonicCard(
                    item: item,
                    metrics: metrics,
                    enabled: !_openingPage,
                    iconBuilder: _lineSonicIcon,
                    onTap: () => _openPage(item.page),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LineSonicItem {
  final String title;
  final String subtitle;
  final String iconAsset;
  final Widget page;

  const _LineSonicItem({
    required this.title,
    required this.subtitle,
    required this.iconAsset,
    required this.page,
  });
}

class _LineSonicCard extends StatefulWidget {
  final _LineSonicItem item;
  final AdaptivePageMetrics metrics;
  final bool enabled;
  final Widget Function(String name, {double size}) iconBuilder;
  final VoidCallback onTap;

  const _LineSonicCard({
    required this.item,
    required this.metrics,
    required this.enabled,
    required this.iconBuilder,
    required this.onTap,
  });

  @override
  State<_LineSonicCard> createState() => _LineSonicCardState();
}

class _LineSonicCardState extends State<_LineSonicCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final metrics = widget.metrics;

    return AnimatedScale(
      scale: _pressed && widget.enabled ? 0.98 : 1.0,
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        opacity: widget.enabled ? 1.0 : 0.62,
        duration: const Duration(milliseconds: 120),
        child: Card(
          elevation: 3,
          shadowColor: scheme.shadow.withAlpha(18),
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
              padding: EdgeInsets.all(metrics.cardPadding),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(metrics.cardRadius),
                border: Border.all(color: scheme.outlineVariant.withAlpha(80)),
              ),
              child: Row(
                children: [
                  Container(
                    width: metrics.iconBoxSize,
                    height: metrics.iconBoxSize,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: widget.iconBuilder(
                        widget.item.iconAsset,
                        size: metrics.iconSize,
                      ),
                    ),
                  ),
                  SizedBox(width: metrics.isTablet ? 16 : 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: metrics.isTablet ? 20 : 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.item.subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: metrics.isTablet ? 15 : 13,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: metrics.isTablet ? 28 : 22,
                    color: scheme.onSurfaceVariant.withAlpha(
                      isDark ? 130 : 100,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
