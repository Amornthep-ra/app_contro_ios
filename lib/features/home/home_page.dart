// lib/features/home/home_page.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' hide Text;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/ble/ble_manager.dart';
import '../../core/ui/app_assets.dart';
import '../../core/ui/language_controller.dart';
import '../../core/ui/theme_controller.dart';
import '../bluetooth/bluetooth_ble_page.dart';
import '../controller/controller_home_page.dart';
import '../info/info_page.dart';
import '../linesonic/linesonic_page.dart';

@immutable
class _HomeMetrics {
  final double contentMaxWidth;
  final EdgeInsets pagePadding;
  final double appBarHeight;
  final double appBarTitleSize;
  final double appBarActionGap;
  final double appBarActionVerticalPadding;
  final double languageControlHeight;
  final double languageControlRadius;
  final double languageControlPadding;
  final double languageIconSize;
  final double segmentPadding;
  final double segmentFontSize;
  final double segmentMinHeight;
  final double themeButtonSize;
  final double themeIconSize;
  final double sectionGap;
  final double navGap;
  final double connectionPadding;
  final double connectionRadius;
  final double connectionIconBox;
  final double connectionIconSize;
  final double connectionLabelSize;
  final double connectionTitleSize;
  final double scanIconSize;
  final double scanButtonHeight;
  final double scanButtonPadding;
  final double scanButtonFontSize;
  final double navPrimaryHeight;
  final double navGuideHeight;
  final EdgeInsets navCardPadding;
  final double navCardRadius;
  final double navIconBox;
  final double navIconSize;
  final double navTitleSize;
  final double navSubtitleSize;
  final double navChevronSize;
  final double recentPaddingHorizontal;
  final double recentPaddingVertical;
  final double recentRadius;
  final double recentIconSize;
  final double recentFontSize;
  final double versionGap;
  final double versionLogoSize;
  final double versionFontSize;

  const _HomeMetrics({
    required this.contentMaxWidth,
    required this.pagePadding,
    required this.appBarHeight,
    required this.appBarTitleSize,
    required this.appBarActionGap,
    required this.appBarActionVerticalPadding,
    required this.languageControlHeight,
    required this.languageControlRadius,
    required this.languageControlPadding,
    required this.languageIconSize,
    required this.segmentPadding,
    required this.segmentFontSize,
    required this.segmentMinHeight,
    required this.themeButtonSize,
    required this.themeIconSize,
    required this.sectionGap,
    required this.navGap,
    required this.connectionPadding,
    required this.connectionRadius,
    required this.connectionIconBox,
    required this.connectionIconSize,
    required this.connectionLabelSize,
    required this.connectionTitleSize,
    required this.scanIconSize,
    required this.scanButtonHeight,
    required this.scanButtonPadding,
    required this.scanButtonFontSize,
    required this.navPrimaryHeight,
    required this.navGuideHeight,
    required this.navCardPadding,
    required this.navCardRadius,
    required this.navIconBox,
    required this.navIconSize,
    required this.navTitleSize,
    required this.navSubtitleSize,
    required this.navChevronSize,
    required this.recentPaddingHorizontal,
    required this.recentPaddingVertical,
    required this.recentRadius,
    required this.recentIconSize,
    required this.recentFontSize,
    required this.versionGap,
    required this.versionLogoSize,
    required this.versionFontSize,
  });

  factory _HomeMetrics.forWidth(double width) {
    if (width >= 720) {
      final expanded = width >= 1024;
      return _HomeMetrics(
        contentMaxWidth: expanded ? 1160 : 920,
        pagePadding: EdgeInsets.fromLTRB(
          expanded ? 28 : 24,
          expanded ? 28 : 22,
          expanded ? 28 : 24,
          32,
        ),
        appBarHeight: expanded ? 60 : 56,
        appBarTitleSize: expanded ? 22 : 20,
        appBarActionGap: expanded ? 12 : 10,
        appBarActionVerticalPadding: expanded ? 8 : 8,
        languageControlHeight: expanded ? 48 : 44,
        languageControlRadius: expanded ? 15 : 14,
        languageControlPadding: expanded ? 8 : 7,
        languageIconSize: expanded ? 32 : 30,
        segmentPadding: expanded ? 10 : 8,
        segmentFontSize: expanded ? 13 : 12,
        segmentMinHeight: expanded ? 34 : 32,
        themeButtonSize: expanded ? 48 : 44,
        themeIconSize: expanded ? 26 : 24,
        sectionGap: expanded ? 24 : 20,
        navGap: expanded ? 22 : 18,
        connectionPadding: expanded ? 24 : 20,
        connectionRadius: expanded ? 24 : 22,
        connectionIconBox: expanded ? 56 : 52,
        connectionIconSize: expanded ? 31 : 28,
        connectionLabelSize: expanded ? 15 : 14,
        connectionTitleSize: expanded ? 22 : 20,
        scanIconSize: expanded ? 24 : 22,
        scanButtonHeight: expanded ? 54 : 50,
        scanButtonPadding: expanded ? 22 : 18,
        scanButtonFontSize: expanded ? 17 : 16,
        navPrimaryHeight: expanded ? 198 : 182,
        navGuideHeight: expanded ? 142 : 132,
        navCardPadding: EdgeInsets.fromLTRB(
          expanded ? 22 : 18,
          expanded ? 20 : 17,
          expanded ? 22 : 18,
          expanded ? 20 : 17,
        ),
        navCardRadius: expanded ? 24 : 22,
        navIconBox: expanded ? 56 : 52,
        navIconSize: expanded ? 34 : 31,
        navTitleSize: expanded ? 20 : 18,
        navSubtitleSize: expanded ? 15 : 14,
        navChevronSize: expanded ? 28 : 26,
        recentPaddingHorizontal: expanded ? 20 : 18,
        recentPaddingVertical: expanded ? 16 : 14,
        recentRadius: expanded ? 20 : 18,
        recentIconSize: expanded ? 22 : 20,
        recentFontSize: expanded ? 16 : 15,
        versionGap: expanded ? 18 : 16,
        versionLogoSize: expanded ? 28 : 26,
        versionFontSize: expanded ? 14 : 13,
      );
    }

    return const _HomeMetrics(
      contentMaxWidth: double.infinity,
      pagePadding: EdgeInsets.fromLTRB(16, 16, 16, 16),
      appBarHeight: 56,
      appBarTitleSize: 18,
      appBarActionGap: 8,
      appBarActionVerticalPadding: 10,
      languageControlHeight: 40,
      languageControlRadius: 12,
      languageControlPadding: 6,
      languageIconSize: 28,
      segmentPadding: 6,
      segmentFontSize: 11,
      segmentMinHeight: 30,
      themeButtonSize: 40,
      themeIconSize: 22,
      sectionGap: 12,
      navGap: 12,
      connectionPadding: 16,
      connectionRadius: 22,
      connectionIconBox: 44,
      connectionIconSize: 24,
      connectionLabelSize: 12,
      connectionTitleSize: 18,
      scanIconSize: 21,
      scanButtonHeight: 44,
      scanButtonPadding: 14,
      scanButtonFontSize: 14,
      navPrimaryHeight: 170,
      navGuideHeight: 120,
      navCardPadding: EdgeInsets.fromLTRB(16, 14, 16, 14),
      navCardRadius: 20,
      navIconBox: 44,
      navIconSize: 28,
      navTitleSize: 16,
      navSubtitleSize: 12,
      navChevronSize: 22,
      recentPaddingHorizontal: 14,
      recentPaddingVertical: 12,
      recentRadius: 16,
      recentIconSize: 18,
      recentFontSize: 14,
      versionGap: 8,
      versionLogoSize: 24,
      versionFontSize: 12,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  StreamSubscription<bool>? _connSub;
  Timer? _rssiTimer;
  Future<PackageInfo>? _infoFuture;

  bool _connected = false;
  bool _openingPage = false;
  int? _rssi;
  String? _lastDeviceId;
  String? _lastDeviceName;

  static const _prefsLastDeviceIdKey = 'ble_last_device_id';
  static const _prefsLastDeviceNameKey = 'ble_last_device_name';

  @override
  void initState() {
    super.initState();
    _connected = BleManager.instance.isConnected;
    _infoFuture = PackageInfo.fromPlatform();
    _loadLastDevice();
    _bindConnection();
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _rssiTimer?.cancel();
    super.dispose();
  }

  void _bindConnection() {
    _connSub = BleManager.instance.connectionStream.listen((connected) {
      if (!mounted) return;
      setState(() {
        _connected = connected;
      });
      if (connected) {
        _startRssiPolling();
        _loadLastDevice();
      } else {
        _stopRssiPolling();
      }
    });

    if (_connected) {
      _startRssiPolling();
    }
  }

  Future<void> _loadLastDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_prefsLastDeviceIdKey);
    final name = prefs.getString(_prefsLastDeviceNameKey);
    if (!mounted) return;
    setState(() {
      _lastDeviceId = id;
      _lastDeviceName = name;
    });
  }

  void _startRssiPolling() {
    _rssiTimer?.cancel();
    _pollRssi();
    _rssiTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _pollRssi();
    });
  }

  void _stopRssiPolling() {
    _rssiTimer?.cancel();
    _rssiTimer = null;
    if (!mounted) return;
    setState(() => _rssi = null);
  }

  Future<void> _pollRssi() async {
    final value = await BleManager.instance.readRssi();
    if (!mounted) return;
    setState(() => _rssi = value);
  }

  Future<void> _openBlePage() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const BluetoothBlePage()));
    await _loadLastDevice();
  }

  Future<void> _openPage(Widget page) async {
    if (_openingPage) return;
    setState(() => _openingPage = true);
    try {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    } finally {
      if (mounted) {
        setState(() => _openingPage = false);
      }
    }
  }

  Future<void> _handleRefresh() async {
    await _openBlePage();
  }

  Future<void> _connectLastDevice(bool isThai) async {
    if (_lastDeviceId == null || _lastDeviceId!.isEmpty) return;
    _showSnack(
      isThai
          ? 'กำลังเชื่อมต่ออุปกรณ์ล่าสุด...'
          : 'Reconnecting to the last device...',
    );
    await BleManager.instance.autoConnectLastDevice();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.black87,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  String _connectedName() {
    final name = BleManager.instance.currentDeviceName;
    if (name != null && name.isNotEmpty) return name;
    final id = BleManager.instance.currentDeviceId;
    if (id != null && id.isNotEmpty) return id;
    if (_lastDeviceName != null && _lastDeviceName!.isNotEmpty) {
      return _lastDeviceName!;
    }
    return _lastDeviceId ?? 'Unknown';
  }

  Color _rssiColor(BuildContext context, int rssi) {
    if (rssi >= -65) return const Color(0xFF22C55E);
    if (rssi >= -80) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  Widget _homeIcon(String name, {double size = 24}) {
    return Image.asset(
      'assets/icons/HomeUnified/$name',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }

  Widget _rssiBars(BuildContext context, int rssi, {double size = 16}) {
    final level = rssi >= -55
        ? 4
        : rssi >= -65
        ? 3
        : rssi >= -75
        ? 2
        : rssi >= -85
        ? 1
        : 0;
    final active = _rssiColor(context, rssi);
    final inactive = active.withAlpha(60);
    final barWidth = (size / 6).clamp(2.0, 5.0).toDouble();
    final gap = (size / 10).clamp(2.0, 4.0).toDouble();
    final heights = <double>[
      size * 0.35,
      size * 0.55,
      size * 0.75,
      size * 0.95,
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (i) {
        final color = i < level ? active : inactive;
        return Container(
          width: barWidth,
          height: heights[i],
          margin: EdgeInsets.only(right: i == 3 ? 0 : gap),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final metrics = _HomeMetrics.forWidth(MediaQuery.of(context).size.width);

    return ValueListenableBuilder<bool>(
      valueListenable: LanguageController.isThai,
      builder: (context, isThai, _) {
        final items = _navItems(isThai);

        return Scaffold(
          appBar: AppBar(
            toolbarHeight: metrics.appBarHeight,
            title: const Text(
              'PB Controller',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            titleTextStyle: TextStyle(
              fontSize: metrics.appBarTitleSize,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
            centerTitle: false,
            titleSpacing: metrics.pagePadding.left,
            automaticallyImplyLeading: false,
            actions: [
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: metrics.appBarActionGap * 0.25,
                  vertical: metrics.appBarActionVerticalPadding,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withAlpha(132),
                    borderRadius: BorderRadius.circular(
                      metrics.languageControlRadius,
                    ),
                    border: Border.all(
                      color: scheme.outlineVariant.withAlpha(88),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: metrics.languageControlPadding),
                      _homeIcon(
                        'Translate-Language.png',
                        size: metrics.languageIconSize,
                      ),
                      SizedBox(width: metrics.appBarActionGap * 0.25),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: metrics.languageControlHeight,
                        ),
                        child: Center(
                          child: SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(value: false, label: Text('EN')),
                              ButtonSegment(value: true, label: Text('TH')),
                            ],
                            selected: {isThai},
                            onSelectionChanged: (value) {
                              LanguageController.setIsThai(value.first);
                            },
                            showSelectedIcon: false,
                            style: SegmentedButton.styleFrom(
                              visualDensity: const VisualDensity(
                                horizontal: -3,
                                vertical: -3,
                              ),
                              padding: EdgeInsets.symmetric(
                                horizontal: metrics.segmentPadding,
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              textStyle: TextStyle(
                                fontSize: metrics.segmentFontSize,
                                fontWeight: FontWeight.w600,
                              ),
                              minimumSize: Size(0, metrics.segmentMinHeight),
                              side: BorderSide(
                                color: scheme.outlineVariant.withAlpha(88),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: metrics.languageControlPadding),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: metrics.themeButtonSize,
                height: metrics.themeButtonSize,
                child: IconButton(
                  icon: _homeIcon(
                    'Theme-Palette.png',
                    size: metrics.themeIconSize,
                  ),
                  onPressed: () => _showThemeSheet(context),
                  tooltip: isThai ? 'ธีม' : 'Theme',
                  padding: EdgeInsets.zero,
                  splashRadius: metrics.themeButtonSize / 2,
                ),
              ),
              SizedBox(width: metrics.pagePadding.right * 0.5),
            ],
            backgroundColor: scheme.surface,
            surfaceTintColor: scheme.surfaceTint,
            scrolledUnderElevation: 2,
          ),
          body: Stack(
            children: [
              RefreshIndicator(
                onRefresh: _handleRefresh,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: metrics.pagePadding,
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: metrics.contentMaxWidth,
                            ),
                            child: Column(
                              children: [
                                _buildConnectionCard(context, isThai, metrics),
                                SizedBox(height: metrics.sectionGap),
                                _buildNavGrid(context, items, metrics),
                                SizedBox(height: metrics.sectionGap),
                                _buildRecentCard(context, isThai, metrics),
                                SizedBox(height: metrics.versionGap),
                                _buildVersionInfo(context, metrics),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<_NavItem> _navItems(bool isThai) {
    return [
      _NavItem(
        title: isThai ? 'โหมดควบคุม' : 'Controller',
        subtitle: isThai
            ? 'ควบคุมทิศทางและจอยสติ๊ก'
            : 'Direction control and joysticks in one place',
        iconAsset: 'Controller-Gamepad.png',
        accent: const Color(0xFF2563EB),
        page: const ControllerHomePage(),
      ),
      _NavItem(
        title: isThai ? 'LineSonic' : 'LineSonic',
        subtitle: isThai
            ? 'ปรับ PID และอ่านเซนเซอร์ผ่าน BLE'
            : 'Tune PID motion over BLE',
        iconAsset: 'LineSonic-PID Tuning.png',
        accent: const Color(0xFF16A34A),
        page: const LineSonicPage(),
      ),
      _NavItem(
        title: isThai ? 'คู่มือการใช้งาน' : 'Guide',
        subtitle: isThai
            ? 'คู่มือและตัวอย่างโค้ด'
            : 'How to use the app and starter code',
        iconAsset: 'Guide-Manual.png',
        accent: const Color(0xFFF59E0B),
        page: const InfoPage(),
      ),
    ];
  }

  Widget _buildConnectionCard(
    BuildContext context,
    bool isThai,
    _HomeMetrics metrics,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final connected = _connected;
    final name = _connectedName();
    final rssi = _rssi;
    final rssiText = rssi != null ? '$rssi dBm' : '-- dBm';

    final gradient = connected
        ? LinearGradient(
            colors: [
              scheme.primaryContainer.withAlpha(220),
              scheme.primaryContainer.withAlpha(120),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : LinearGradient(
            colors: [
              scheme.surfaceContainerHighest.withAlpha(200),
              scheme.surfaceContainerHighest.withAlpha(120),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );

    return Card(
      elevation: 3,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(metrics.connectionRadius),
      ),
      child: Ink(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(metrics.connectionRadius),
        ),
        child: Padding(
          padding: EdgeInsets.all(metrics.connectionPadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: metrics.connectionIconBox,
                height: metrics.connectionIconBox,
                decoration: BoxDecoration(
                  color: connected
                      ? scheme.primary.withAlpha(32)
                      : scheme.outlineVariant.withAlpha(40),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: connected
                    ? _homeIcon(
                        'Bluetooth Connected.png',
                        size: metrics.connectionIconSize,
                      )
                    : _homeIcon(
                        'Bluetooth Disabled.png',
                        size: metrics.connectionIconSize,
                      ),
              ),
              SizedBox(width: metrics.connectionPadding * 0.75),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isThai ? 'สถานะ BLE' : 'BLE Connection',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: isThai
                            ? metrics.connectionLabelSize + 1
                            : metrics.connectionLabelSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      connected
                          ? name
                          : (isThai ? 'ยังไม่เชื่อมต่อ' : 'No device'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: metrics.connectionTitleSize,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (connected)
                      Row(
                        children: [
                          _rssiBars(context, rssi ?? -100, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            rssiText,
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              if (!connected)
                FilledButton.icon(
                  onPressed: _openBlePage,
                  icon: _homeIcon(
                    'Search-Scan.png',
                    size: metrics.scanIconSize,
                  ),
                  label: Text(isThai ? 'ค้นหา' : 'Scan devices'),
                  style: FilledButton.styleFrom(
                    minimumSize: Size(0, metrics.scanButtonHeight),
                    padding: EdgeInsets.symmetric(
                      horizontal: metrics.scanButtonPadding,
                    ),
                    textStyle: TextStyle(
                      fontSize: metrics.scanButtonFontSize,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                )
              else
                Column(
                  children: [
                    _rssiBars(context, rssi ?? -100, size: 26),
                    const SizedBox(height: 4),
                    Text(
                      isThai ? 'สัญญาณ' : 'RSSI',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavGrid(
    BuildContext context,
    List<_NavItem> items,
    _HomeMetrics metrics,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = metrics.navGap;
        final width = constraints.maxWidth;
        final half = (width - spacing) / 2;
        final singleColumn = half < 140;

        return Column(
          children: [
            if (singleColumn) ...[
              SizedBox(
                width: width,
                child: _NavCard(
                  item: items[0],
                  height: metrics.navPrimaryHeight,
                  metrics: metrics,
                  wide: true,
                  enabled: !_openingPage,
                  onTap: () => _openPage(items[0].page),
                ),
              ),
              SizedBox(height: metrics.navGap),
              SizedBox(
                width: width,
                child: _NavCard(
                  item: items[1],
                  height: metrics.navPrimaryHeight,
                  metrics: metrics,
                  wide: true,
                  enabled: !_openingPage,
                  onTap: () => _openPage(items[1].page),
                ),
              ),
            ] else
              Row(
                children: [
                  SizedBox(
                    width: half,
                    child: _NavCard(
                      item: items[0],
                      height: metrics.navPrimaryHeight,
                      metrics: metrics,
                      enabled: !_openingPage,
                      onTap: () => _openPage(items[0].page),
                    ),
                  ),
                  SizedBox(width: metrics.navGap),
                  SizedBox(
                    width: half,
                    child: _NavCard(
                      item: items[1],
                      height: metrics.navPrimaryHeight,
                      metrics: metrics,
                      enabled: !_openingPage,
                      onTap: () => _openPage(items[1].page),
                    ),
                  ),
                ],
              ),
            SizedBox(height: metrics.navGap),
            SizedBox(
              width: width,
              child: _NavCard(
                item: items[2],
                height: metrics.navGuideHeight,
                metrics: metrics,
                wide: true,
                enabled: !_openingPage,
                onTap: () => _openPage(items[2].page),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRecentCard(
    BuildContext context,
    bool isThai,
    _HomeMetrics metrics,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final hasLast = _lastDeviceId != null && _lastDeviceId!.isNotEmpty;

    if (!hasLast) {
      return Card(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(metrics.recentRadius),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: metrics.recentPaddingHorizontal,
            vertical: metrics.recentPaddingVertical,
          ),
          child: Row(
            children: [
              _homeIcon(
                'Recent Activity-History.png',
                size: metrics.recentIconSize,
              ),
              SizedBox(width: metrics.recentPaddingHorizontal * 0.55),
              Expanded(
                child: Text(
                  isThai ? 'ยังไม่มีอุปกรณ์ล่าสุด' : 'No recent device yet',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: metrics.recentFontSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(metrics.recentRadius),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: metrics.recentPaddingHorizontal,
          vertical: metrics.recentPaddingVertical,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _homeIcon(
                  'Recent Activity-History.png',
                  size: metrics.recentIconSize,
                ),
                SizedBox(width: metrics.recentPaddingHorizontal * 0.55),
                Text(
                  isThai ? 'อุปกรณ์ที่เชื่อมต่อล่าสุด' : 'Recent Activity',
                  style: TextStyle(
                    fontSize: metrics.recentFontSize,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (!hasLast)
              Text(
                isThai ? 'ยังไม่มีประวัติการเชื่อมต่อ' : 'No recent device yet',
                style: TextStyle(color: scheme.onSurfaceVariant),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _lastDeviceName ?? _lastDeviceId ?? '-',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _lastDeviceId ?? '-',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonal(
                        onPressed: () => _connectLastDevice(isThai),
                        child: Text(isThai ? 'เชื่อมต่ออีกครั้ง' : 'Reconnect'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _openBlePage,
                        icon: _homeIcon('Search-Scan.png', size: 36),
                        label: Text(isThai ? 'ค้นหา' : 'Scan'),
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVersionInfo(BuildContext context, _HomeMetrics metrics) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: FutureBuilder<PackageInfo>(
        future: _infoFuture,
        builder: (context, snapshot) {
          final version = snapshot.data?.version ?? '2.0.4';
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: 0.28,
                child: ClipOval(
                  child: Image.asset(
                    AppAssets.cornerLogo,
                    width: metrics.versionLogoSize,
                    height: metrics.versionLogoSize,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'v$version',
                style: TextStyle(
                  fontSize: metrics.versionFontSize,
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NavItem {
  final String title;
  final String subtitle;
  final String iconAsset;
  final Color accent;
  final Widget page;

  const _NavItem({
    required this.title,
    required this.subtitle,
    required this.iconAsset,
    required this.accent,
    required this.page,
  });
}

class _NavCard extends StatefulWidget {
  final _NavItem item;
  final double height;
  final _HomeMetrics metrics;
  final bool wide;
  final bool enabled;
  final VoidCallback onTap;

  const _NavCard({
    required this.item,
    required this.height,
    required this.metrics,
    required this.enabled,
    required this.onTap,
    this.wide = false,
  });

  @override
  State<_NavCard> createState() => _NavCardState();
}

class _NavCardState extends State<_NavCard> {
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

    final gradient = LinearGradient(
      colors: [accent.withAlpha(32), accent.withAlpha(14)],
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
          elevation: 3,
          shadowColor: accent.withAlpha(60),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(metrics.navCardRadius),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(metrics.navCardRadius),
            onTap: widget.enabled ? widget.onTap : null,
            onTapDown: widget.enabled ? (_) => _setPressed(true) : null,
            onTapCancel: () => _setPressed(false),
            onTapUp: (_) => _setPressed(false),
            child: Ink(
              height: widget.height,
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(metrics.navCardRadius),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact =
                      constraints.maxWidth < 150 || constraints.maxHeight < 150;
                  final compactWide =
                      widget.wide && constraints.maxHeight < 150;
                  final padding = compact
                      ? (compactWide
                            ? const EdgeInsets.fromLTRB(12, 10, 12, 10)
                            : const EdgeInsets.fromLTRB(6, 6, 6, 6))
                      : metrics.navCardPadding;
                  final iconBox = compact
                      ? (compactWide ? 36.0 : 30.0)
                      : metrics.navIconBox;
                  final iconSize = compact
                      ? (compactWide ? 24.0 : 18.0)
                      : metrics.navIconSize;
                  final gapTop = compact
                      ? (compactWide ? 6.0 : 2.0)
                      : metrics.navGap;
                  final gapMid = compact
                      ? (compactWide ? 2.0 : 0.0)
                      : metrics.navGap * 0.5;
                  final titleSize = compact ? 16.0 : metrics.navTitleSize;
                  final subtitleSize = compact ? 12.0 : metrics.navSubtitleSize;
                  final subtitleLines = compact ? 1 : (widget.wide ? 2 : 3);

                  return Padding(
                    padding: padding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: iconBox,
                              height: iconBox,
                              decoration: BoxDecoration(
                                color: accent.withAlpha(40),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Image.asset(
                                  'assets/icons/HomeUnified/${widget.item.iconAsset}',
                                  width: iconSize,
                                  height: iconSize,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: compact ? 18 : metrics.navChevronSize,
                              color: accent.withAlpha(isDark ? 130 : 100),
                            ),
                          ],
                        ),
                        SizedBox(height: gapTop),
                        Text(
                          widget.item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: titleSize,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: gapMid),
                        Text(
                          widget.item.subtitle,
                          maxLines: subtitleLines,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: subtitleSize,
                            height: compact ? 1.05 : 1.2,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _showThemeSheet(BuildContext context) {
  final isThai = LanguageController.isThai.value;
  showCupertinoModalPopup<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return CupertinoActionSheet(
        title: Text(isThai ? 'ธีม' : 'Theme'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              ThemeController.setMode(ThemeMode.light);
              Navigator.of(context).pop();
            },
            child: Text(isThai ? 'สว่าง' : 'Light'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              ThemeController.setMode(ThemeMode.dark);
              Navigator.of(context).pop();
            },
            child: Text(isThai ? 'มืด' : 'Dark'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(isThai ? 'ยกเลิก' : 'Cancel'),
        ),
      );
    },
  );
}
