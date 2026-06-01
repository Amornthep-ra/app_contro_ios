// lib/features/gamepad/gamepad_4_button_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/ble/ble_manager.dart';
import '../../core/ui/gamepad_assets.dart';
import '../../core/ui/gamepad_components.dart';
import '../../core/ui/gamepad_edit_metrics.dart';
import '../../core/widgets/connection_status_badge.dart';
import '../../core/widgets/gamepad_app_bar.dart';
import '../../core/widgets/gamepad_appbar_controls.dart';
import '../../core/ui/gamepad_tutorial_overlay_components.dart';
import '../../core/utils/orientation_utils.dart';
import '../../core/ui/gamepad_skin.dart';
import '../../core/ble/joystick_packet.dart';
import '../../core/ui/language_controller.dart';
import 'widgets/gamepad_telemetry_chip.dart';

const double designW = 1280;
const double designH = 720;
const double _panelEdgeInset = 28.0;
const double _panelRowGap = 28.0;
const double _panelColGap = 32.0;

const int kLoopHz = 60;
const int kLoopMs = 1000 ~/ kLoopHz;
const int kMinActiveMs = 50;
const int kMinIdleMs = 150;

const int kMaxSendHz = 40;
const int kMaxSendMs = 1000 ~/ kMaxSendHz;

const double _minBtnSize = 0.18;
const double _maxBtnSize = 0.8;
const double _gridStep = 0.05;

Color _opacity(Color color, double opacity) =>
    color.withAlpha((opacity * 255).round());

double _finiteDouble(double? value, double fallback) {
  if (value == null || !value.isFinite) return fallback;
  return value;
}

double _clampUnit(double? value, double fallback) {
  return _finiteDouble(value, fallback).clamp(0.0, 1.0).toDouble();
}

double _clampInitialButtonSize(double? value) {
  return _finiteDouble(value, 0.30).clamp(_minBtnSize, _maxBtnSize).toDouble();
}

double _snapToGrid(double value) {
  if (_gridStep <= 0) return value;
  return (value / _gridStep).round() * _gridStep;
}

class _S {
  final double _sx;
  final double _sy;
  final double _sp;

  _S(this._sx, this._sy, this._sp);

  double w(double v) => v * _sx;
  double h(double v) => v * _sy;
  double r(double v) => v * ((_sx + _sy) / 2.0);
  double sp(double v) => v * _sp;

  EdgeInsets m(EdgeInsets e) =>
      EdgeInsets.fromLTRB(w(e.left), h(e.top), w(e.right), h(e.bottom));
  Offset o(Offset o) => Offset(w(o.dx), h(o.dy));
}

BtnCfg _baseHoldCfg(BuildContext ctx) {
  final theme = Theme.of(ctx);
  final s = theme.colorScheme;

  final platformB = MediaQuery.of(ctx).platformBrightness;
  final isDark =
      theme.brightness == Brightness.dark || platformB == Brightness.dark;

  const darkBase = Color(0xFF0D0F14);
  const darkBorder = Color(0xFF343A46);
  const darkNeon = Color(0xFF8B5CFF);

  final baseColor = isDark ? darkBase : Colors.white;

  final borderColor = isDark
      ? _opacity(darkBorder, .85)
      : _opacity(Colors.black, .20);

  final glowColor = isDark
      ? _opacity(darkNeon, .92)
      : _opacity(const Color(0xFF5C6BFF), .70);

  final pressOverlayColor = isDark ? Colors.white : Colors.black;

  final labelColor = isDark
      ? _opacity(Colors.white, .92)
      : s.onPrimaryContainer;

  return BtnCfg(
    width: 220,
    height: 160,
    margin: const EdgeInsets.all(0),
    radius: 26,
    baseColor: baseColor,
    borderColor: borderColor,
    borderWidthOn: 2.4,
    borderWidthOff: 1.4,
    glowBlurOn: 30,
    glowSpreadOn: 1.2,
    glowBlurOff: 14,
    glowSpreadOff: 0.4,
    shadowOffsetOn: const Offset(0, 8),
    shadowOffsetOff: const Offset(0, 5),
    glowColor: glowColor,
    iconAsset: null,
    iconFit: BoxFit.cover,
    iconPadding: EdgeInsets.zero,
    label: 'Button',
    labelFontSize: 20,
    labelColor: labelColor,
    pressOverlayColor: pressOverlayColor,
    pressOverlayOpacity: .10,
  );
}

BtnCfg cfgForward(BuildContext ctx) => _baseHoldCfg(ctx).copyWith(
  label: 'Forward',
  width: 210,
  height: 280,
  margin: const EdgeInsets.fromLTRB(80, 0, 0, 8),
  iconAsset: kGamepad8AssetUp,
);

BtnCfg cfgBackward(BuildContext ctx) => _baseHoldCfg(ctx).copyWith(
  label: 'Backward',
  width: 210,
  height: 280,
  margin: const EdgeInsets.fromLTRB(80, 16, 0, 0),
  iconAsset: kGamepad8AssetDown,
);

BtnCfg cfgLeft(BuildContext ctx) => _baseHoldCfg(ctx).copyWith(
  label: 'Left',
  width: 210,
  height: 280,
  margin: const EdgeInsets.fromLTRB(0, 64, 0, 0),
  iconAsset: kGamepad8AssetLeft,
);

BtnCfg cfgRight(BuildContext ctx) => _baseHoldCfg(ctx).copyWith(
  label: 'Right',
  width: 210,
  height: 280,
  margin: const EdgeInsets.fromLTRB(0, 64, 0, 0),
  iconAsset: kGamepad8AssetRight,
);

const double speedRowGap = 6.0;

TapCfg cfgSpeedLow(BuildContext ctx) {
  final theme = Theme.of(ctx);
  final platformB = MediaQuery.of(ctx).platformBrightness;
  final isDark =
      theme.brightness == Brightness.dark || platformB == Brightness.dark;

  final c = Colors.green;
  final grad = [lighten(c, .18), darken(c, .06)];

  final border = isDark
      ? lighten(const Color(0xFF00FF9D), .10)
      : lighten(c, .24);

  final glow = isDark
      ? _opacity(const Color(0xFF00FFB2), .55)
      : _opacity(Colors.black, .22);

  final textOn = isDark ? Colors.white : const Color.fromARGB(255, 0, 0, 0);
  final textOff = isDark
      ? _opacity(Colors.white, .85)
      : _opacity(const Color.fromARGB(255, 0, 0, 0), .85);

  return TapCfg(
    width: 100,
    height: 80,
    margin: const EdgeInsets.symmetric(horizontal: speedRowGap),
    radius: 18,
    gradient: grad,
    border: border,
    borderWidthSelected: 2.2,
    borderWidthUnselected: 1.4,
    glowBlurSelected: 18,
    glowBlurUnselected: 12,
    shadowOffsetSelected: const Offset(0, 6),
    shadowOffsetUnselected: const Offset(0, 4),
    glowColor: glow,
    label: 'Lo',
    fontSize: 18,
    textOn: textOn,
    textOff: textOff,
  );
}

TapCfg cfgSpeedMid(BuildContext ctx) {
  final theme = Theme.of(ctx);
  final platformB = MediaQuery.of(ctx).platformBrightness;
  final isDark =
      theme.brightness == Brightness.dark || platformB == Brightness.dark;

  final c = Colors.yellow;
  final grad = [lighten(c, .18), darken(c, .06)];

  final border = isDark
      ? lighten(const Color(0xFFFFD36A), .06)
      : lighten(c, .24);

  final glow = isDark
      ? _opacity(const Color(0xFFFFD54F), .55)
      : _opacity(Colors.black, .22);

  final textOn = Colors.black;
  final textOff = _opacity(Colors.black, .85);

  return TapCfg(
    width: 100,
    height: 80,
    margin: const EdgeInsets.symmetric(horizontal: speedRowGap),
    radius: 18,
    gradient: grad,
    border: border,
    borderWidthSelected: 2.2,
    borderWidthUnselected: 1.4,
    glowBlurSelected: 18,
    glowBlurUnselected: 12,
    shadowOffsetSelected: const Offset(0, 6),
    shadowOffsetUnselected: const Offset(0, 4),
    glowColor: glow,
    label: 'Med',
    fontSize: 18,
    textOn: textOn,
    textOff: textOff,
  );
}

TapCfg cfgSpeedHigh(BuildContext ctx) {
  final theme = Theme.of(ctx);
  final platformB = MediaQuery.of(ctx).platformBrightness;
  final isDark =
      theme.brightness == Brightness.dark || platformB == Brightness.dark;

  final c = Colors.red;
  final grad = [lighten(c, .18), darken(c, .06)];

  final border = isDark
      ? lighten(const Color(0xFFFF6B6B), .06)
      : lighten(c, .24);

  final glow = isDark
      ? _opacity(const Color(0xFFFF5A5A), .60)
      : _opacity(Colors.black, .22);

  final textOn = isDark ? Colors.white : const Color.fromARGB(255, 0, 0, 0);
  final textOff = isDark
      ? _opacity(Colors.white, .85)
      : _opacity(const Color.fromARGB(255, 0, 0, 0), .85);

  return TapCfg(
    width: 100,
    height: 80,
    margin: const EdgeInsets.symmetric(horizontal: speedRowGap),
    radius: 18,
    gradient: grad,
    border: border,
    borderWidthSelected: 2.2,
    borderWidthUnselected: 1.4,
    glowBlurSelected: 18,
    glowBlurUnselected: 12,
    shadowOffsetSelected: const Offset(0, 6),
    shadowOffsetUnselected: const Offset(0, 4),
    glowColor: glow,
    label: 'Hi',
    fontSize: 18,
    textOn: textOn,
    textOff: textOff,
  );
}

CommandCardCfg cfgCommandCard(BuildContext ctx) {
  final t = Theme.of(ctx);
  final base = _opacity(t.colorScheme.surfaceContainerHighest, .70);
  return CommandCardCfg(
    width: 480,
    margin: const EdgeInsets.only(top: 60),
    padding: const EdgeInsets.all(12),
    background: [lighten(base, .06), darken(base, .06)],
    radius: 16,
    borderColor: _opacity(t.colorScheme.outlineVariant, .45),
    borderWidth: 1.2,
    shadowBlur: 12,
    shadowOffset: const Offset(0, 6),
    shadowColor: _opacity(Colors.black, .14),
    titleFont: 18,
    valueFont: 24,
    textColor: t.textTheme.bodyMedium?.color ?? Colors.white,
    valueColor: t.textTheme.bodyLarge?.color ?? Colors.white,
    dividerColor: _opacity(t.colorScheme.outlineVariant, .6),
  );
}

BtnCfg _scaleBtn(BtnCfg c, _S s) => c.copyWith(
  width: s.w(c.width),
  height: s.h(c.height),
  margin: s.m(c.margin),
  radius: s.r(c.radius),
  borderWidthOn: s.r(c.borderWidthOn),
  borderWidthOff: s.r(c.borderWidthOff),
  glowBlurOn: s.r(c.glowBlurOn),
  glowSpreadOn: s.r(c.glowSpreadOn),
  glowBlurOff: s.r(c.glowBlurOff),
  glowSpreadOff: s.r(c.glowSpreadOff),
  shadowOffsetOn: s.o(c.shadowOffsetOn),
  shadowOffsetOff: s.o(c.shadowOffsetOff),
  iconPadding: s.m(c.iconPadding),
  labelFontSize: s.sp(c.labelFontSize),
);

class Gamepad4ButtonPage extends StatefulWidget {
  const Gamepad4ButtonPage({super.key});

  @override
  State<Gamepad4ButtonPage> createState() => _Gamepad4ButtonPageState();
}

class _Gamepad4ButtonPageState extends State<Gamepad4ButtonPage> {
  static const _prefsLayoutAll = 'gp4_layout_all';
  static const _prefsActiveAll = 'gp4_active_all';
  static const _prefsTutorialSeen = 'gp4_tutorial_seen';
  static const _prefsTutorialPromptSeen = 'gp4_tutorial_prompt_seen';
  static const _prefsPreset1 = 'gp4_preset_1';
  static const _prefsPreset2 = 'gp4_preset_2';
  static const _prefsPreset3 = 'gp4_preset_3';

  bool _f = false, _b = false, _l = false, _r = false;
  String _command = '0';
  String _speedLabel = 'Lo';
  String _lastPacketKey = '';

  bool _showTutorial = false;
  bool _showTutorialPrompt = false;
  int _tutorialStep = 0;
  bool _tutorialThai = true;
  bool _tutorialSpeedPanelOpen = false;
  late final VoidCallback _langListener;
  Rect? _tutorialTargetRect;
  GlobalKey? _tutorialTargetKey;
  final GlobalKey _tutorialStackKey = GlobalKey();
  final GlobalKey _tutorialBackKey = GlobalKey();
  final GlobalKey _tutorialCustomizeKey = GlobalKey();
  final GlobalKey _tutorialSpeedKey = GlobalKey();
  final GlobalKey _tutorialSpeedPanelKey = GlobalKey();
  final GlobalKey _tutorialBtKey = GlobalKey();
  final GlobalKey _tutorialBlePanelKey = GlobalKey();
  final GlobalKey _tutorialButtonsPanelKey = GlobalKey();
  final GlobalKey _tutorialPresetKey = GlobalKey();
  final GlobalKey _tutorialHelpKey = GlobalKey();
  final GlobalKey _tutorialCmdKey = GlobalKey();
  final GlobalKey _tutorialSpdKey = GlobalKey();
  final GlobalKey _tutorialGridKey = GlobalKey();
  final GlobalKey _tutorialDoneKey = GlobalKey();
  final GlobalKey _tutorialDeleteKey = GlobalKey();
  final GlobalKey _tutorialResetKey = GlobalKey();
  final GlobalKey _tutorialUndoKey = GlobalKey();
  final GlobalKey _tutorialRedoKey = GlobalKey();
  final GlobalKey _tutorialSizeKey = GlobalKey();
  final GlobalKey _tutorialLockKey = GlobalKey();

  bool _editMode = false;
  bool _showGrid = false;
  bool _speedMenuOpen = false;
  Map<String, _ButtonLayout> _layoutAll = {};
  Set<String> _activeIds = {'F:forward', 'F:backward', 'F:left', 'F:right'};
  final Set<String> _lockedIds = {};
  String? _selectedId;
  String? _editWarningId;
  Size? _panelSize;
  Timer? _editWarningTimer;
  int _lastOverlapWarningMs = 0;
  int _lastBoundaryWarningMs = 0;
  final List<_EditSnapshot> _undoStack = [];
  final List<_EditSnapshot> _redoStack = [];
  static const int _maxHistory = 30;

  Timer? _tick;
  int _lastSendMs = 0;
  StreamSubscription<bool>? _bleConnSub;
  int? _bleTrafficOwner;

  void _resetInputState() {
    void apply() {
      _f = false;
      _b = false;
      _l = false;
      _r = false;
      _command = '0';
      _lastPacketKey = '';
      _lastSendMs = 0;
    }

    if (mounted) {
      setState(apply);
    } else {
      apply();
    }
  }

  Set<int> _buildPressedButtons() {
    final btns = <int>{};

    if (_f && !_b) btns.add(kBleBtnUp);
    if (_b && !_f) btns.add(kBleBtnDown);
    if (_l && !_r) btns.add(kBleBtnLeft);
    if (_r && !_l) btns.add(kBleBtnRight);

    if (_speedLabel == 'Lo') btns.add(kBleBtnSpeedLow);
    if (_speedLabel == 'Med') btns.add(kBleBtnSpeedMid);
    if (_speedLabel == 'Hi') btns.add(kBleBtnSpeedHigh);

    return btns;
  }

  String _packetKey() => '$_command|$_speedLabel';

  int _buttonsByte() {
    final btns = _buildPressedButtons();
    int v = 0;
    for (final b in btns) {
      if (b < 1 || b > 8) continue;
      v |= (1 << (b - 1));
    }
    return v & 0xFF;
  }

  String _commandByteLabel() => _buttonsByte().toString();

  Future<void> _loadLayouts() async {
    final prefs = await SharedPreferences.getInstance();
    final layoutRaw = prefs.getString(_prefsLayoutAll);
    final activeRaw = prefs.getString(_prefsActiveAll);

    if (layoutRaw != null && layoutRaw.isNotEmpty) {
      _layoutAll = _decodeLayout(layoutRaw);
    }
    if (activeRaw != null && activeRaw.isNotEmpty) {
      _activeIds = _decodeIdList(activeRaw);
    }

    if (_activeIds.isEmpty) {
      _activeIds = {'F:forward', 'F:backward', 'F:left', 'F:right'};
    }

    _layoutAll.removeWhere((k, _) => !_activeIds.contains(k));
    _lockedIds.removeWhere((id) => !_layoutAll.containsKey(id));

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _saveLayout(
    String key,
    Map<String, _ButtonLayout> layout,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(_encodeLayout(layout)));
  }

  Future<void> _saveActive(String key, Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(ids.toList()));
  }

  Map<String, _ButtonLayout> _decodeLayout(String raw) {
    try {
      final obj = jsonDecode(raw);
      if (obj is! Map) return {};
      final out = <String, _ButtonLayout>{};
      obj.forEach((k, v) {
        if (v is Map) {
          final cx = (v['cx'] as num?)?.toDouble();
          final cy = (v['cy'] as num?)?.toDouble();
          final size = (v['size'] as num?)?.toDouble();
          if (cx != null && cy != null) {
            out[k.toString()] = _ButtonLayout(
              _clampUnit(cx, 0.5),
              _clampUnit(cy, 0.5),
              _clampInitialButtonSize(size),
            );
          }
        }
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  Map<String, Map<String, double>> _encodeLayout(
    Map<String, _ButtonLayout> layout,
  ) {
    final out = <String, Map<String, double>>{};
    layout.forEach((k, v) {
      out[k] = v.toJson();
    });
    return out;
  }

  Set<String> _decodeIdList(String raw) {
    try {
      final obj = jsonDecode(raw);
      if (obj is! List) return {};
      return obj.map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  void _toggleEdit() {
    setState(() {
      _editMode = !_editMode;
      _editWarningId = null;
    });
  }

  void _selectButton(String id) {
    setState(() {
      _selectedId = id;
      _editWarningId = null;
    });
  }

  void _toggleActive(String id) {
    _pushHistory();
    setState(() {
      if (_activeIds.contains(id)) {
        _activeIds.remove(id);
        _layoutAll.remove(id);
        _lockedIds.remove(id);
        if (_selectedId == id) _selectedId = null;
        if (id == 'F:forward') _f = false;
        if (id == 'F:backward') _b = false;
        if (id == 'F:left') _l = false;
        if (id == 'F:right') _r = false;
      } else {
        _activeIds.add(id);
      }
      _saveActive(_prefsActiveAll, _activeIds);
    });
  }

  void _removeSelected() {
    final id = _selectedId;
    if (id == null) return;
    _toggleActive(id);
  }

  Map<String, _ButtonLayout> _cloneLayout(Map<String, _ButtonLayout> src) {
    final out = <String, _ButtonLayout>{};
    src.forEach((k, v) {
      out[k] = _ButtonLayout(v.cx, v.cy, v.size);
    });
    return out;
  }

  _EditSnapshot _captureSnapshot() {
    return _EditSnapshot(
      layoutAll: _cloneLayout(_layoutAll),
      activeIds: Set<String>.from(_activeIds),
      lockedIds: Set<String>.from(_lockedIds),
      selectedId: _selectedId,
    );
  }

  void _applySnapshot(_EditSnapshot snap) {
    _layoutAll = _cloneLayout(snap.layoutAll);
    _activeIds
      ..clear()
      ..addAll(snap.activeIds);
    _lockedIds
      ..clear()
      ..addAll(snap.lockedIds);
    _selectedId = snap.selectedId;
    _lockedIds.removeWhere((id) => !_layoutAll.containsKey(id));
  }

  void _pushHistory() {
    _undoStack.add(_captureSnapshot());
    if (_undoStack.length > _maxHistory) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    setState(() {
      _redoStack.add(_captureSnapshot());
      _applySnapshot(_undoStack.removeLast());
      _editWarningId = null;
    });
    _saveActive(_prefsActiveAll, _activeIds);
    _saveLayout(_prefsLayoutAll, _layoutAll);
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    setState(() {
      _undoStack.add(_captureSnapshot());
      _applySnapshot(_redoStack.removeLast());
      _editWarningId = null;
    });
    _saveActive(_prefsActiveAll, _activeIds);
    _saveLayout(_prefsLayoutAll, _layoutAll);
  }

  void _changeSelectedSize(double delta) {
    final id = _selectedId;
    if (id == null) return;
    if (_lockedIds.contains(id)) return;
    final panelSize = _panelSize;
    if (panelSize == null) return;
    final current = _layoutAll[id];
    if (current == null) return;
    final base = _cfgForId(id);
    if (base == null) return;
    final normalizedCurrent = _normalizeLayoutForPanel(
      current,
      base,
      panelSize,
    );
    final maxSize = _maxLayoutSizeForPanel(base, panelSize);
    final minSize = math.min(_minBtnSize, maxSize);
    final unclamped = normalizedCurrent.size + delta;
    final nextSize = unclamped.clamp(minSize, maxSize).toDouble();
    if (nextSize == normalizedCurrent.size) {
      final atMax = unclamped >= maxSize;
      _showSizeLimit(atMax);
      _flashEditWarning(id);
      return;
    }
    final w = panelSize.width;
    final h = panelSize.height;
    final scaled = _scaledHoldCfg(
      base,
      normalizedCurrent.copyWith(size: nextSize),
      panelSize,
    );
    final candidate = _ButtonLayout(
      w > 0 ? scaled.center.dx / w : 0.5,
      h > 0 ? scaled.center.dy / h : 0.5,
      nextSize,
    );
    if (_wouldOverlapAny(id, candidate, panelSize)) {
      HapticFeedback.vibrate();
      setState(() => _editWarningId = id);
      _showOverlapWarning();
      return;
    }

    _pushHistory();
    setState(() {
      final next = Map<String, _ButtonLayout>.from(_layoutAll);
      next[id] = candidate;
      _layoutAll = next;
      _editWarningId = null;
    });
    _saveLayout(_prefsLayoutAll, _layoutAll);
  }

  void _toggleSelectedLock() {
    final id = _selectedId;
    if (id == null) return;
    setState(() {
      if (_lockedIds.contains(id)) {
        _lockedIds.remove(id);
      } else {
        _lockedIds.add(id);
      }
    });
  }

  void _showSizeLimit(bool atMax) {
    final isThai = LanguageController.isThai.value;
    final msg = atMax
        ? (isThai ? 'ขนาดสูงสุดคือ 80%' : 'Maximum size is 80%.')
        : (isThai ? 'ถึงขนาดต่ำสุดแล้ว' : 'Minimum size reached.');
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(milliseconds: 900)),
    );
  }

  void _flashEditWarning(String id) {
    _editWarningTimer?.cancel();
    setState(() => _editWarningId = id);
    _editWarningTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() {
        if (_editWarningId == id) _editWarningId = null;
      });
    });
  }

  BtnCfg? _cfgForId(String id) {
    if (id == 'F:forward') return cfgForward(context);
    if (id == 'F:backward') return cfgBackward(context);
    if (id == 'F:left') return cfgLeft(context);
    if (id == 'F:right') return cfgRight(context);
    return null;
  }

  bool _wouldOverlapAny(String movingId, _ButtonLayout moving, Size panelSize) {
    final movingBase = _cfgForId(movingId);
    if (movingBase == null) return false;
    final movingScaled = _scaledHoldCfg(movingBase, moving, panelSize);
    final movingRadius =
        math.min(movingScaled.cfg.width, movingScaled.cfg.height) / 2;
    final movingCenter = movingScaled.center;

    for (final entry in _layoutAll.entries) {
      final id = entry.key;
      if (id == movingId) continue;
      if (!_activeIds.contains(id)) continue;
      final base = _cfgForId(id);
      if (base == null) continue;
      final otherScaled = _scaledHoldCfg(base, entry.value, panelSize);
      final otherRadius =
          math.min(otherScaled.cfg.width, otherScaled.cfg.height) / 2;
      final dx = movingCenter.dx - otherScaled.center.dx;
      final dy = movingCenter.dy - otherScaled.center.dy;
      final dist = math.sqrt((dx * dx) + (dy * dy));
      if (dist < (movingRadius + otherRadius)) {
        return true;
      }
    }
    return false;
  }

  Widget _buildGridOverlay() {
    if (!_editMode || !_showGrid) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final minor = _opacity(
      isDark ? Colors.white : Colors.black,
      isDark ? 0.14 : 0.16,
    );
    final major = _opacity(
      isDark ? Colors.white : Colors.black,
      isDark ? 0.24 : 0.30,
    );

    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _GridPainter(
            step: _gridStep,
            minorColor: minor,
            majorColor: major,
          ),
        ),
      ),
    );
  }

  void _resetLayouts() async {
    _pushHistory();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsLayoutAll);
    await prefs.remove(_prefsActiveAll);
    setState(() {
      _layoutAll = {};
      _activeIds = {'F:forward', 'F:backward', 'F:left', 'F:right'};
      _lockedIds.clear();
      _selectedId = null;
      _editWarningId = null;
    });
  }

  Future<void> _maybeStartTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    final tutorialSeen = prefs.getBool(_prefsTutorialSeen) ?? false;
    final promptSeen = prefs.getBool(_prefsTutorialPromptSeen) ?? false;
    if (tutorialSeen || promptSeen || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _showTutorialPrompt = true;
      });
    });
  }

  Future<void> _dismissTutorialPrompt() async {
    setState(() {
      _showTutorialPrompt = false;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsTutorialPromptSeen, true);
  }

  Future<void> _startTutorialFromPrompt() async {
    setState(() {
      _showTutorialPrompt = false;
      _showTutorial = true;
      _tutorialStep = 0;
      _tutorialThai = LanguageController.isThai.value;
      _tutorialSpeedPanelOpen = false;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsTutorialPromptSeen, true);
    _scheduleTutorialRectUpdate();
  }

  void _scheduleTutorialRectUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_showTutorial) return;
      final changed = _syncTutorialPreviewPanels();
      if (changed) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_showTutorial) return;
          _updateTutorialRect();
        });
        return;
      }
      _updateTutorialRect();
    });
  }

  bool _syncTutorialPreviewPanels() {
    final steps = _tutorialSteps();
    if (_tutorialStep < 0 || _tutorialStep >= steps.length) return false;
    final step = steps[_tutorialStep];
    final shouldOpenSpeedPanel = step.openSpeedPanel;
    if (_tutorialSpeedPanelOpen != shouldOpenSpeedPanel) {
      setState(() => _tutorialSpeedPanelOpen = shouldOpenSpeedPanel);
      return true;
    }
    return false;
  }

  List<_TutorialStep> _tutorialSteps() {
    return [
      const _TutorialStep(
        titleTh: 'Gamepad 4',
        bodyTh:
            'ภาพรวมการควบคุมทิศทาง การตั้งค่าความเร็ว Lo/Med/Hi และเครื่องมือปรับแต่งเลย์เอาต์ในหน้านี้',
        titleEn: 'Gamepad 4',
        bodyEn:
            'Overview of directional controls, Lo/Med/Hi speed settings, and layout editing tools on this page.',
        editMode: false,
      ),
      _TutorialStep(
        titleTh: 'Back',
        bodyTh: 'ย้อนกลับไปยังหน้า Controller',
        titleEn: 'Back',
        bodyEn: 'Go back to the Controller page.',
        targetKey: _tutorialBackKey,
        editMode: false,
      ),
      _TutorialStep(
        titleTh: 'ระดับความเร็ว',
        bodyTh:
            'แตะเพื่อเลือกความเร็วพื้นฐาน: ต่ำ (Lo) / กลาง (Med) / สูง (Hi) ',
        titleEn: 'Speed Selector',
        bodyEn: 'Tap to choose a preset speed: Lo, Med, or Hi.',
        targetKey: _tutorialSpeedKey,
        editMode: false,
      ),
      _TutorialStep(
        titleTh: 'เมนูเลือกความเร็ว',
        bodyTh: 'หน้าต่างป๊อปอัปสำหรับปรับเปลี่ยนความเร็วอย่างรวดเร็ว',
        titleEn: 'Speed Panel Preview',
        bodyEn: 'A preview of the popup panel for quick speed adjustments.',
        targetKey: _tutorialSpeedPanelKey,
        openSpeedPanel: true,
        editMode: false,
      ),
      _TutorialStep(
        titleTh: 'ชุดคำสั่ง (CMD)',
        bodyTh:
            'แสดงรหัสคำสั่ง (Byte) ที่ส่งไปยังหุ่นยนต์แบบเรียลไทม์ตามปุ่มที่กด',
        titleEn: 'Command Status (CMD)',
        bodyEn:
            'Displays real-time command bytes sent to the robot based on your input.',
        targetKey: _tutorialCmdKey,
        editMode: false,
      ),
      _TutorialStep(
        titleTh: 'ข้อมูลรหัสความเร็ว',
        bodyTh:
            'แสดงค่ารหัส (Byte) ของระดับความเร็ว Lo / Med / Hi ที่กำลังส่งไปยังหุ่นยนต์แบบเรียลไทม์',
        titleEn: 'Speed Code Status',
        bodyEn:
            'Displays the real-time speed byte for Lo / Med / Hi modes being sent to the robot.',
        targetKey: _tutorialSpdKey,
        editMode: false,
      ),
      _TutorialStep(
        titleTh: 'สถานะ BLE',
        bodyTh:
            'ตรวจสอบการเชื่อมต่อ และแตะเพื่อเปิดเมนูจัดการอุปกรณ์ (ระบบจะเชื่อมต่ออุปกรณ์ล่าสุดให้เองอัตโนมัติ)',
        titleEn: 'BLE Status',
        bodyEn:
            'View connection status and tap to manage devices. (Automatically reconnects to the last device).',
        targetKey: _tutorialBtKey,
        editMode: false,
      ),
      _TutorialStep(
        titleTh: 'หน้าจัดการ BLE',
        bodyTh:
            'หน้าสำหรับค้นหาและเชื่อมต่ออุปกรณ์ BLE พร้อมแสดงรายการที่ตรวจพบและสถานะสัญญาณ',
        titleEn: 'BLE Management',
        bodyEn:
            'Scan and connect to BLE devices, view signal strength, and manage discovered devices.',
        targetKey: _tutorialBlePanelKey,
        openBleSheet: true,
        editMode: false,
      ),
      _TutorialStep(
        titleTh: 'โหมดแก้ไข',
        bodyTh: 'แตะเพื่อเข้าสู่โหมดการปรับแต่งเลย์เอาต์ปุ่ม',
        titleEn: 'Edit Mode',
        bodyEn: 'Enter layout customization mode.',
        targetKey: _tutorialCustomizeKey,
        editMode: false,
      ),
      _TutorialStep(
        titleTh: 'ลบปุ่ม',
        bodyTh: 'นำปุ่มที่เลือกไว้ออกจากหน้าจอ',
        titleEn: 'Delete',
        bodyEn: 'Remove the selected button from the layout.',
        targetKey: _tutorialDeleteKey,
        editMode: true,
      ),
      _TutorialStep(
        titleTh: 'รีเซ็ต',
        bodyTh: 'รีเซ็ตตำแหน่งและขนาดปุ่มทั้งหมดกลับเป็นค่าเริ่มต้น',
        titleEn: 'Reset Layout',
        bodyEn: 'Reset all button positions and sizes to defaults.',
        targetKey: _tutorialResetKey,
        editMode: true,
      ),
      _TutorialStep(
        titleTh: 'ย้อน',
        bodyTh: 'ย้อนการแก้ไขล่าสุด',
        titleEn: 'Undo',
        bodyEn: 'Undo latest edit action.',
        targetKey: _tutorialUndoKey,
        editMode: true,
      ),
      _TutorialStep(
        titleTh: 'ทำซ้ำ',
        bodyTh: 'ทำซ้ำการแก้ไขที่ย้อนกลับไป',
        titleEn: 'Redo',
        bodyEn: 'Redo the undone edit action.',
        targetKey: _tutorialRedoKey,
        editMode: true,
      ),
      _TutorialStep(
        titleTh: 'กริด',
        bodyTh: 'เปิด/ปิดเส้นกริดเพื่อช่วยในการจัดวางปุ่มให้แม่นยำ',
        titleEn: 'Grid',
        bodyEn: 'Toggle grid lines for precise button alignment.',
        targetKey: _tutorialGridKey,
        editMode: true,
      ),
      _TutorialStep(
        titleTh: 'ขนาด',
        bodyTh: 'ย่อหรือขยายขนาดของปุ่มที่เลือกอยู่',
        titleEn: 'Size',
        bodyEn: 'Scale the selected button up or down.',
        targetKey: _tutorialSizeKey,
        editMode: true,
      ),
      _TutorialStep(
        titleTh: 'ล็อกปุ่ม',
        bodyTh: 'ล็อกตำแหน่งปุ่มเพื่อป้องกันการเคลื่อนย้ายโดยไม่ตั้งใจ',
        titleEn: 'Lock',
        bodyEn: 'Lock button position to prevent accidental moving.',
        targetKey: _tutorialLockKey,
        editMode: true,
      ),
      _TutorialStep(
        titleTh: 'เสร็จสิ้น',
        bodyTh: 'บันทึกการตั้งค่าและออกจากโหมดแก้ไข',
        titleEn: 'Done',
        bodyEn: 'Save changes and exit edit mode.',
        targetKey: _tutorialDoneKey,
        editMode: true,
      ),
      _TutorialStep(
        titleTh: 'ค่าที่ตั้งไว้ (Preset)',
        bodyTh: 'บันทึกหรือเรียกใช้รูปแบบปุ่มและค่าความเร็วที่คุณตั้งไว้',
        titleEn: 'Presets',
        bodyEn: 'Save or load your custom layouts and speed settings.',
        targetKey: _tutorialPresetKey,
        editMode: false,
      ),
      _TutorialStep(
        titleTh: 'หน้าจัดการพรีเซ็ต',
        bodyTh: 'เลือกดูและจัดการรายการการตั้งค่าทั้งหมดที่บันทึกไว้',
        titleEn: 'Preset Management',
        bodyEn: 'View and manage all your saved configuration presets.',
        editMode: false,
      ),
      _TutorialStep(
        titleTh: 'คำแนะนำการใช้งาน',
        bodyTh: 'แตะที่นี่เพื่อดูคำแนะนำการใช้งานนี้อีกครั้งได้ทุกเมื่อ',
        titleEn: 'Tutorial',
        bodyEn: 'Tap here to replay this tutorial anytime.',
        targetKey: _tutorialHelpKey,
        editMode: false,
      ),
    ];
  }

  void _goTutorialStep(int nextStep) {
    final steps = _tutorialSteps();
    if (nextStep < 0 || nextStep >= steps.length) return;
    final step = steps[nextStep];
    setState(() {
      if (step.editMode != null) {
        _editMode = step.editMode!;
      }
      _tutorialStep = nextStep;
    });
    _scheduleTutorialRectUpdate();
  }

  Future<void> _finishTutorial() async {
    setState(() {
      _showTutorial = false;
      _tutorialStep = 0;
      _editMode = false;
      _tutorialSpeedPanelOpen = false;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsTutorialSeen, true);
  }

  Future<void> _restartTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsTutorialSeen, false);
    if (!mounted) return;
    setState(() {
      _showTutorial = true;
      _tutorialStep = 0;
      _tutorialThai = LanguageController.isThai.value;
      _editMode = false;
      _tutorialSpeedPanelOpen = false;
    });
    _scheduleTutorialRectUpdate();
  }

  void _updateTutorialRect() {
    final steps = _tutorialSteps();
    if (_tutorialStep < 0 || _tutorialStep >= steps.length) {
      setState(() {
        _tutorialTargetRect = null;
        _tutorialTargetKey = null;
      });
      return;
    }
    final key = steps[_tutorialStep].targetKey;
    final stackBox =
        _tutorialStackKey.currentContext?.findRenderObject() as RenderBox?;
    final targetBox = key?.currentContext?.findRenderObject() as RenderBox?;
    if (key == null || stackBox == null || targetBox == null) {
      setState(() {
        _tutorialTargetRect = null;
        _tutorialTargetKey = key;
      });
      if (key != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_showTutorial) return;
          _updateTutorialRect();
        });
      }
      return;
    }
    final rect = _targetRectInStack(stackBox, targetBox);
    setState(() {
      _tutorialTargetRect = rect;
      _tutorialTargetKey = key;
    });
  }

  Rect _targetRectInStack(RenderBox stackBox, RenderBox targetBox) {
    final transform = targetBox.getTransformTo(stackBox);
    final rect = Offset.zero & targetBox.size;
    final corners = <Offset>[
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ].map((point) => MatrixUtils.transformPoint(transform, point)).toList();

    final left = corners.map((p) => p.dx).reduce(math.min);
    final right = corners.map((p) => p.dx).reduce(math.max);
    final top = corners.map((p) => p.dy).reduce(math.min);
    final bottom = corners.map((p) => p.dy).reduce(math.max);
    return Rect.fromLTRB(left, top, right, bottom);
  }

  String _presetKey(int slot) {
    switch (slot) {
      case 1:
        return _prefsPreset1;
      case 2:
        return _prefsPreset2;
      case 3:
        return _prefsPreset3;
      default:
        return _prefsPreset1;
    }
  }

  String _defaultPresetName(int slot, bool isThai) =>
      isThai ? 'ค่าที่ตั้งไว้ $slot' : 'Preset $slot';

  static final RegExp _presetAllowedPattern = RegExp(
    r'^[A-Za-z0-9ก-ฮ\u0E30-\u0E3A\u0E40-\u0E4E _-]+$',
  );
  static final RegExp _presetRequiredChars = RegExp(r'[A-Za-z0-9ก-ฮ]');

  String? _validatePresetName(String raw, bool isThai) {
    final value = raw.trim();
    if (value.isEmpty) {
      return isThai
          ? 'กรุณาตั้งชื่อโดยใช้ตัวอักษรหรือเลข'
          : 'Enter a preset name using letters or numbers.';
    }
    if (!_presetAllowedPattern.hasMatch(value)) {
      return isThai
          ? 'ใช้ได้เฉพาะตัวอักษร ตัวเลข เว้นวรรค - และ _'
          : 'Only letters, numbers, spaces, - and _ are allowed.';
    }
    if (!_presetRequiredChars.hasMatch(value)) {
      return isThai
          ? 'กรุณาใช้ตัวอักษรหรือเลขอย่างน้อย 1 ตัว และไม่ใช้สัญลักษณ์ล้วน'
          : 'Use at least one letter or number. Symbols alone are not allowed.';
    }
    return null;
  }

  String? _readPresetName(String raw) {
    try {
      final obj = jsonDecode(raw);
      if (obj is! Map) return null;
      final name = obj['name'];
      if (name is String && name.trim().isNotEmpty) return name.trim();
    } catch (_) {}
    return null;
  }

  Future<String?> _promptPresetName({
    required BuildContext context,
    String? currentName,
  }) async {
    final isThai = LanguageController.isThai.value;
    final controller = TextEditingController(text: currentName ?? '');
    final focusNode = FocusNode();
    String? errorText = _validatePresetName(controller.text, isThai);
    var closing = false;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void submit() {
            if (closing) return;
            final trimmed = controller.text.trim();
            final validation = _validatePresetName(trimmed, isThai);
            if (validation != null) {
              setDialogState(() {
                errorText = validation;
              });
              return;
            }
            closing = true;
            FocusManager.instance.primaryFocus?.unfocus();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (ctx.mounted && Navigator.of(ctx).canPop()) {
                Navigator.of(ctx).pop(trimmed);
              }
            });
          }

          return AlertDialog(
            title: Text(isThai ? 'ตั้งชื่อค่าที่ตั้งไว้' : 'Rename Preset'),
            content: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              maxLength: 24,
              decoration: InputDecoration(
                hintText: isThai ? 'ชื่อค่าที่ตั้งไว้' : 'Preset name',
                helperText: isThai
                    ? 'ใช้ได้เฉพาะตัวอักษร ตัวเลข เว้นวรรค - และ _'
                    : 'Letters, numbers, spaces, - and _ only',
                errorText: errorText,
              ),
              onChanged: (value) {
                if (closing) return;
                setDialogState(() {
                  errorText = _validatePresetName(value, isThai);
                });
              },
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                onPressed: closing ? null : () => Navigator.pop(ctx),
                child: Text(isThai ? 'ยกเลิก' : 'Cancel'),
              ),
              FilledButton(
                onPressed: errorText != null || closing ? null : submit,
                child: Text(isThai ? 'บันทึก' : 'Save'),
              ),
            ],
          );
        },
      ),
    );
    focusNode.dispose();
    controller.dispose();
    return result;
  }

  Future<void> _savePreset(int slot, {String? name}) async {
    final prefs = await SharedPreferences.getInstance();
    final data = <String, Object>{
      'layout': _encodeLayout(_layoutAll),
      'active': _activeIds.toList(),
      'speed': _speedLabel,
    };
    final trimmed = (name ?? '').trim();
    if (trimmed.isNotEmpty) {
      data['name'] = trimmed;
    }
    await prefs.setString(_presetKey(slot), jsonEncode(data));
  }

  Future<void> _loadPreset(int slot) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_presetKey(slot));
    if (raw == null || raw.isEmpty) return;
    try {
      final obj = jsonDecode(raw);
      if (obj is! Map) return;
      final layoutRaw = obj['layout'];
      final activeRaw = obj['active'];
      final speed = obj['speed'];
      if (layoutRaw is Map) {
        _layoutAll = _decodeLayout(jsonEncode(layoutRaw));
      }
      if (activeRaw is List) {
        _activeIds = activeRaw.map((e) => e.toString()).toSet();
      }
      if (speed is String) _speedLabel = speed;
      setState(() {});
      _saveLayout(_prefsLayoutAll, _layoutAll);
      _saveActive(_prefsActiveAll, _activeIds);
      _sendBinary(force: true);
    } catch (_) {}
  }

  Future<void> _showPresetSheet() async {
    final rootTheme = Theme.of(context);
    final rootIsDark = rootTheme.brightness == Brightness.dark;
    final isThai = LanguageController.isThai.value;
    final prefs = await SharedPreferences.getInstance();
    final exists = <int, bool>{
      1: (prefs.getString(_prefsPreset1) ?? '').isNotEmpty,
      2: (prefs.getString(_prefsPreset2) ?? '').isNotEmpty,
      3: (prefs.getString(_prefsPreset3) ?? '').isNotEmpty,
    };
    final customNames = <int, String?>{
      1: _readPresetName(prefs.getString(_prefsPreset1) ?? ''),
      2: _readPresetName(prefs.getString(_prefsPreset2) ?? ''),
      3: _readPresetName(prefs.getString(_prefsPreset3) ?? ''),
    };
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      barrierColor: _opacity(Colors.black, rootIsDark ? 0.72 : 0.46),
      builder: (context) {
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;
        final sheetBg = isDark
            ? _opacity(const Color(0xFF0B1220), 0.92)
            : _opacity(Colors.white, 0.97);
        final sheetBorder = isDark
            ? _opacity(const Color(0xFF60A5FA), 0.34)
            : _opacity(const Color(0xFF3B82F6), 0.22);
        final cardBg = isDark
            ? _opacity(const Color(0xFF111A2E), 0.9)
            : _opacity(const Color(0xFFF8FAFC), 0.96);
        final cardBorder = isDark
            ? _opacity(Colors.white, 0.12)
            : _opacity(const Color(0xFF0F172A), 0.1);
        final titleColor = isDark ? Colors.white : cs.onSurface;
        final subtitleColor = isDark
            ? Colors.white70
            : cs.onSurface.withAlpha(170);

        return StatefulBuilder(
          builder: (context, setSheetState) {
            Widget actionButton({
              required String label,
              required IconData icon,
              required Color accent,
              required VoidCallback onTap,
            }) {
              return TextButton.icon(
                onPressed: onTap,
                icon: Icon(icon, size: 14),
                label: Text(label),
                style: TextButton.styleFrom(
                  foregroundColor: accent,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                    side: BorderSide(color: _opacity(accent, 0.35)),
                  ),
                ),
              );
            }

            Widget row(int slot) {
              final hasData = exists[slot] ?? false;
              final displayName =
                  customNames[slot] ?? _defaultPresetName(slot, isThai);
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: _opacity(const Color(0xFFF59E0B), 0.18),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '$slot',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFF59E0B),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: titleColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _opacity(
                              hasData
                                  ? const Color(0xFF22C55E)
                                  : const Color(0xFF64748B),
                              0.18,
                            ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            hasData
                                ? (isThai ? 'มีข้อมูล' : 'Saved')
                                : (isThai ? 'ว่าง' : 'Empty'),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: hasData
                                  ? const Color(0xFF22C55E)
                                  : subtitleColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (hasData)
                          actionButton(
                            label: isThai ? 'โหลด' : 'Load',
                            icon: Icons.download_rounded,
                            accent: const Color(0xFF22C55E),
                            onTap: () async {
                              gamepadBuzz();
                              await _loadPreset(slot);
                              if (context.mounted) Navigator.pop(context);
                            },
                          ),
                        if (hasData)
                          actionButton(
                            label: isThai ? 'ล้าง' : 'Clear',
                            icon: Icons.delete_outline_rounded,
                            accent: const Color(0xFFEF4444),
                            onTap: () async {
                              gamepadBuzz();
                              await prefs.remove(_presetKey(slot));
                              exists[slot] = false;
                              customNames.remove(slot);
                              if (context.mounted) {
                                setSheetState(() {});
                              }
                            },
                          ),
                        actionButton(
                          label: isThai ? 'บันทึก' : 'Save',
                          icon: Icons.save_outlined,
                          accent: const Color(0xFF3B82F6),
                          onTap: () async {
                            gamepadBuzz();
                            final name = await _promptPresetName(
                              context: context,
                              currentName: customNames[slot],
                            );
                            if (name == null) return;
                            await _savePreset(slot, name: name);
                            exists[slot] = true;
                            final trimmed = name.trim();
                            if (trimmed.isEmpty) {
                              customNames.remove(slot);
                            } else {
                              customNames[slot] = trimmed;
                            }
                            if (context.mounted) {
                              setSheetState(() {});
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }

            final media = MediaQuery.of(context);
            final maxSheetHeight = media.size.height * 0.7;
            return Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              decoration: BoxDecoration(
                color: sheetBg,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: sheetBorder),
                boxShadow: [
                  BoxShadow(
                    color: _opacity(Colors.black, isDark ? 0.28 : 0.12),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxSheetHeight),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: _opacity(const Color(0xFFF59E0B), 0.18),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.bookmark_rounded,
                              size: 16,
                              color: Color(0xFFF59E0B),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isThai ? 'ค่าที่ตั้งไว้' : 'Presets',
                              style: TextStyle(
                                color: titleColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.only(left: 2),
                        child: Text(
                          isThai
                              ? 'บันทึกและเรียกใช้งานรูปแบบปุ่มพร้อมค่า Lo/Med/Hi'
                              : 'Save and load button layouts with Lo/Med/Hi speed.',
                          style: TextStyle(color: subtitleColor, fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: 8),
                      row(1),
                      row(2),
                      row(3),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonalIcon(
                          onPressed: () {
                            gamepadBuzz();
                            Navigator.pop(context);
                          },
                          icon: const Icon(Icons.close_rounded, size: 16),
                          label: Text(isThai ? 'ปิด' : 'Close'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showOverlapWarning() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastOverlapWarningMs < 900) return;
    _lastOverlapWarningMs = now;
    final isThai = LanguageController.isThai.value;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          isThai ? 'ปุ่มห้ามซ้อนทับกัน' : 'Buttons cannot overlap.',
        ),
        duration: const Duration(milliseconds: 900),
      ),
    );
  }

  void _showBoundaryWarning() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastBoundaryWarningMs < 900) return;
    _lastBoundaryWarningMs = now;
    final isThai = LanguageController.isThai.value;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          isThai
              ? 'ปุ่มต้องอยู่ภายในขอบเขตปลอดภัย'
              : 'Buttons must stay inside the safe zone.',
        ),
        duration: const Duration(milliseconds: 900),
      ),
    );
  }

  void _sendBinary({bool force = false}) {
    if (!BleManager.instance.isConnected) return;
    final owner = _bleTrafficOwner;
    if (owner == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final key = _packetKey();

    if (!force) {
      if ((now - _lastSendMs) < kMaxSendMs) return;

      final bool changed = key != _lastPacketKey;
      final bool active = _command != '0';
      final int minInterval = active ? kMinActiveMs : kMinIdleMs;

      if (!changed && (now - _lastSendMs) < minInterval) {
        return;
      }
    }

    _lastPacketKey = key;
    _lastSendMs = now;

    unawaited(
      BleManager.instance.sendJoystickBinary(
        packet: JoystickPacket(lx: 0, ly: 0, rx: 0, ry: 0),
        pressedButtons: _buildPressedButtons(),
        owner: owner,
        force: force,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _bleTrafficOwner = BleManager.instance.claimTrafficMode(
      BleTrafficMode.controlBinary,
      ownerName: 'gamepad_4',
    );
    final trafficOwner = _bleTrafficOwner;
    if (trafficOwner != null) {
      BleManager.instance.enableControlReconnect(
        owner: trafficOwner,
        ownerName: 'gamepad_4',
      );
    }
    OrientationUtils.setLandscapeOnly();
    _tutorialThai = LanguageController.isThai.value;
    _langListener = () {
      final next = LanguageController.isThai.value;
      if (next != _tutorialThai) {
        setState(() => _tutorialThai = next);
      }
    };
    LanguageController.isThai.addListener(_langListener);
    _sendSpeed('Med');
    _loadLayouts();
    _maybeStartTutorial();
    if (trafficOwner != null) {
      unawaited(
        BleManager.instance.autoConnectLastDevice(
          source: 'control_initial',
          owner: trafficOwner,
        ),
      );
    }

    // ชั้น 3: reset input state เมื่อ BLE หลุด/reconnect
    _bleConnSub = BleManager.instance.connectionStream.listen((connected) {
      if (!mounted) return;
      _resetInputState();
      if (connected) {
        _sendBinary(force: true);
      }
    });

    _tick = Timer.periodic(
      const Duration(milliseconds: kLoopMs),
      (_) => _sendLoop(),
    );
  }

  @override
  void dispose() {
    _editWarningTimer?.cancel();
    _tick?.cancel();
    _bleConnSub?.cancel();
    LanguageController.isThai.removeListener(_langListener);

    final trafficOwner = _bleTrafficOwner;
    _bleTrafficOwner = null;
    if (trafficOwner != null) {
      BleManager.instance.disableControlReconnect(trafficOwner);
    }
    if (BleManager.instance.isConnected && trafficOwner != null) {
      unawaited(
        BleManager.instance.sendControlStop(owner: trafficOwner).whenComplete(
          () {
            BleManager.instance.releaseTrafficMode(trafficOwner);
          },
        ),
      );
    } else if (trafficOwner != null) {
      BleManager.instance.releaseTrafficMode(trafficOwner);
    }
    OrientationUtils.reset();
    super.dispose();
  }

  String _computeCommand() {
    final bool forward = _f && !_b;
    final bool backward = _b && !_f;
    final bool left = _l && !_r;
    final bool right = _r && !_l;

    final v = forward ? 'F' : (backward ? 'B' : '');
    final h = left ? 'L' : (right ? 'R' : '');

    if (v.isEmpty && h.isEmpty) {
      return '0';
    } else if (v.isNotEmpty && h.isEmpty) {
      return v;
    } else if (v.isEmpty && h.isNotEmpty) {
      return h;
    } else {
      return '$v$h';
    }
  }

  void _updateCommandOnly() {
    final cmd = _computeCommand();
    setState(() {
      _command = cmd;
    });
    if (cmd == '0' && BleManager.instance.isConnected) {
      _sendBinary(force: true);
    }
  }

  void _sendLoop() {
    _sendBinary();
  }

  void _sendSpeed(String v) {
    if (_speedLabel == v) return;

    setState(() {
      _speedLabel = v;
    });

    _sendBinary(force: true);
  }

  void _onPressChanged(String id, bool isDown) {
    if (id == 'F') _f = isDown;
    if (id == 'B') _b = isDown;
    if (id == 'L') _l = isDown;
    if (id == 'R') _r = isDown;
    _updateCommandOnly();
  }

  Color _barAccent(String label) {
    switch (label) {
      case 'SPD':
        return const Color(0xFF38BDF8);
      case 'CMD':
        return const Color(0xFFF59E0B);
      case 'DRV':
        return const Color(0xFF22C55E);
      case 'TRN':
        return const Color(0xFFA855F7);
      case 'BLE':
        return const Color(0xFF3B82F6);
      case 'PRESET':
        return const Color(0xFFF59E0B);
      case 'EDIT':
        return const Color(0xFF60A5FA);
      default:
        return Colors.white;
    }
  }

  Widget _buildAppBarBackButton() {
    return GamepadAppBarBackButton(
      buttonKey: _tutorialBackKey,
      onPressed: () {
        gamepadBuzz();
        Navigator.maybePop(context);
      },
    );
  }

  Widget _appBarBadge(String label, String value) {
    IconData icon;
    Color accent;
    switch (label) {
      case 'SPD':
        icon = Icons.speed_rounded;
        accent = _barAccent('SPD');
        break;
      case 'CMD':
        icon = Icons.tune_rounded;
        accent = _barAccent('CMD');
        break;
      default:
        icon = Icons.circle;
        accent = _barAccent(label);
    }
    return GamepadTelemetryChip(
      icon: icon,
      label: label,
      value: value,
      accentColor: accent,
    );
  }

  Color _speedColor(String label) {
    return switch (label) {
      'Lo' => const Color(0xFF2ECC71),
      'Med' => const Color(0xFFFFD54F),
      'Hi' => const Color(0xFFE74C3C),
      _ => Colors.white,
    };
  }

  void _openSpeedMenu() {
    setState(() => _speedMenuOpen = !_speedMenuOpen);
  }

  void _selectSpeedMenuValue(String value) {
    setState(() => _speedMenuOpen = false);
    _sendSpeed(value);
  }

  Widget _buildSpeedMenuPanel() {
    if (!_speedMenuOpen || _editMode) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    final panelWidth = math.min(media.size.width - 24, 168.0);
    final panelTop = media.padding.top + GamepadAppBarMetrics.toolbarHeight + 6;
    final panelBg = isDark
        ? _opacity(const Color(0xFF020817), 0.78)
        : _opacity(const Color(0xFFF8FAFC), 0.94);
    final panelBorder = _opacity(const Color(0xFF7DD3FC), isDark ? 0.45 : 0.24);
    final title = LanguageController.isThai.value ? 'ความเร็ว' : 'Speed';

    return Positioned(
      top: panelTop,
      right: 12,
      child: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: panelWidth,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                decoration: BoxDecoration(
                  color: panelBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: panelBorder),
                  boxShadow: [
                    BoxShadow(
                      color: _opacity(Colors.black, isDark ? 0.22 : 0.08),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: _opacity(
                              const Color(0xFF38BDF8),
                              isDark ? 0.18 : 0.12,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.speed_rounded,
                            size: 12,
                            color: Color(0xFF38BDF8),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w900,
                              color: isDark
                                  ? Colors.white
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: LanguageController.isThai.value
                              ? 'ปิด'
                              : 'Close',
                          onPressed: () =>
                              setState(() => _speedMenuOpen = false),
                          icon: const Icon(Icons.close_rounded, size: 16),
                          color: _opacity(
                            isDark ? Colors.white : theme.colorScheme.onSurface,
                            0.72,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 32,
                            height: 32,
                          ),
                          style: IconButton.styleFrom(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ..._buildSpeedGlassItems(onSelect: _selectSpeedMenuValue),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSpeedGlassItems({required ValueChanged<String> onSelect}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final options = ['Lo', 'Med', 'Hi'];
    return options.map((label) {
      final selected = _speedLabel == label;
      final color = _speedColor(label);
      final bgColor = selected
          ? _opacity(color, isDark ? 0.24 : 0.18)
          : _opacity(
              isDark ? Colors.white : const Color(0xFF0F172A),
              isDark ? 0.04 : 0.03,
            );
      final borderColor = selected
          ? _opacity(color, isDark ? 0.72 : 0.58)
          : _opacity(theme.colorScheme.outline, isDark ? 0.36 : 0.30);
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onSelect(label),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: selected ? color : _opacity(color, 0.55),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? color : _opacity(color, 0.8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                  ),
                  Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    size: 16,
                    color: selected
                        ? color
                        : _opacity(
                            isDark ? Colors.white : const Color(0xFF0F172A),
                            0.34,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _speedPopupButton() {
    return GamepadSpeedTogglePill(
      pillKey: _tutorialSpeedKey,
      expanded: _speedMenuOpen,
      onTap: _openSpeedMenu,
      accent: _speedColor(_speedLabel),
      label: _speedLabel,
    );
  }

  Widget _actionPill({
    required String label,
    required IconData icon,
    required Color accent,
    required VoidCallback? onTap,
    Key? key,
    bool iconOnly = false,
    bool compact = false,
  }) {
    return GamepadActionPill(
      pillKey: key,
      label: label,
      icon: icon,
      accent: accent,
      onTap: onTap,
      iconOnly: iconOnly,
      compact: compact,
    );
  }

  Widget _toolIconPill({
    required IconData icon,
    required String label,
    required Color accent,
    required VoidCallback? onTap,
    Key? key,
    bool active = false,
  }) {
    return GamepadToolIconPill(
      pillKey: key,
      icon: icon,
      label: label,
      accent: accent,
      onTap: onTap,
      active: active,
    );
  }

  Widget _sizeToolPill({required bool enabled, Key? key}) {
    return GamepadSizeToolPill(
      pillKey: key,
      isThai: LanguageController.isThai.value,
      enabled: enabled,
      onDecrease: enabled ? () => _changeSelectedSize(-0.05) : null,
      onIncrease: enabled ? () => _changeSelectedSize(0.05) : null,
    );
  }

  double _editAppBarGap({
    required bool isThai,
    required GamepadAppBarMetrics metrics,
  }) {
    final width = MediaQuery.of(context).size.width;
    final estimatedButtonsWidth = isThai ? 126.0 : 82.0;
    final estimatedDoneWidth = isThai ? 78.0 : 70.0;
    final estimatedDeleteWidth = isThai ? 58.0 : 76.0;
    final estimatedResetWidth = isThai ? 72.0 : 70.0;
    const estimatedToolWidth = 62.0;
    final estimatedSizeWidth = isThai ? 78.0 : 70.0;
    final estimatedContentWidth =
        estimatedButtonsWidth +
        estimatedDoneWidth +
        estimatedDeleteWidth +
        estimatedResetWidth +
        (estimatedToolWidth * 4) +
        estimatedSizeWidth;
    final availableWidth = math.max(
      0.0,
      width - metrics.contentPadding.horizontal - 28.0,
    );
    final remaining = math.max(0.0, availableWidth - estimatedContentWidth);
    return (remaining / 8).clamp(4.0, 10.0);
  }

  Widget _buildEditAppBarRow(bool isThai, double gap) {
    final selectedId = _selectedId;
    final hasSelection = selectedId != null;
    final selectedLocked =
        selectedId != null && _lockedIds.contains(selectedId);
    final sizeEnabled = hasSelection && !selectedLocked;
    final canUndo = _undoStack.isNotEmpty;
    final canRedo = _redoStack.isNotEmpty;
    final children = <Widget>[
      _actionPill(
        key: _tutorialDeleteKey,
        label: isThai ? 'ลบ' : 'Delete',
        icon: Icons.delete_outline,
        accent: const Color(0xFFF87171),
        compact: true,
        onTap: hasSelection ? _removeSelected : null,
      ),
      _actionPill(
        key: _tutorialResetKey,
        label: isThai ? 'รีเซ็ต' : 'Reset',
        icon: Icons.restart_alt,
        accent: const Color(0xFFF59E0B),
        compact: true,
        onTap: _resetLayouts,
      ),
      _toolIconPill(
        key: _tutorialUndoKey,
        icon: Icons.undo_rounded,
        label: isThai ? 'ย้อน' : 'Undo',
        accent: const Color(0xFFA78BFA),
        onTap: canUndo ? _undo : null,
      ),
      _toolIconPill(
        key: _tutorialRedoKey,
        icon: Icons.redo_rounded,
        label: isThai ? 'ทำซ้ำ' : 'Redo',
        accent: const Color(0xFFA78BFA),
        onTap: canRedo ? _redo : null,
      ),
      _toolIconPill(
        key: _tutorialGridKey,
        icon: _showGrid ? Icons.grid_on_rounded : Icons.grid_off_rounded,
        label: isThai ? 'กริด' : 'Grid',
        accent: const Color(0xFF38BDF8),
        active: _showGrid,
        onTap: () => setState(() => _showGrid = !_showGrid),
      ),
      _sizeToolPill(key: _tutorialSizeKey, enabled: sizeEnabled),
      _toolIconPill(
        key: _tutorialLockKey,
        icon: selectedLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
        label: isThai ? 'ล็อก' : 'Lock',
        accent: const Color(0xFFFBBF24),
        active: selectedLocked,
        onTap: hasSelection ? _toggleSelectedLock : null,
      ),
      _actionPill(
        key: _tutorialDoneKey,
        label: isThai ? 'เสร็จสิ้น' : 'Done',
        icon: Icons.edit,
        accent: const Color(0xFF60A5FA),
        compact: true,
        onTap: _toggleEdit,
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

  Widget _buildSpeedPreviewPanel() {
    if (!_showTutorial || !_tutorialSpeedPanelOpen) {
      return const SizedBox.shrink();
    }
    final steps = _tutorialSteps();
    if (_tutorialStep < 0 || _tutorialStep >= steps.length) {
      return const SizedBox.shrink();
    }
    final isThai = LanguageController.isThai.value;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final topInset = MediaQuery.of(context).padding.top;
    final panelTop = topInset + GamepadAppBarMetrics.toolbarHeight + 8;
    final panelWidth = math.min(MediaQuery.of(context).size.width - 24, 210.0);
    return Positioned(
      top: panelTop,
      right: 12,
      child: SizedBox(
        key: _tutorialSpeedPanelKey,
        width: panelWidth,
        child: Material(
          color: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                decoration: BoxDecoration(
                  color: isDark
                      ? _opacity(const Color(0xFF020817), 0.78)
                      : _opacity(const Color(0xFFF8FAFC), 0.94),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: _opacity(
                      const Color(0xFF7DD3FC),
                      isDark ? 0.45 : 0.24,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isThai ? 'ตัวอย่างแผงความเร็ว' : 'Speed Panel Preview',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? Colors.white
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._buildSpeedGlassItems(onSelect: (_) {}),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBlePreviewPanel() {
    if (!_showTutorial) return const SizedBox.shrink();
    final steps = _tutorialSteps();
    if (_tutorialStep < 0 || _tutorialStep >= steps.length) {
      return const SizedBox.shrink();
    }
    final step = steps[_tutorialStep];
    if (!step.openBleSheet) return const SizedBox.shrink();
    final isThai = LanguageController.isThai.value;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final panelWidth = math.min(screenWidth - 24, 560.0);
    final maxPanelHeight = math.max(220.0, screenHeight * 0.58);
    final listMaxHeight = math.min(180.0, maxPanelHeight * 0.48);
    final connected = BleManager.instance.isConnected;
    final titleColor = isDark
        ? _opacity(Colors.white, 0.94)
        : _opacity(theme.colorScheme.onSurface, 0.95);
    final bodyColor = isDark
        ? _opacity(Colors.white, 0.72)
        : _opacity(theme.colorScheme.onSurface, 0.72);
    final tileColor = isDark
        ? _opacity(Colors.white, 0.05)
        : _opacity(const Color(0xFF0F172A), 0.04);
    final tileBorder = isDark
        ? _opacity(Colors.white, 0.08)
        : _opacity(const Color(0xFF0F172A), 0.12);
    final accent = connected
        ? const Color(0xFF22C55E)
        : const Color(0xFF38BDF8);
    final mockDevices = const [('PrinceBot-01', '64:B7:08:6F:D4:06', -45)];

    return Positioned.fill(
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: SizedBox(
              key: _tutorialBlePanelKey,
              width: panelWidth,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: panelWidth,
                  maxHeight: maxPanelHeight,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                        decoration: BoxDecoration(
                          color: isDark
                              ? _opacity(const Color(0xFF020817), 0.78)
                              : _opacity(const Color(0xFFF8FAFC), 0.96),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _opacity(
                              const Color(0xFF7DD3FC),
                              isDark ? 0.40 : 0.22,
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _opacity(
                                Colors.black,
                                isDark ? 0.26 : 0.10,
                              ),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Center(
                              child: Container(
                                width: 30,
                                height: 4,
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: _opacity(accent, isDark ? 0.55 : 0.35),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 18,
                                        height: 18,
                                        decoration: BoxDecoration(
                                          color: _opacity(
                                            accent,
                                            isDark ? 0.20 : 0.12,
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.bluetooth_disabled_rounded,
                                          size: 12,
                                          color: accent,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          isThai
                                              ? 'ยังไม่เชื่อมต่อ'
                                              : 'Not connected',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: titleColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                _blePreviewChip(
                                  label: isThai ? 'ล่าสุด' : 'Last',
                                  icon: Icons.history_rounded,
                                  isDark: isDark,
                                  accent: const Color(0xFF38BDF8),
                                  textColor: titleColor,
                                ),
                                const SizedBox(width: 4),
                                _blePreviewChip(
                                  label: isThai ? 'ค้นหา' : 'Scan',
                                  icon: Icons.search_rounded,
                                  isDark: isDark,
                                  accent: const Color(0xFF38BDF8),
                                  textColor: titleColor,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: listMaxHeight,
                              ),
                              child: SingleChildScrollView(
                                child: Column(
                                  children: [
                                    for (final d in mockDevices) ...[
                                      ListTile(
                                        dense: true,
                                        visualDensity: VisualDensity.compact,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 0,
                                            ),
                                        tileColor: tileColor,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          side: BorderSide(color: tileBorder),
                                        ),
                                        title: Text(
                                          d.$1,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: titleColor,
                                          ),
                                        ),
                                        subtitle: Text(
                                          'MAC: ${d.$2} • RSSI: ${d.$3} dBm',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w400,
                                            color: bodyColor,
                                          ),
                                        ),
                                        trailing: Icon(
                                          Icons.chevron_right_rounded,
                                          color: _opacity(titleColor, 0.45),
                                        ),
                                        onTap: null,
                                      ),
                                      if (d != mockDevices.last)
                                        const SizedBox(height: 6),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                _blePreviewChip(
                                  label: isThai ? 'ลืมอุปกรณ์' : 'Forget',
                                  icon: Icons.delete_outline_rounded,
                                  isDark: isDark,
                                  accent: const Color(0xFFFB7185),
                                  textColor: const Color(0xFFEF4444),
                                ),
                                const SizedBox(width: 6),
                                _blePreviewChip(
                                  label: isThai ? 'ยกเลิก' : 'Cancel',
                                  icon: Icons.close_rounded,
                                  isDark: isDark,
                                  accent: isDark
                                      ? _opacity(Colors.white, 0.28)
                                      : const Color(0xFF94A3B8),
                                  textColor: bodyColor,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildButtonsPreviewPanel() {
    if (!_showTutorial) return const SizedBox.shrink();
    final steps = _tutorialSteps();
    if (_tutorialStep < 0 || _tutorialStep >= steps.length) {
      return const SizedBox.shrink();
    }
    final step = steps[_tutorialStep];
    if (step.titleEn != 'Preview Buttons Panel') {
      return const SizedBox.shrink();
    }
    final isThai = LanguageController.isThai.value;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelWidth = math.min(MediaQuery.of(context).size.width - 24, 560.0);
    return Positioned.fill(
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              key: _tutorialButtonsPanelKey,
              width: panelWidth,
              child: Material(
                color: Colors.transparent,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? _opacity(const Color(0xFF020817), 0.78)
                            : _opacity(const Color(0xFFF8FAFC), 0.96),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _opacity(const Color(0xFF7DD3FC), 0.26),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  isThai ? 'เลือกปุ่มใช้งาน' : 'Buttons',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: null,
                                child: Text(isThai ? 'ยกเลิก' : 'Cancel'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _buttonsPreviewRow(
                            label: isThai ? 'ขึ้น (Forward)' : 'Forward',
                            active: true,
                            isDark: isDark,
                          ),
                          const SizedBox(height: 6),
                          _buttonsPreviewRow(
                            label: isThai ? 'ลง (Backward)' : 'Backward',
                            active: false,
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPresetPreviewPanel() {
    if (!_showTutorial) return const SizedBox.shrink();
    final steps = _tutorialSteps();
    if (_tutorialStep < 0 || _tutorialStep >= steps.length) {
      return const SizedBox.shrink();
    }
    final step = steps[_tutorialStep];
    if (step.titleEn != 'Preview Preset' &&
        step.titleEn != 'Preset Management') {
      return const SizedBox.shrink();
    }

    final isThai = LanguageController.isThai.value;
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final panelWidth = math.min(screenWidth - 24, 560.0);
    final maxPanelHeight = math.max(230.0, screenHeight * 0.60);
    final listMaxHeight = math.min(190.0, maxPanelHeight * 0.54);
    final titleColor = _opacity(theme.colorScheme.onSurface, 0.95);
    final subtitleColor = _opacity(theme.colorScheme.onSurface, 0.62);
    const sheetBg = Color(0xFFF8FAFC);
    final sheetBorder = _opacity(const Color(0xFFCBD5E1), 0.65);

    Widget presetRow({
      required int slot,
      required String name,
      required bool isEmpty,
    }) {
      const badge = Color(0xFFF59E0B);
      final rowBg = _opacity(Colors.white, 0.88);
      final rowBorder = _opacity(const Color(0xFFCBD5E1), 0.72);
      final statusText = isEmpty
          ? (isThai ? 'ว่าง' : 'Empty')
          : (isThai ? 'พร้อมใช้' : 'Ready');
      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
        decoration: BoxDecoration(
          color: rowBg,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: rowBorder),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: _opacity(badge, 0.16),
                    shape: BoxShape.circle,
                    border: Border.all(color: _opacity(badge, 0.40)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$slot',
                    style: const TextStyle(
                      color: badge,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 13.0,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _opacity(const Color(0xFFE2E8F0), 0.85),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: _opacity(const Color(0xFFCBD5E1), 0.85),
                    ),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: _opacity(const Color(0xFF64748B), 0.95),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _opacity(const Color(0xFFDBEAFE), 0.85),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: _opacity(const Color(0xFF93C5FD), 0.85),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.save_outlined,
                      size: 12.5,
                      color: _opacity(const Color(0xFF2563EB), 0.95),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isThai ? 'บันทึก' : 'Save',
                      style: TextStyle(
                        color: _opacity(const Color(0xFF2563EB), 0.95),
                        fontSize: 11.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Positioned.fill(
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: SizedBox(
              width: panelWidth,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: panelWidth,
                  maxHeight: maxPanelHeight,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        decoration: BoxDecoration(
                          color: sheetBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: sheetBorder),
                          boxShadow: [
                            BoxShadow(
                              color: _opacity(Colors.black, 0.14),
                              blurRadius: 18,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: Container(
                                width: 26,
                                height: 4,
                                margin: const EdgeInsets.only(bottom: 6),
                                decoration: BoxDecoration(
                                  color: _opacity(
                                    const Color(0xFF64748B),
                                    0.52,
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: _opacity(
                                      const Color(0xFFF59E0B),
                                      0.16,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.bookmark_rounded,
                                    size: 14,
                                    color: Color(0xFFF59E0B),
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    isThai ? 'ค่าที่ตั้งไว้' : 'Presets',
                                    style: TextStyle(
                                      color: titleColor,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isThai
                                  ? 'บันทึกและเรียกใช้งานรูปแบบปุ่มพร้อมค่า Lo/Med/Hi'
                                  : 'Save and load button layouts with Lo/Med/Hi values.',
                              style: TextStyle(
                                color: subtitleColor,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: listMaxHeight,
                              ),
                              child: SingleChildScrollView(
                                child: Column(
                                  children: [
                                    presetRow(
                                      slot: 1,
                                      name: isThai
                                          ? 'ค่าที่ตั้งไว้ 1'
                                          : 'Preset 1',
                                      isEmpty: true,
                                    ),
                                    presetRow(
                                      slot: 2,
                                      name: isThai
                                          ? 'ค่าที่ตั้งไว้ 2'
                                          : 'Preset 2',
                                      isEmpty: true,
                                    ),
                                  ],
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
            ),
          ),
        ),
      ),
    );
  }

  Widget _buttonsPreviewRow({
    required String label,
    required bool active,
    required bool isDark,
  }) {
    const accent = Color(0xFF38BDF8);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: _opacity(Colors.white, active ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _opacity(active ? accent : Colors.white, active ? 0.56 : 0.12),
        ),
      ),
      child: Row(
        children: [
          Icon(
            active
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
            size: 16,
            color: active
                ? accent
                : _opacity(
                    isDark ? Colors.white : const Color(0xFF0F172A),
                    0.4,
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }

  Widget _blePreviewChip({
    required String label,
    required IconData icon,
    required bool isDark,
    required Color accent,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _opacity(accent, isDark ? 0.15 : 0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _opacity(accent, 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: _opacity(textColor, 0.85)),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _opacity(textColor, 0.86),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTutorialOverlay() {
    if (!_showTutorial) return const SizedBox.shrink();
    final steps = _tutorialSteps();
    final step = steps[_tutorialStep];
    final isPreviewSpdStep = step.openSpeedPanel;
    final isPreviewBleStep = step.openBleSheet;
    final isPreviewButtonsStep = step.titleEn == 'Preview Buttons Panel';
    final isPreviewPresetStep =
        step.titleEn == 'Preview Preset' || step.titleEn == 'Preset Management';
    final isTopPreviewCard =
        isPreviewBleStep || isPreviewButtonsStep || isPreviewPresetStep;
    final isLast = _tutorialStep == steps.length - 1;
    final skin = Theme.of(context).extension<GamepadSkin>();
    final rect = _tutorialTargetKey == step.targetKey
        ? _tutorialTargetRect
        : null;
    final highlightRect = rect;
    final screenSize = MediaQuery.of(context).size;
    final scaledMedia = MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(1.0));
    const double arrowSize = 72;
    const double arrowGap = 4;
    final bool arrowOnLeft = isPreviewSpdStep && highlightRect != null;
    final media = MediaQuery.of(context);
    const double previewCardEstimatedHeight = 210;
    final previewCardTopLimit =
        (screenSize.height -
                media.padding.bottom -
                12 -
                previewCardEstimatedHeight -
                8)
            .clamp(8.0, screenSize.height - arrowSize - 8);
    final bool arrowAbove =
        !arrowOnLeft &&
        highlightRect != null &&
        highlightRect.top > (arrowSize + 24);
    final double arrowLeft = highlightRect == null
        ? 0
        : arrowOnLeft
        ? (highlightRect.left - arrowSize - 10).clamp(
            8.0,
            screenSize.width - arrowSize - 8,
          )
        : (highlightRect.center.dx - (arrowSize / 2)).clamp(
            8.0,
            screenSize.width - arrowSize - 8,
          );
    final double arrowTop = highlightRect == null
        ? 0
        : arrowOnLeft
        ? (highlightRect.center.dy - (arrowSize / 2)).clamp(
            8.0,
            previewCardTopLimit,
          )
        : arrowAbove
        ? (highlightRect.top - arrowSize - arrowGap).clamp(
            8.0,
            screenSize.height - arrowSize - 8,
          )
        : (highlightRect.bottom + arrowGap).clamp(
            8.0,
            screenSize.height - arrowSize - 8,
          );

    final tutorialCardAlignment = isTopPreviewCard
        ? Alignment.topCenter
        : (isPreviewSpdStep ? Alignment.bottomLeft : Alignment.bottomCenter);
    final tutorialCardPadding = isTopPreviewCard
        ? const EdgeInsets.fromLTRB(12, 2, 12, 12)
        : const EdgeInsets.all(12);

    return Positioned.fill(
      child: MediaQuery(
        data: scaledMedia,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            GestureDetector(
              onTap: () {},
              behavior: HitTestBehavior.opaque,
              child: CustomPaint(
                painter: GamepadTutorialMaskPainter(
                  holeRect: highlightRect,
                  radius: 12,
                  color: _opacity(
                    Colors.black,
                    isPreviewButtonsStep
                        ? (Theme.of(context).brightness == Brightness.dark
                              ? 0.64
                              : 0.52)
                        : (Theme.of(context).brightness == Brightness.dark
                              ? 0.58
                              : 0.46),
                  ),
                ),
                child: const SizedBox.expand(),
              ),
            ),
            if (isPreviewButtonsStep) _buildButtonsPreviewPanel(),
            if (isPreviewPresetStep) _buildPresetPreviewPanel(),
            _buildSpeedPreviewPanel(),
            _buildBlePreviewPanel(),
            SafeArea(
              child: Align(
                alignment: tutorialCardAlignment,
                child: Padding(
                  padding: tutorialCardPadding,
                  child: GamepadTutorialFloatingCard(
                    title: _tutorialThai ? step.titleTh : step.titleEn,
                    body: _tutorialThai ? step.bodyTh : step.bodyEn,
                    isThai: _tutorialThai,
                    isLast: isLast,
                    showBack: _tutorialStep > 0,
                    surfaceColor:
                        skin?.tutorialSurface ?? const Color(0xFF1F2329),
                    ctaColor: skin?.tutorialCta ?? const Color(0xFF3B82F6),
                    maxWidth: isPreviewBleStep
                        ? 380
                        : (isTopPreviewCard ? 280 : 420),
                    minHeight: isPreviewBleStep ? 130 : null,
                    roomyCompact: isPreviewBleStep,
                    compact: isTopPreviewCard,
                    onSkip: () {
                      gamepadBuzz();
                      _finishTutorial();
                    },
                    onBack: _tutorialStep > 0
                        ? () {
                            gamepadBuzz();
                            _goTutorialStep(_tutorialStep - 1);
                          }
                        : null,
                    onNext: isLast
                        ? () {
                            gamepadBuzz();
                            _finishTutorial();
                          }
                        : () {
                            gamepadBuzz();
                            _goTutorialStep(_tutorialStep + 1);
                          },
                  ),
                ),
              ),
            ),
            if (highlightRect != null)
              Positioned.fromRect(
                rect: highlightRect,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _opacity(const Color(0xFF7DD3FC), 0.82),
                        width: 2.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _opacity(const Color(0xFF7DD3FC), 0.28),
                          blurRadius: 18,
                          spreadRadius: 1.2,
                        ),
                        BoxShadow(
                          color: _opacity(Colors.white, 0.12),
                          blurRadius: 10,
                          spreadRadius: 0.2,
                          blurStyle: BlurStyle.inner,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (highlightRect != null && !isPreviewBleStep)
              Positioned(
                left: arrowLeft,
                top: arrowTop,
                child: IgnorePointer(
                  child: GamepadTutorialPointer(
                    size: arrowSize,
                    color: const Color(0xFF7DD3FC),
                    direction: arrowOnLeft
                        ? GamepadPointerDirection.right
                        : (arrowAbove
                              ? GamepadPointerDirection.down
                              : GamepadPointerDirection.up),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTutorialPromptOverlay() {
    if (!_showTutorialPrompt || _showTutorial) return const SizedBox.shrink();
    final isThai = LanguageController.isThai.value;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final bodyColor = _opacity(titleColor, 0.72);
    final cardColor = isDark
        ? const Color(0xFF182233)
        : const Color(0xFFF8FAFC);
    final cardBorderColor = isDark
        ? _opacity(const Color(0xFF93C5FD), 0.26)
        : _opacity(const Color(0xFF1D4ED8), 0.16);

    return Positioned.fill(
      child: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: Container(
              color: _opacity(Colors.black, isDark ? 0.54 : 0.45),
            ),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cardBorderColor),
                      boxShadow: [
                        BoxShadow(
                          color: _opacity(Colors.black, isDark ? 0.42 : 0.18),
                          blurRadius: 20,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isThai
                              ? 'ดูคำแนะนำการใช้งานหน้านี้ไหม?'
                              : 'Would you like to view this page guide?',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: titleColor,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isThai
                              ? 'ระบบจะแสดง Tutorial การใช้งานปุ่มและเครื่องมือในหน้า Gamepad 4'
                              : 'The app will show a tutorial for buttons and tools on the Gamepad 4 page.',
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.35,
                            color: bodyColor,
                            fontWeight: FontWeight.w500,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  gamepadBuzz();
                                  _dismissTutorialPrompt();
                                },
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(42),
                                  side: BorderSide(
                                    color: _opacity(
                                      isDark
                                          ? Colors.white
                                          : const Color(0xFF0F172A),
                                      0.28,
                                    ),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  isThai ? 'ข้าม' : 'Skip',
                                  style: TextStyle(
                                    color: _opacity(titleColor, 0.84),
                                    fontWeight: FontWeight.w700,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {
                                  gamepadBuzz();
                                  _startTutorialFromPrompt();
                                },
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(42),
                                  backgroundColor: const Color(0xFF3B82F6),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  isThai ? 'ดู' : 'View',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isThai = LanguageController.isThai.value;
    final appBarMetrics = GamepadAppBarMetrics.forWidth(
      MediaQuery.of(context).size.width,
    );
    return Stack(
      key: _tutorialStackKey,
      children: [
        Scaffold(
          extendBodyBehindAppBar: true,
          appBar: GamepadUnifiedAppBar(
            leading: _editMode ? null : _buildAppBarBackButton(),
            speedToggle: _editMode
                ? _buildEditAppBarRow(
                    isThai,
                    _editAppBarGap(isThai: isThai, metrics: appBarMetrics),
                  )
                : _speedPopupButton(),
            cmdChip: _editMode
                ? null
                : SizedBox(
                    key: _tutorialCmdKey,
                    child: _appBarBadge('CMD', _commandByteLabel()),
                  ),
            drvChip: _editMode
                ? null
                : SizedBox(
                    key: _tutorialSpdKey,
                    child: _appBarBadge('SPD', _speedLabel),
                  ),
            bleBadge: _editMode
                ? null
                : ConnectionStatusBadge(
                    key: _tutorialBtKey,
                    appBarMetrics: appBarMetrics,
                  ),
            actionsBuilder: (gap) {
              if (_editMode) {
                return const SizedBox.shrink();
              }
              return GamepadAppBarActionGroup(
                gap: gap,
                items: [
                  GamepadAppBarActionItem(
                    key: _tutorialCustomizeKey,
                    label: isThai ? 'แก้ไข' : 'Edit',
                    icon: _editMode ? Icons.check_rounded : Icons.tune_rounded,
                    accent: _barAccent('EDIT'),
                    compactOnNarrow: false,
                    onTap: _toggleEdit,
                  ),
                  GamepadAppBarActionItem(
                    key: _tutorialPresetKey,
                    label: isThai ? 'ค่าที่ตั้งไว้' : 'Preset',
                    icon: Icons.bookmark_rounded,
                    accent: _barAccent('PRESET'),
                    onTap: _showPresetSheet,
                  ),
                  GamepadAppBarActionItem(
                    key: _tutorialHelpKey,
                    label: '?',
                    icon: Icons.help_outline,
                    accent: const Color(0xFFEC4899),
                    iconOnly: true,
                    onTap: _restartTutorial,
                  ),
                ],
              );
            },
          ),
          body: Stack(
            children: [
              SafeArea(
                child: Stack(
                  children: [
                    _buildGridOverlay(),
                    LayoutBuilder(
                      builder: (context, cons) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                          child: Center(
                            child: SizedBox.expand(
                              child: _editMode
                                  ? _EditablePadPanel(
                                      ids: _activeIds.toList(),
                                      specs: {
                                        'F:forward': _BtnSpec(
                                          'Forward',
                                          'F',
                                          cfgForward(context),
                                        ),
                                        'F:backward': _BtnSpec(
                                          'Backward',
                                          'B',
                                          cfgBackward(context),
                                        ),
                                        'F:left': _BtnSpec(
                                          'Left',
                                          'L',
                                          cfgLeft(context),
                                        ),
                                        'F:right': _BtnSpec(
                                          'Right',
                                          'R',
                                          cfgRight(context),
                                        ),
                                      },
                                      layout: _layoutAll,
                                      snapToGrid: _showGrid,
                                      onLayoutChanged: (next) {
                                        _layoutAll = next;
                                        _saveLayout(
                                          _prefsLayoutAll,
                                          _layoutAll,
                                        );
                                      },
                                      selectedId: _selectedId,
                                      warningId: _editWarningId,
                                      lockedIds: _lockedIds,
                                      onSelect: _selectButton,
                                      onPanelSize: (size) {
                                        _panelSize = size;
                                      },
                                      onStart: () {
                                        if (_editWarningId != null) {
                                          setState(() => _editWarningId = null);
                                        }
                                        _pushHistory();
                                      },
                                      onCollision: _showOverlapWarning,
                                      onBoundaryWarning: _showBoundaryWarning,
                                    )
                                  : _LayoutPadPanel(
                                      ids: _activeIds.toList(),
                                      specs: {
                                        'F:forward': _BtnSpec(
                                          'Forward',
                                          'F',
                                          cfgForward(context),
                                        ),
                                        'F:backward': _BtnSpec(
                                          'Backward',
                                          'B',
                                          cfgBackward(context),
                                        ),
                                        'F:left': _BtnSpec(
                                          'Left',
                                          'L',
                                          cfgLeft(context),
                                        ),
                                        'F:right': _BtnSpec(
                                          'Right',
                                          'R',
                                          cfgRight(context),
                                        ),
                                      },
                                      layout: _layoutAll,
                                      onLayoutNormalized: (next) {
                                        _layoutAll = next;
                                        _saveLayout(
                                          _prefsLayoutAll,
                                          _layoutAll,
                                        );
                                      },
                                      onPressChanged: _onPressChanged,
                                    ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _buildSpeedMenuPanel(),
        _buildTutorialOverlay(),
        _buildTutorialPromptOverlay(),
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  final double step;
  final Color minorColor;
  final Color majorColor;

  const _GridPainter({
    required this.step,
    required this.minorColor,
    required this.majorColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (step <= 0) return;
    final paint = Paint()..strokeWidth = 1;

    final dx = size.width * step;
    final dy = size.height * step;
    if (dx <= 0 || dy <= 0) return;

    const int majorEvery = 4;
    int ix = 1;
    for (double x = dx; x < size.width; x += dx, ix++) {
      paint.color = (ix % majorEvery == 0) ? majorColor : minorColor;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    int iy = 1;
    for (double y = dy; y < size.height; y += dy, iy++) {
      paint.color = (iy % majorEvery == 0) ? majorColor : minorColor;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) {
    return oldDelegate.step != step ||
        oldDelegate.minorColor != minorColor ||
        oldDelegate.majorColor != majorColor;
  }
}

class _TutorialStep {
  final String titleTh;
  final String bodyTh;
  final String titleEn;
  final String bodyEn;
  final GlobalKey? targetKey;
  final bool? editMode;
  final bool openSpeedPanel;
  final bool openBleSheet;
  const _TutorialStep({
    required this.titleTh,
    required this.bodyTh,
    required this.titleEn,
    required this.bodyEn,
    this.targetKey,
    this.editMode,
    this.openSpeedPanel = false,
    this.openBleSheet = false,
  });
}

class _BtnSpec {
  final String label;
  final String sendValue;
  final BtnCfg cfg;
  const _BtnSpec(this.label, this.sendValue, this.cfg);
}

class _ScaledHoldCfg {
  final BtnCfg cfg;
  final Offset center;
  const _ScaledHoldCfg(this.cfg, this.center);
}

_S _scaleForPanel(Size panel) {
  final sw = panel.width / designW;
  final sh = panel.height / designH;
  final sp = ((sw + sh) / 2.0).clamp(0.75, 1.35);
  return _S(sw, sh, sp);
}

BtnCfg _scaledBaseCfg(BtnCfg base, Size panel) {
  final s = _scaleForPanel(panel);
  return _scaleBtn(base, s).copyWith(margin: EdgeInsets.zero);
}

BtnCfg _scaleHoldCfg(BtnCfg c, double scale) {
  final ip = c.iconPadding;
  return c.copyWith(
    width: c.width * scale,
    height: c.height * scale,
    margin: EdgeInsets.zero,
    radius: c.radius * scale,
    borderWidthOn: c.borderWidthOn * scale,
    borderWidthOff: c.borderWidthOff * scale,
    glowBlurOn: c.glowBlurOn * scale,
    glowSpreadOn: c.glowSpreadOn * scale,
    glowBlurOff: c.glowBlurOff * scale,
    glowSpreadOff: c.glowSpreadOff * scale,
    shadowOffsetOn: Offset(
      c.shadowOffsetOn.dx * scale,
      c.shadowOffsetOn.dy * scale,
    ),
    shadowOffsetOff: Offset(
      c.shadowOffsetOff.dx * scale,
      c.shadowOffsetOff.dy * scale,
    ),
    iconPadding: EdgeInsets.fromLTRB(
      ip.left * scale,
      ip.top * scale,
      ip.right * scale,
      ip.bottom * scale,
    ),
    labelFontSize: c.labelFontSize * scale,
  );
}

double _maxLayoutSizeForPanel(BtnCfg base, Size panel) {
  final unit = GamepadEditMetrics.panelUnit(panel);
  if (unit <= 0) return _minBtnSize;

  final baseScaled = _scaledBaseCfg(base, panel);
  final baseDiameter = math.min(baseScaled.width, baseScaled.height);
  if (baseDiameter <= 0 || baseScaled.width <= 0 || baseScaled.height <= 0) {
    return _minBtnSize;
  }

  final usableWidth = math.max(
    0.0,
    panel.width - (GamepadEditMetrics.safeEdgePad * 2),
  );
  final usableHeight = math.max(
    0.0,
    panel.height -
        GamepadEditMetrics.safeTopEdgePad -
        GamepadEditMetrics.safeEdgePad,
  );
  final widthCap = usableWidth * baseDiameter / (baseScaled.width * unit);
  final heightCap = usableHeight * baseDiameter / (baseScaled.height * unit);
  final cap = math.min(_maxBtnSize, math.min(widthCap, heightCap));

  if (!cap.isFinite || cap <= 0) return _minBtnSize;
  return cap;
}

_ButtonLayout _normalizeLayoutForPanel(
  _ButtonLayout layout,
  BtnCfg base,
  Size panel,
) {
  final maxSize = _maxLayoutSizeForPanel(base, panel);
  final minSize = math.min(_minBtnSize, maxSize);
  return _ButtonLayout(
    _clampUnit(layout.cx, 0.5),
    _clampUnit(layout.cy, 0.5),
    _finiteDouble(layout.size, 0.30).clamp(minSize, maxSize).toDouble(),
  );
}

bool _sameLayout(_ButtonLayout a, _ButtonLayout b) {
  return a.cx == b.cx && a.cy == b.cy && a.size == b.size;
}

double _safeCenterCoordinate({
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

_ScaledHoldCfg _scaledHoldCfg(BtnCfg base, _ButtonLayout layout, Size panel) {
  final w = panel.width;
  final h = panel.height;
  final normalized = _normalizeLayoutForPanel(layout, base, panel);
  final baseScaled = _scaledBaseCfg(base, panel);
  final baseDiameter = math.min(baseScaled.width, baseScaled.height);
  final targetDiameter = GamepadEditMetrics.sizePx(panel, normalized.size);
  final visualScale = baseDiameter > 0 ? (targetDiameter / baseDiameter) : 1.0;
  var cfg = _scaleHoldCfg(baseScaled, visualScale);

  final usableWidth = math.max(0.0, w - (GamepadEditMetrics.safeEdgePad * 2));
  final usableHeight = math.max(
    0.0,
    h - GamepadEditMetrics.safeTopEdgePad - GamepadEditMetrics.safeEdgePad,
  );
  final fitScale = math.min(
    1.0,
    math.min(
      cfg.width > 0 ? usableWidth / cfg.width : 1.0,
      cfg.height > 0 ? usableHeight / cfg.height : 1.0,
    ),
  );
  if (fitScale.isFinite && fitScale > 0 && fitScale < 1.0) {
    cfg = _scaleHoldCfg(cfg, fitScale);
  }

  final cx = _safeCenterCoordinate(
    value: normalized.cx * w,
    extent: w,
    itemExtent: cfg.width,
    leadingPadding: GamepadEditMetrics.safeEdgePad,
    trailingPadding: GamepadEditMetrics.safeEdgePad,
  );
  final cy = _safeCenterCoordinate(
    value: normalized.cy * h,
    extent: h,
    itemExtent: cfg.height,
    leadingPadding: GamepadEditMetrics.safeTopEdgePad,
    trailingPadding: GamepadEditMetrics.safeEdgePad,
  );

  return _ScaledHoldCfg(cfg, Offset(cx, cy));
}

BtnCfg _defaultRenderedCfg(BtnCfg base, Size panel) {
  return _scaledHoldCfg(base, const _ButtonLayout(0.5, 0.5, 0.30), panel).cfg;
}

Map<String, _ButtonLayout> _defaultLayoutForIds(
  Size size,
  Map<String, _BtnSpec> specs,
  List<String> ids,
) {
  final w = size.width;
  final h = size.height;
  final s = _scaleForPanel(size);
  final frame = GamepadEditMetrics.defaultLayoutFrame(size);

  _ButtonLayout make(double x, double y) {
    return _ButtonLayout(x / w, y / h, 0.30);
  }

  final hasForward = ids.contains('F:forward');
  final hasBackward = ids.contains('F:backward');
  final hasLeft = ids.contains('F:left');
  final hasRight = ids.contains('F:right');

  final out = <String, _ButtonLayout>{};

  if (hasForward || hasBackward) {
    final cfgF = hasForward
        ? _defaultRenderedCfg(specs['F:forward']!.cfg, size)
        : null;
    final cfgB = hasBackward
        ? _defaultRenderedCfg(specs['F:backward']!.cfg, size)
        : null;
    final totalHeight = [
      if (cfgF != null) cfgF.height + cfgF.margin.vertical,
      if (cfgB != null) cfgB.height + cfgB.margin.vertical,
    ].fold(0.0, (a, b) => a + b);
    final gapY = (cfgF != null && cfgB != null) ? s.h(_panelColGap) : 0.0;
    final colLeft = frame.left + _panelEdgeInset;
    double y = frame.top + (frame.height - (totalHeight + gapY)) / 2.0;

    if (cfgF != null) {
      y += cfgF.margin.top;
      out['F:forward'] = make(
        colLeft + cfgF.margin.left + cfgF.width / 2,
        y + cfgF.height / 2,
      );
      y += cfgF.height + cfgF.margin.bottom;
      y += gapY;
    }
    if (cfgB != null) {
      y += cfgB.margin.top;
      out['F:backward'] = make(
        colLeft + cfgB.margin.left + cfgB.width / 2,
        y + cfgB.height / 2,
      );
      y += cfgB.height + cfgB.margin.bottom;
    }
  }

  if (hasLeft || hasRight) {
    final cfgL = hasLeft
        ? _defaultRenderedCfg(specs['F:left']!.cfg, size)
        : null;
    final cfgR = hasRight
        ? _defaultRenderedCfg(specs['F:right']!.cfg, size)
        : null;
    final gap = s.w(_panelRowGap);
    final rowWidth =
        [
          if (cfgL != null) cfgL.width + cfgL.margin.horizontal,
          if (cfgR != null) cfgR.width + cfgR.margin.horizontal,
        ].fold(0.0, (a, b) => a + b) +
        ((cfgL != null && cfgR != null) ? gap : 0);
    final maxHeight = [
      if (cfgL != null) cfgL.height + cfgL.margin.vertical,
      if (cfgR != null) cfgR.height + cfgR.margin.vertical,
    ].fold(0.0, math.max);

    double x = frame.right - rowWidth - _panelEdgeInset;
    final y = frame.top + (frame.height - maxHeight) / 2.0;

    if (cfgL != null) {
      final cy = y + cfgL.margin.top + cfgL.height / 2;
      x += cfgL.margin.left;
      out['F:left'] = make(x + cfgL.width / 2, cy);
      x += cfgL.width + cfgL.margin.right;
      if (cfgR != null) x += gap;
    }
    if (cfgR != null) {
      final cy = y + cfgR.margin.top + cfgR.height / 2;
      x += cfgR.margin.left;
      out['F:right'] = make(x + cfgR.width / 2, cy);
      x += cfgR.width + cfgR.margin.right;
    }
  }

  return out;
}

class _ButtonLayout {
  final double cx;
  final double cy;
  final double size;

  const _ButtonLayout(this.cx, this.cy, this.size);

  _ButtonLayout copyWith({double? cx, double? cy, double? size}) {
    return _ButtonLayout(cx ?? this.cx, cy ?? this.cy, size ?? this.size);
  }

  Map<String, double> toJson() => {'cx': cx, 'cy': cy, 'size': size};
}

class _EditSnapshot {
  final Map<String, _ButtonLayout> layoutAll;
  final Set<String> activeIds;
  final Set<String> lockedIds;
  final String? selectedId;

  const _EditSnapshot({
    required this.layoutAll,
    required this.activeIds,
    required this.lockedIds,
    required this.selectedId,
  });
}

class _GuideState {
  final bool showVertical;
  final bool showHorizontal;
  final double? verticalX;
  final double? horizontalY;
  final bool snap;

  const _GuideState({
    required this.showVertical,
    required this.showHorizontal,
    required this.verticalX,
    required this.horizontalY,
    required this.snap,
  });

  const _GuideState.hidden()
    : showVertical = false,
      showHorizontal = false,
      verticalX = null,
      horizontalY = null,
      snap = false;
}

class _EditGuidePainter extends CustomPainter {
  final bool showVertical;
  final bool showHorizontal;
  final double? verticalXFactor;
  final double? horizontalYFactor;
  final Color color;

  const _EditGuidePainter({
    required this.showVertical,
    required this.showHorizontal,
    required this.verticalXFactor,
    required this.horizontalYFactor,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!showVertical && !showHorizontal) return;
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    if (showVertical && verticalXFactor != null) {
      final x = (verticalXFactor!.clamp(0.0, 1.0)) * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    if (showHorizontal && horizontalYFactor != null) {
      final y = (horizontalYFactor!.clamp(0.0, 1.0)) * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant _EditGuidePainter oldDelegate) {
    return oldDelegate.showVertical != showVertical ||
        oldDelegate.showHorizontal != showHorizontal ||
        oldDelegate.verticalXFactor != verticalXFactor ||
        oldDelegate.horizontalYFactor != horizontalYFactor ||
        oldDelegate.color != color;
  }
}

class _EditablePadPanel extends StatefulWidget {
  final List<String> ids;
  final Map<String, _BtnSpec> specs;
  final Map<String, _ButtonLayout> layout;
  final ValueChanged<Map<String, _ButtonLayout>> onLayoutChanged;
  final String? selectedId;
  final String? warningId;
  final Set<String> lockedIds;
  final bool snapToGrid;
  final ValueChanged<String> onSelect;
  final ValueChanged<Size> onPanelSize;
  final VoidCallback? onStart;
  final VoidCallback? onCollision;
  final VoidCallback? onBoundaryWarning;

  const _EditablePadPanel({
    required this.ids,
    required this.specs,
    required this.layout,
    required this.onLayoutChanged,
    required this.selectedId,
    required this.warningId,
    required this.lockedIds,
    required this.snapToGrid,
    required this.onSelect,
    required this.onPanelSize,
    this.onStart,
    this.onCollision,
    this.onBoundaryWarning,
  });

  @override
  State<_EditablePadPanel> createState() => _EditablePadPanelState();
}

class _EditablePadPanelState extends State<_EditablePadPanel> {
  late Map<String, _ButtonLayout> _layout;
  bool _initialized = false;
  _GuideState _guide = const _GuideState.hidden();

  @override
  void initState() {
    super.initState();
    _layout = Map<String, _ButtonLayout>.from(widget.layout);
  }

  @override
  void didUpdateWidget(covariant _EditablePadPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.layout, widget.layout)) {
      _layout = Map<String, _ButtonLayout>.from(widget.layout);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.ids.isEmpty) {
      return Center(
        child: Text(
          'Tap + to add buttons',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        widget.onPanelSize(size);
        final defaults = _defaultLayoutForIds(size, widget.specs, widget.ids);

        bool changed = false;
        if (!_initialized) {
          _initialized = true;
        }
        for (final id in widget.ids) {
          final def = defaults[id];
          if (def != null && _layout[id] == null) {
            _layout[id] = def;
            changed = true;
          }
          final spec = widget.specs[id];
          final current = _layout[id];
          if (spec != null && current != null) {
            final normalized = _normalizeLayoutForPanel(
              current,
              spec.cfg,
              size,
            );
            if (!_sameLayout(current, normalized)) {
              _layout[id] = normalized;
              changed = true;
            }
          }
        }
        _layout.removeWhere((k, _) => !widget.ids.contains(k));
        if (changed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {});
            widget.onLayoutChanged(_layout);
          });
        }

        final guideColor = _guide.snap
            ? _opacity(const Color(0xFFFACC15), 0.95)
            : _opacity(const Color(0xFFFACC15), 0.60);
        return Stack(
          children: [
            IgnorePointer(
              child: CustomPaint(
                painter: _EditGuidePainter(
                  showVertical: _guide.showVertical,
                  showHorizontal: _guide.showHorizontal,
                  verticalXFactor: _guide.verticalX,
                  horizontalYFactor: _guide.horizontalY,
                  color: guideColor,
                ),
                child: const SizedBox.expand(),
              ),
            ),
            ...widget.ids.map((id) {
              final spec = widget.specs[id];
              final layout = _layout[id];
              if (spec == null || layout == null) {
                return const SizedBox.shrink();
              }
              return _EditableButton(
                id: id,
                layout: layout,
                panelSize: size,
                cfg: spec.cfg,
                specs: widget.specs,
                allLayouts: _layout,
                snapToGrid: widget.snapToGrid,
                selected: widget.selectedId == id,
                externalWarning: widget.warningId == id,
                dimmed: widget.selectedId != null && widget.selectedId != id,
                locked: widget.lockedIds.contains(id),
                onChanged: (next) {
                  setState(() => _layout[id] = next);
                },
                onGuideChanged: (g) {
                  if (g.showVertical != _guide.showVertical ||
                      g.showHorizontal != _guide.showHorizontal ||
                      g.verticalX != _guide.verticalX ||
                      g.horizontalY != _guide.horizontalY ||
                      g.snap != _guide.snap) {
                    setState(() => _guide = g);
                  }
                },
                onEnd: () {
                  setState(() => _guide = const _GuideState.hidden());
                  widget.onLayoutChanged(_layout);
                },
                onTap: () => widget.onSelect(id),
                onStart: widget.onStart,
                onCollision: widget.onCollision,
                onBoundaryWarning: widget.onBoundaryWarning,
              );
            }),
          ],
        );
      },
    );
  }
}

class _LayoutPadPanel extends StatelessWidget {
  final List<String> ids;
  final Map<String, _BtnSpec> specs;
  final Map<String, _ButtonLayout> layout;
  final ValueChanged<Map<String, _ButtonLayout>>? onLayoutNormalized;
  final void Function(String id, bool down) onPressChanged;

  const _LayoutPadPanel({
    required this.ids,
    required this.specs,
    required this.layout,
    this.onLayoutNormalized,
    required this.onPressChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (ids.isEmpty) {
      return Center(
        child: Text(
          'No buttons',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        final defaults = _defaultLayoutForIds(size, specs, ids);
        final effective = <String, _ButtonLayout>{...defaults, ...layout};
        final normalizedSavedLayout = Map<String, _ButtonLayout>.from(layout);
        var normalizedSavedChanged = false;

        final children = ids.map((id) {
          final spec = specs[id];
          final l = effective[id];
          if (spec == null || l == null) {
            return const SizedBox.shrink();
          }
          final normalized = _normalizeLayoutForPanel(l, spec.cfg, size);
          final saved = layout[id];
          if (saved != null && !_sameLayout(saved, normalized)) {
            normalizedSavedLayout[id] = normalized;
            normalizedSavedChanged = true;
          }
          final scaled = _scaledHoldCfg(spec.cfg, normalized, size);
          final cx = scaled.center.dx;
          final cy = scaled.center.dy;

          return Positioned(
            left: cx - scaled.cfg.width / 2,
            top: cy - scaled.cfg.height / 2,
            child: SizedBox(
              width: scaled.cfg.width,
              height: scaled.cfg.height,
              child: Center(
                child: GamepadImageHoldButton(
                  label: spec.label,
                  sendValue: spec.sendValue,
                  asset: scaled.cfg.iconAsset ?? '',
                  diameter: math.min(scaled.cfg.width, scaled.cfg.height),
                  showLabel: false,
                  onPressChanged: (id, down) => onPressChanged(id, down),
                ),
              ),
            ),
          );
        }).toList();

        if (normalizedSavedChanged && onLayoutNormalized != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            onLayoutNormalized!(normalizedSavedLayout);
          });
        }

        return Stack(children: children);
      },
    );
  }
}

class _EditableButton extends StatefulWidget {
  final String id;
  final _ButtonLayout layout;
  final Size panelSize;
  final BtnCfg cfg;
  final Map<String, _BtnSpec> specs;
  final Map<String, _ButtonLayout> allLayouts;
  final bool snapToGrid;
  final bool selected;
  final bool externalWarning;
  final bool dimmed;
  final bool locked;
  final ValueChanged<_ButtonLayout> onChanged;
  final ValueChanged<_GuideState>? onGuideChanged;
  final VoidCallback onEnd;
  final VoidCallback onTap;
  final VoidCallback? onStart;
  final VoidCallback? onCollision;
  final VoidCallback? onBoundaryWarning;

  const _EditableButton({
    required this.id,
    required this.layout,
    required this.panelSize,
    required this.cfg,
    required this.specs,
    required this.allLayouts,
    required this.snapToGrid,
    required this.selected,
    this.externalWarning = false,
    required this.dimmed,
    required this.locked,
    required this.onChanged,
    this.onGuideChanged,
    required this.onEnd,
    required this.onTap,
    this.onStart,
    this.onCollision,
    this.onBoundaryWarning,
  });

  @override
  State<_EditableButton> createState() => _EditableButtonState();
}

class _EditableButtonState extends State<_EditableButton> {
  late Offset _startFocal;
  late _ButtonLayout _startLayout;
  late _ScaledHoldCfg _startScaled;
  static const double _snapThresholdPx = 5.0;
  static const double _nearCollisionPx = 10.0;
  static const double _safeEdgePad = GamepadEditMetrics.safeEdgePad;
  static const double _safeTopEdgePad = GamepadEditMetrics.safeTopEdgePad;
  static const double _edgeWarnThresholdPx =
      GamepadEditMetrics.edgeWarnThresholdPx;
  bool _colliding = false;
  bool _nearCollision = false;
  bool _nearEdgeWarning = false;

  void _onScaleStart(ScaleStartDetails d) {
    if (widget.locked) return;
    if (!widget.selected) {
      widget.onTap();
      return;
    }
    _startFocal = d.focalPoint;
    _startLayout = _normalizeLayoutForPanel(
      widget.layout,
      widget.cfg,
      widget.panelSize,
    );
    _startScaled = _scaledHoldCfg(widget.cfg, _startLayout, widget.panelSize);
    _nearEdgeWarning = false;
    widget.onGuideChanged?.call(const _GuideState.hidden());
    widget.onStart?.call();
  }

  (bool, bool) _collisionState(_ButtonLayout movingLayout) {
    final movingScaled = _scaledHoldCfg(
      widget.cfg,
      movingLayout,
      widget.panelSize,
    );
    final movingRadius =
        math.min(movingScaled.cfg.width, movingScaled.cfg.height) / 2;
    final movingCenter = movingScaled.center;
    var near = false;

    for (final entry in widget.allLayouts.entries) {
      final id = entry.key;
      if (id == widget.id) continue;
      final spec = widget.specs[id];
      if (spec == null) continue;
      final otherScaled = _scaledHoldCfg(
        spec.cfg,
        entry.value,
        widget.panelSize,
      );
      final otherRadius =
          math.min(otherScaled.cfg.width, otherScaled.cfg.height) / 2;
      final dx = movingCenter.dx - otherScaled.center.dx;
      final dy = movingCenter.dy - otherScaled.center.dy;
      final dist = math.sqrt((dx * dx) + (dy * dy));
      final minDist = movingRadius + otherRadius;
      if (dist < minDist) {
        return (true, true);
      }
      if (dist < (minDist + _nearCollisionPx)) {
        near = true;
      }
    }
    return (false, near);
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (widget.locked) return;
    if (!widget.selected) return;
    final w = widget.panelSize.width;
    final h = widget.panelSize.height;
    final halfW = _startScaled.cfg.width / 2;
    final halfH = _startScaled.cfg.height / 2;

    final dx = d.focalPoint.dx - _startFocal.dx;
    final dy = d.focalPoint.dy - _startFocal.dy;

    double cx = _startLayout.cx * w + dx;
    double cy = _startLayout.cy * h + dy;

    if (widget.snapToGrid) {
      double nx = _snapToGrid(cx / w);
      double ny = _snapToGrid(cy / h);
      cx = nx * w;
      cy = ny * h;
    }

    final centerX = w / 2;
    final centerY = h / 2;
    final snapX = (cx - centerX).abs() <= _snapThresholdPx;
    final snapY = (cy - centerY).abs() <= _snapThresholdPx;
    if (snapX) cx = centerX;
    if (snapY) cy = centerY;
    widget.onGuideChanged?.call(
      _GuideState(
        showVertical: snapX,
        showHorizontal: snapY,
        verticalX: snapX ? 0.5 : null,
        horizontalY: snapY ? 0.5 : null,
        snap: snapX || snapY,
      ),
    );

    final minX = _safeEdgePad + halfW;
    final maxX = w - _safeEdgePad - halfW;
    final minY = _safeTopEdgePad + halfH;
    final maxY = h - _safeEdgePad - halfH;
    final attemptedOutOfBounds =
        maxX < minX ||
        maxY < minY ||
        cx < minX ||
        cx > maxX ||
        cy < minY ||
        cy > maxY;
    cx = _safeCenterCoordinate(
      value: cx,
      extent: w,
      itemExtent: _startScaled.cfg.width,
      leadingPadding: _safeEdgePad,
      trailingPadding: _safeEdgePad,
    );
    cy = _safeCenterCoordinate(
      value: cy,
      extent: h,
      itemExtent: _startScaled.cfg.height,
      leadingPadding: _safeTopEdgePad,
      trailingPadding: _safeEdgePad,
    );
    final nearEdge =
        attemptedOutOfBounds ||
        ((cx - minX).abs() <= _edgeWarnThresholdPx) ||
        ((maxX - cx).abs() <= _edgeWarnThresholdPx) ||
        ((cy - minY).abs() <= _edgeWarnThresholdPx) ||
        ((maxY - cy).abs() <= _edgeWarnThresholdPx);
    if (nearEdge != _nearEdgeWarning) {
      setState(() => _nearEdgeWarning = nearEdge);
      if (nearEdge) {
        widget.onBoundaryWarning?.call();
      }
    }
    final candidate = _ButtonLayout(cx / w, cy / h, _startLayout.size);
    final collisionState = _collisionState(candidate);
    final collides = collisionState.$1;
    final near = collisionState.$2;
    if (near != _nearCollision) {
      setState(() => _nearCollision = near);
    }
    if (collides) {
      if (!_colliding) {
        HapticFeedback.vibrate();
        setState(() => _colliding = true);
        widget.onCollision?.call();
      }
      return;
    }
    if (_colliding) {
      setState(() => _colliding = false);
    }
    widget.onChanged(candidate);
  }

  @override
  Widget build(BuildContext context) {
    final scaled = _scaledHoldCfg(widget.cfg, widget.layout, widget.panelSize);
    final cx = scaled.center.dx;
    final cy = scaled.center.dy;
    final diameter = math.min(scaled.cfg.width, scaled.cfg.height);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final selectedGlow = primary.withAlpha(
      ((isDark ? 0.65 : 0.45) * 255).round(),
    );
    final warningColor = const Color(0xFFEF4444);
    final showWarning =
        _colliding ||
        _nearCollision ||
        _nearEdgeWarning ||
        widget.externalWarning;
    final dimOpacity = widget.dimmed ? 0.35 : 1.0;
    final buttonContent = SizedBox(
      width: diameter,
      height: diameter,
      child: ClipOval(
        child: AnimatedScale(
          scale: widget.selected ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOutBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 50),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: widget.selected
                  ? [
                      BoxShadow(
                        color: selectedGlow,
                        blurRadius: 18,
                        spreadRadius: 2,
                      ),
                    ]
                  : const [],
            ),
            child: ColorFiltered(
              colorFilter: widget.selected
                  ? const ColorFilter.matrix([
                      1,
                      0,
                      0,
                      0,
                      51,
                      0,
                      1,
                      0,
                      0,
                      51,
                      0,
                      0,
                      1,
                      0,
                      51,
                      0,
                      0,
                      0,
                      1,
                      0,
                    ])
                  : const ColorFilter.matrix([
                      1,
                      0,
                      0,
                      0,
                      0,
                      0,
                      1,
                      0,
                      0,
                      0,
                      0,
                      0,
                      1,
                      0,
                      0,
                      0,
                      0,
                      0,
                      1,
                      0,
                    ]),
              child: Padding(
                padding: EdgeInsets.all(diameter * 0.08),
                child: ClipOval(
                  child: Image.asset(
                    scaled.cfg.iconAsset ?? '',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Positioned(
      left: cx - scaled.cfg.width / 2,
      top: cy - scaled.cfg.height / 2,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: widget.locked ? null : _onScaleStart,
        onScaleUpdate: widget.locked ? null : _onScaleUpdate,
        onScaleEnd: widget.locked
            ? null
            : (_) {
                widget.onGuideChanged?.call(const _GuideState.hidden());
                if (_colliding || _nearCollision || _nearEdgeWarning) {
                  setState(() {
                    _colliding = false;
                    _nearCollision = false;
                    _nearEdgeWarning = false;
                  });
                }
                widget.onEnd();
              },
        onTap: widget.onTap,
        child: Opacity(
          opacity: dimOpacity,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            width: scaled.cfg.width,
            height: scaled.cfg.height,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: showWarning
                  ? Border.all(color: _opacity(warningColor, 0.96), width: 3)
                  : null,
              boxShadow: showWarning
                  ? [
                      BoxShadow(
                        color: _opacity(warningColor, 0.46),
                        blurRadius: 14,
                        spreadRadius: 2,
                      ),
                    ]
                  : const [],
            ),
            child: Center(child: IgnorePointer(child: buttonContent)),
          ),
        ),
      ),
    );
  }
}
