// lib/pages/joystick.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';
import 'dart:io';
import 'package:flutter/cupertino.dart' hide Text;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/ble/ble_manager.dart';
import '../joystick_controller.dart';
import '../widgets/joystick_widget.dart';
import '../joystick_view.dart';
import '../../../../core/widgets/connection_status_badge.dart';
import '../../../../core/utils/orientation_utils.dart';
import '../joystick_theme.dart';
import '../../../controller/controller_home_page.dart';
import '../../../../core/ble/joystick_packet.dart';
import '../../../../core/ui/gamepad_assets.dart';
import '../../../../core/ui/gamepad_components.dart';
import '../../../../core/ui/gamepad_edit_metrics.dart';
import '../../../../core/ui/gamepad_tutorial_overlay_components.dart';
import '../../../../core/widgets/gamepad_app_bar.dart';
import '../../../../core/widgets/gamepad_appbar_controls.dart';
import '../../../../core/ui/language_controller.dart';
import '../../../gamepad/widgets/gamepad_telemetry_chip.dart';
import '../../../gamepad/widgets/gamepad_edit_shared.dart';

const double kJoyMinSize = 0.6;
const double kJoyMaxSize = 1.6;
const double kJoyBtnMinSize = 0.6;
const double kJoyBtnMaxSize = 1.6;
const double _gridStep = 0.05;

const String kJoyLeftId = 'joy_left';
const String kJoyRightId = 'joy_right';
const String kJoyYOnlyId = 'joy_y_only';
const String kJoyXOnlyId = 'joy_x_only';
const String kBtnTriangleId = 'btn_triangle';
const String kBtnCrossId = 'btn_cross';
const String kBtnSquareId = 'btn_square';
const String kBtnCircleId = 'btn_circle';
const Set<String> kJoyDefaultActiveIds = {kJoyLeftId, kJoyRightId};

double _clampInitialJoySize(double? value) {
  return GamepadEditMetrics.finiteDouble(
    value,
    1.0,
  ).clamp(kJoyMinSize, kJoyMaxSize).toDouble();
}

double _snapToGrid(double value) {
  if (_gridStep <= 0) return value;
  return (value / _gridStep).round() * _gridStep;
}

class JoystickPage extends StatefulWidget {
  const JoystickPage({super.key});

  @override
  State<JoystickPage> createState() => _JoystickPageState();
}

class _JoystickPageState extends State<JoystickPage> {
  static const Color _cmdAccent = Color(0xFFF59E0B);
  static const Color _jlAccent = Color(0xFF22C55E);
  static const Color _jrAccent = Color(0xFF38BDF8);
  final JoystickController _controller = JoystickController();
  Timer? _timer;

  static const _prefsLayout = 'joy_dual_layout';
  static const _prefsActive = 'joy_dual_active';
  static const double _baseJoyRatio = 0.45;
  static const _prefsTutorialSeen = 'joy_tutorial_seen';
  static const _prefsTutorialPromptSeen = 'joy_tutorial_prompt_seen';
  static const _prefsPreset1 = 'joy_preset_1';
  static const _prefsPreset2 = 'joy_preset_2';
  static const _prefsPreset3 = 'joy_preset_3';

  bool _editMode = false;
  bool _menuOpen = false;
  Offset? _menuAnchor;
  String? _selectedId;
  Size? _panelSize;
  Map<String, _JoyLayout> _layout = {};
  Set<String> _activeIds = {kJoyLeftId, kJoyRightId};
  final Set<String> _lockedIds = {};
  final List<_EditSnapshot> _undoStack = [];
  final List<_EditSnapshot> _redoStack = [];
  static const int _maxHistory = 30;
  int _dragCount = 0;
  bool _showVGuide = false;
  bool _showHGuide = false;
  bool _guideSnap = false;
  double? _guideV;
  double? _guideH;
  String? _editWarningId;
  Timer? _editWarningTimer;
  bool _restoreAutoOrientationOnExit = false;
  int _lastBoundaryWarningMs = 0;
  int _lastOverlapWarningMs = 0;

  bool _triangle = false;
  bool _cross = false;
  bool _square = false;
  bool _circle = false;
  int _lastButtonsKey = 0;

  double _smoothLX = 0.0, _smoothLY = 0.0;
  double _smoothRX = 0.0, _smoothRY = 0.0;

  double _lastLX = 0.0, _lastLY = 0.0;
  double _lastRX = 0.0, _lastRY = 0.0;

  static const double _deadZone = 0.05;
  static const double _smooth = 0.85;
  static const double _delta = 0.005;
  static const int _activeKeepaliveMs = 50;
  int _lastControlSendMs = 0;

  int _debugTick = 0;

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  String _fmt(double v) => v.toStringAsFixed(2);
  String _leftDebug = "X:0.00 Y:0.00";
  String _rightDebug = "X:0.00 Y:0.00";

  bool _showTutorial = false;
  bool _showTutorialPrompt = false;
  int _tutorialStep = 0;
  bool _tutorialThai = true;
  bool _showGrid = false;
  late final VoidCallback _langListener;
  Rect? _tutorialTargetRect;
  GlobalKey? _tutorialTargetKey;

  Color _opacity(Color color, double opacity) =>
      color.withAlpha((opacity * 255).round());
  final GlobalKey _tutorialStackKey = GlobalKey();
  final GlobalKey _tutorialBackKey = GlobalKey();
  final GlobalKey _tutorialCustomizeKey = GlobalKey();
  final GlobalKey _tutorialDoneKey = GlobalKey();
  final GlobalKey _tutorialItemsKey = GlobalKey();
  final GlobalKey _tutorialAreaKey = GlobalKey();
  final GlobalKey _tutorialBtKey = GlobalKey();
  final GlobalKey _tutorialBlePanelKey = GlobalKey();
  final GlobalKey _tutorialPresetPanelKey = GlobalKey();
  final GlobalKey _tutorialPresetKey = GlobalKey();
  final GlobalKey _tutorialHelpKey = GlobalKey();
  final GlobalKey _tutorialCmdKey = GlobalKey();
  final GlobalKey _tutorialJlKey = GlobalKey();
  final GlobalKey _tutorialJrKey = GlobalKey();
  final GlobalKey _tutorialEditBarKey = GlobalKey();
  final GlobalKey _tutorialGridKey = GlobalKey();
  final GlobalKey _tutorialSizeKey = GlobalKey();
  final GlobalKey _tutorialLockKey = GlobalKey();
  final GlobalKey _tutorialUndoKey = GlobalKey();
  final GlobalKey _tutorialRedoKey = GlobalKey();
  final GlobalKey _tutorialRemoveKey = GlobalKey();
  final GlobalKey _tutorialResetKey = GlobalKey();
  final ConnectionStatusBadgeController _bleBadgeController =
      ConnectionStatusBadgeController();
  bool _tutorialButtonsSheetOpened = false;
  StreamSubscription<bool>? _bleConnSub;
  int? _bleTrafficOwner;

  void _resetInputState() {
    void apply() {
      _smoothLX = 0;
      _smoothLY = 0;
      _smoothRX = 0;
      _smoothRY = 0;
      _lastLX = 0;
      _lastLY = 0;
      _lastRX = 0;
      _lastRY = 0;
      _triangle = false;
      _cross = false;
      _square = false;
      _circle = false;
      _lastButtonsKey = 0;
      _controller.setLeftJoystick(0, 0);
      _controller.setRightJoystick(0, 0);
      _setLeftDebug(0, 0);
      _setRightDebug(0, 0);
    }

    if (mounted) {
      setState(apply);
    } else {
      apply();
    }
  }

  void _setLeftDebug(double x, double y) {
    _leftDebug = "X:${_fmt(x)} Y:${_fmt(y)}";
  }

  void _setRightDebug(double x, double y) {
    _rightDebug = "X:${_fmt(x)} Y:${_fmt(y)}";
  }

  void _sendBinary(
    JoystickPacket packet, {
    Set<int>? buttons,
    bool force = false,
  }) {
    final owner = _bleTrafficOwner;
    if (owner == null) return;
    _lastControlSendMs = DateTime.now().millisecondsSinceEpoch;
    unawaited(
      BleManager.instance.sendJoystickBinary(
        packet: packet,
        pressedButtons: buttons ?? const <int>{},
        owner: owner,
        force: force,
      ),
    );
  }

  void _resetLeftJoystick() {
    _smoothLX = 0;
    _smoothLY = 0;
    _lastLX = 0;
    _lastLY = 0;

    _controller.setLeftJoystick(0, 0);

    _sendBinary(
      JoystickPacket(lx: 0, ly: 0, rx: _lastRX, ry: _lastRY),
      buttons: _pressedButtons(),
    );
    Future.delayed(const Duration(milliseconds: 20), () {
      _sendBinary(
        JoystickPacket(lx: 0, ly: 0, rx: _lastRX, ry: _lastRY),
        buttons: _pressedButtons(),
      );
    });

    if (mounted) {
      setState(() => _setLeftDebug(0, 0));
    }
  }

  void _resetRightJoystick() {
    _smoothRX = 0;
    _smoothRY = 0;
    _lastRX = 0;
    _lastRY = 0;

    _controller.setRightJoystick(0, 0);

    _sendBinary(
      JoystickPacket(lx: _lastLX, ly: _lastLY, rx: 0, ry: 0),
      buttons: _pressedButtons(),
    );
    Future.delayed(const Duration(milliseconds: 20), () {
      _sendBinary(
        JoystickPacket(lx: _lastLX, ly: _lastLY, rx: 0, ry: 0),
        buttons: _pressedButtons(),
      );
    });

    if (mounted) {
      setState(() => _setRightDebug(0, 0));
    }
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _sendZeroAndClear({bool updateUi = true, int? owner}) {
    _smoothLX = 0;
    _smoothLY = 0;
    _smoothRX = 0;
    _smoothRY = 0;

    _lastLX = 0;
    _lastLY = 0;
    _lastRX = 0;
    _lastRY = 0;

    _triangle = false;
    _cross = false;
    _square = false;
    _circle = false;

    _controller.setLeftJoystick(0, 0);
    _controller.setRightJoystick(0, 0);

    _lastButtonsKey = 0;
    final stopOwner = owner ?? _bleTrafficOwner;
    final stopFuture = stopOwner == null
        ? Future<void>.value()
        : BleManager.instance.sendControlStop(owner: stopOwner);

    if (updateUi && mounted) {
      setState(() {
        _setLeftDebug(0, 0);
        _setRightDebug(0, 0);
      });
    }
    return stopFuture;
  }

  @override
  void initState() {
    super.initState();
    _bleTrafficOwner = BleManager.instance.claimTrafficMode(
      BleTrafficMode.controlBinary,
      ownerName: 'joystick',
    );
    final trafficOwner = _bleTrafficOwner;
    if (trafficOwner != null) {
      BleManager.instance.enableControlReconnect(
        owner: trafficOwner,
        ownerName: 'joystick',
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
    _loadLayout();
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
        _sendBinary(
          JoystickPacket(lx: 0, ly: 0, rx: 0, ry: 0),
          buttons: _pressedButtons(),
          force: true,
        );
      }
    });

    _timer = Timer.periodic(const Duration(milliseconds: 25), (_) {
      if (_editMode) return;
      final packet = _controller.buildPacket();
      final buttonsKey = _buttonsKey();
      final buttonsChanged = buttonsKey != _lastButtonsKey;

      const zeroEps = 0.015;

      final nearZero =
          packet.lx.abs() < zeroEps &&
          packet.ly.abs() < zeroEps &&
          packet.rx.abs() < zeroEps &&
          packet.ry.abs() < zeroEps;

      if (nearZero &&
          (_lastLX != 0 || _lastLY != 0 || _lastRX != 0 || _lastRY != 0)) {
        _lastLX = 0;
        _lastLY = 0;
        _lastRX = 0;
        _lastRY = 0;

        _smoothLX = 0;
        _smoothLY = 0;
        _smoothRX = 0;
        _smoothRY = 0;

        _controller.setLeftJoystick(0, 0);
        _controller.setRightJoystick(0, 0);

        _lastButtonsKey = buttonsKey;
        _sendBinary(
          JoystickPacket(lx: 0, ly: 0, rx: 0, ry: 0),
          buttons: _pressedButtons(),
        );
        Future.delayed(const Duration(milliseconds: 20), () {
          _sendBinary(
            JoystickPacket(lx: 0, ly: 0, rx: 0, ry: 0),
            buttons: _pressedButtons(),
          );
        });

        if (mounted && !_menuOpen) {
          setState(() {
            _setLeftDebug(0, 0);
            _setRightDebug(0, 0);
          });
        }
        return;
      }

      final changed =
          (packet.lx - _lastLX).abs() > _delta ||
          (packet.ly - _lastLY).abs() > _delta ||
          (packet.rx - _lastRX).abs() > _delta ||
          (packet.ry - _lastRY).abs() > _delta;

      if (!changed && !buttonsChanged) {
        final active = !nearZero || buttonsKey != 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (!active || now - _lastControlSendMs < _activeKeepaliveMs) {
          return;
        }
      }

      _lastLX = packet.lx;
      _lastLY = packet.ly;
      _lastRX = packet.rx;
      _lastRY = packet.ry;
      _lastButtonsKey = buttonsKey;

      _sendBinary(packet, buttons: _pressedButtons());

      _debugTick++;
      if (!mounted) return;
      if (_debugTick % 3 == 0 && !_menuOpen) {
        setState(() {
          _setLeftDebug(packet.lx, packet.ly);
          _setRightDebug(packet.rx, packet.ry);
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _restoreAutoOrientationOnExit =
        MediaQuery.sizeOf(context).shortestSide >=
        OrientationUtils.tabletShortestSide;
  }

  @override
  void dispose() {
    _stopTimer();
    _editWarningTimer?.cancel();
    _bleConnSub?.cancel();
    final trafficOwner = _bleTrafficOwner;
    _bleTrafficOwner = null;
    if (trafficOwner != null) {
      BleManager.instance.disableControlReconnect(trafficOwner);
    }
    unawaited(
      _sendZeroAndClear(updateUi: false, owner: trafficOwner).whenComplete(() {
        if (trafficOwner != null) {
          BleManager.instance.releaseTrafficMode(trafficOwner);
        }
      }),
    );
    LanguageController.isThai.removeListener(_langListener);
    OrientationUtils.restoreAfterControl(
      isTablet: _restoreAutoOrientationOnExit,
    );
    super.dispose();
  }

  (double, double) _process(double rawX, double rawY, double sx, double sy) {
    double x = (rawX.abs() < _deadZone) ? 0 : rawX;
    double y = (rawY.abs() < _deadZone) ? 0 : rawY;

    final fx = _lerp(sx, x, _smooth);
    final fy = _lerp(sy, y, _smooth);

    const eps = 0.01;
    final snapX = (fx.abs() < eps) ? 0.0 : fx;
    final snapY = (fy.abs() < eps) ? 0.0 : fy;

    return (snapX, snapY);
  }

  Set<int> _pressedButtons() {
    final btns = <int>{};
    if (_triangle) btns.add(kBleBtnTriangle);
    if (_cross) btns.add(kBleBtnCross);
    if (_square) btns.add(kBleBtnSquare);
    if (_circle) btns.add(kBleBtnCircle);
    return btns;
  }

  int _buttonsKey() {
    final btns = _pressedButtons();
    int v = 0;
    for (final b in btns) {
      if (b < 1 || b > 8) continue;
      v |= (1 << (b - 1));
    }
    return v & 0xFF;
  }

  String _cmdLabel() => _buttonsKey().toString();

  double _baseJoySize(Size panel) =>
      math.min(panel.width, panel.height) * _baseJoyRatio;

  double _baseBtnSize(Size panel) => _baseJoySize(panel) * 0.55;

  Map<String, _JoyLayout> _defaultLayout(Size panel, Set<String> active) {
    final out = <String, _JoyLayout>{};
    if (active.contains(kJoyLeftId)) {
      out[kJoyLeftId] = const _JoyLayout(0.25, 0.5, 1.0);
    }
    if (active.contains(kJoyYOnlyId)) {
      out[kJoyYOnlyId] = const _JoyLayout(0.25, 0.5, 1.0);
    }
    if (active.contains(kJoyRightId)) {
      out[kJoyRightId] = const _JoyLayout(0.75, 0.5, 1.0);
    }
    if (active.contains(kJoyXOnlyId)) {
      out[kJoyXOnlyId] = const _JoyLayout(0.75, 0.5, 1.0);
    }

    final buttonIds = <String>[
      if (active.contains(kBtnTriangleId)) 'R:triangle',
      if (active.contains(kBtnCrossId)) 'R:cross',
      if (active.contains(kBtnSquareId)) 'R:square',
      if (active.contains(kBtnCircleId)) 'R:circle',
    ];
    if (buttonIds.isNotEmpty) {
      final buttonDefaults = buildDualClusterDefaultLayout(panel, buttonIds);
      final idMap = <String, String>{
        'R:triangle': kBtnTriangleId,
        'R:cross': kBtnCrossId,
        'R:square': kBtnSquareId,
        'R:circle': kBtnCircleId,
      };
      final joyBaseButtonSize = _baseBtnSize(panel);
      final panelMinSide = math.min(panel.width, panel.height);
      const rightClusterCenterX = 0.72;
      const actionClusterCenterY = 0.5;
      const clusterTighten = 0.7;
      buttonDefaults.forEach((tempId, layout) {
        final joyId = idMap[tempId];
        if (joyId == null) return;
        final gamepadButtonPx = layout.size * panelMinSide;
        final mappedScale = gamepadButtonPx / joyBaseButtonSize;
        final joySizeScale = (mappedScale * 0.75).clamp(kJoyBtnMinSize, 1.2);
        final tightenedCx =
            rightClusterCenterX +
            ((layout.cx - rightClusterCenterX) * clusterTighten);
        final tightenedCy =
            actionClusterCenterY +
            ((layout.cy - actionClusterCenterY) * clusterTighten);
        out[joyId] = _JoyLayout(tightenedCx, tightenedCy, joySizeScale);
      });
    }
    return out;
  }

  Future<void> _loadLayout() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsLayout);
    final activeRaw = prefs.getString(_prefsActive);
    if (raw != null && raw.isNotEmpty) {
      _layout = _decodeLayout(raw);
    }
    if (activeRaw != null && activeRaw.isNotEmpty) {
      _activeIds = _decodeIdList(activeRaw);
    } else {
      _activeIds = {kJoyLeftId, kJoyRightId};
    }
    _layout.removeWhere((k, _) => !_activeIds.contains(k));
    _lockedIds.removeWhere((id) => !_layout.containsKey(id));
    if (mounted) setState(() {});
  }

  Future<void> _saveLayout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsLayout, jsonEncode(_encodeLayout(_layout)));
  }

  Future<void> _saveActive() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsActive, jsonEncode(_activeIds.toList()));
  }

  Map<String, _JoyLayout> _decodeLayout(String raw) {
    try {
      final obj = jsonDecode(raw);
      if (obj is! Map) return {};
      final out = <String, _JoyLayout>{};
      obj.forEach((k, v) {
        if (v is Map) {
          final cx = (v['cx'] as num?)?.toDouble();
          final cy = (v['cy'] as num?)?.toDouble();
          final size = (v['size'] as num?)?.toDouble() ?? 1.0;
          if (cx != null && cy != null) {
            out[k.toString()] = _JoyLayout(
              GamepadEditMetrics.clampUnit(cx, 0.5),
              GamepadEditMetrics.clampUnit(cy, 0.5),
              _clampInitialJoySize(size),
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
    Map<String, _JoyLayout> layout,
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
      if (_editMode && _panelSize != null) {
        final defaults = _defaultLayout(_panelSize!, _activeIds);
        _layout = {...defaults, ..._layout};
      }
    });
  }

  bool _isLeftJoy(String id) => id == kJoyLeftId || id == kJoyYOnlyId;
  bool _isRightJoy(String id) => id == kJoyRightId || id == kJoyXOnlyId;

  void _selectJoystick(String id) {
    setState(() => _selectedId = id);
  }

  void _toggleSelectedLock() {
    final id = _selectedId;
    if (id == null) return;
    _pushHistory();
    setState(() {
      if (_lockedIds.contains(id)) {
        _lockedIds.remove(id);
      } else {
        _lockedIds.add(id);
      }
    });
  }

  Map<String, _JoyLayout> _cloneLayout(Map<String, _JoyLayout> src) {
    final out = <String, _JoyLayout>{};
    src.forEach((k, v) {
      out[k] = _JoyLayout(v.cx, v.cy, v.size);
    });
    return out;
  }

  _EditSnapshot _captureSnapshot() {
    return _EditSnapshot(
      layout: _cloneLayout(_layout),
      activeIds: Set<String>.from(_activeIds),
      lockedIds: Set<String>.from(_lockedIds),
      selectedId: _selectedId,
    );
  }

  void _applySnapshot(_EditSnapshot snap) {
    _layout = _cloneLayout(snap.layout);
    _activeIds = Set<String>.from(snap.activeIds);
    _lockedIds
      ..clear()
      ..addAll(snap.lockedIds);
    _selectedId = snap.selectedId;

    _layout.removeWhere((k, _) => !_activeIds.contains(k));
    _lockedIds.removeWhere((id) => !_layout.containsKey(id));
    if (_selectedId != null && !_layout.containsKey(_selectedId)) {
      _selectedId = null;
    }
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
    });
    _saveLayout();
    _saveActive();
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    setState(() {
      _undoStack.add(_captureSnapshot());
      _applySnapshot(_redoStack.removeLast());
    });
    _saveLayout();
    _saveActive();
  }

  void _toggleActive(String id) {
    _pushHistory();
    setState(() {
      if (_activeIds.contains(id)) {
        _activeIds.remove(id);
        _layout.remove(id);
        _lockedIds.remove(id);
        if (_selectedId == id) _selectedId = null;
        _clearButtonState(id);
        if (_isLeftJoy(id)) _resetLeftJoystick();
        if (_isRightJoy(id)) _resetRightJoystick();
      } else {
        _activeIds.add(id);
        if (_panelSize != null) {
          final defaults = _defaultLayout(_panelSize!, _activeIds);
          final def = defaults[id];
          if (def != null) {
            _layout[id] = def;
          }
        }
      }
    });
    _saveLayout();
    _saveActive();
  }

  void _removeSelected() {
    final id = _selectedId;
    if (id == null) return;
    _toggleActive(id);
  }

  void _resetLayout() async {
    _pushHistory();
    final defaultActive = Set<String>.from(kJoyDefaultActiveIds);
    final defaultLayout = _panelSize != null
        ? _defaultLayout(_panelSize!, defaultActive)
        : <String, _JoyLayout>{};
    setState(() {
      _layout = defaultLayout;
      _activeIds = defaultActive;
      _lockedIds.clear();
      _selectedId = null;
      _dragCount = 0;
      _showVGuide = false;
      _showHGuide = false;
      _guideSnap = false;
      _guideV = null;
      _guideH = null;
      _clearButtonState(null);
    });
    _resetLeftJoystick();
    _resetRightJoystick();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsLayout);
    await prefs.remove(_prefsActive);
  }

  void _clearButtonState(String? id) {
    if (id == null || id == kBtnTriangleId) _triangle = false;
    if (id == null || id == kBtnCrossId) _cross = false;
    if (id == null || id == kBtnSquareId) _square = false;
    if (id == null || id == kBtnCircleId) _circle = false;
  }

  void _setGuideVisibility(
    bool showV,
    bool showH, {
    bool snap = false,
    double? guideV,
    double? guideH,
  }) {
    if (!mounted) return;
    setState(() {
      _showVGuide = showV;
      _showHGuide = showH;
      _guideV = showV ? guideV : null;
      _guideH = showH ? guideH : null;
      _guideSnap = snap && (showV || showH);
    });
  }

  void _beginDrag() {
    if (!mounted) return;
    setState(() {
      _dragCount += 1;
    });
  }

  void _endDrag() {
    if (!mounted) return;
    setState(() {
      _dragCount = math.max(0, _dragCount - 1);
      if (_dragCount == 0) {
        _showVGuide = false;
        _showHGuide = false;
        _guideSnap = false;
        _guideV = null;
        _guideH = null;
      }
    });
  }

  Widget _buildEditMenu({bool compact = false}) {
    final isThai = LanguageController.isThai.value;
    final accent = const Color(0xFF34D399);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor =
        Color.lerp(
          accent,
          isDark ? Colors.white : theme.colorScheme.onSurface,
          0.4,
        ) ??
        Colors.white;
    final horizontalPadding = compact ? 10.0 : 12.0;
    final fontSize = compact ? 10.0 : 11.0;

    Widget content() {
      return GamepadGlassTopPill(
        pillKey: Platform.isIOS ? null : _tutorialItemsKey,
        onTap: Platform.isIOS
            ? null
            : () {
                gamepadBuzz();
                _openButtonsMenu();
              },
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: 0,
        ),
        child: Center(
          child: Text(
            isThai ? 'เลือกใช้งานปุ่ม' : 'Buttons',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: textColor,
              height: 1.0,
            ),
          ),
        ),
      );
    }

    if (Platform.isIOS) {
      return GestureDetector(
        key: _tutorialItemsKey,
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _menuAnchor = d.globalPosition,
        onTap: () {
          gamepadBuzz();
          _openButtonsMenu();
        },
        child: content(),
      );
    }

    return content();
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

  Widget _sizeToolPill({
    required bool isThai,
    required bool enabled,
    Key? key,
  }) {
    return GamepadSizeToolPill(
      pillKey: key,
      isThai: isThai,
      enabled: enabled,
      onDecrease: () {
        gamepadBuzz();
        _adjustSelectedSize(-0.05);
      },
      onIncrease: () {
        gamepadBuzz();
        _adjustSelectedSize(0.05);
      },
    );
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
      _editMode = false;
      _tutorialButtonsSheetOpened = false;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsTutorialPromptSeen, true);
    _scheduleTutorialRectUpdate();
  }

  void _scheduleTutorialRectUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_showTutorial) return;
      _updateTutorialRect();
      _maybeOpenBleTutorialSheet();
      _maybeOpenButtonsTutorialSheet();
    });
  }

  void _maybeOpenBleTutorialSheet() {
    // Joy now uses an inline BLE preview panel in tutorial mode (same flow as Gamepad).
  }

  void _maybeOpenButtonsTutorialSheet() {
    if (!_showTutorial) return;
    final steps = _tutorialSteps();
    if (_tutorialStep < 0 || _tutorialStep >= steps.length) return;
    final step = steps[_tutorialStep];
    if (!step.openButtonsSheet) {
      _tutorialButtonsSheetOpened = false;
      return;
    }
    if (_tutorialButtonsSheetOpened) return;
    _tutorialButtonsSheetOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_showTutorial) return;
      _openButtonsMenu(showTutorial: true);
    });
  }

  List<_TutorialStep> _tutorialSteps() {
    return [
      const _TutorialStep(
        titleTh: 'Joystick Mode',
        bodyTh:
            'ใช้จอยสติ๊กซ้ายและขวาร่วมกับปุ่มเสริม เพื่อควบคุมการเคลื่อนที่ได้ยืดหยุ่น',
        titleEn: 'Joystick Mode',
        bodyEn:
            'Use the left and right joysticks, along with extra buttons, for flexible movement control.',
      ),
      _TutorialStep(
        titleTh: 'Back',
        bodyTh: 'ย้อนกลับไปยังหน้า Controller',
        titleEn: 'Back',
        bodyEn: 'Go back to the Controller page.',
        targetKey: _tutorialBackKey,
        requiresPlayMode: true,
      ),
      _TutorialStep(
        titleTh: 'ชุดคำสั่ง (CMD)',
        bodyTh:
            'แสดงรหัสคำสั่ง (Byte) ที่ส่งไปยังหุ่นยนต์แบบเรียลไทม์ตามปุ่มที่กด',
        titleEn: 'Command Status (CMD)',
        bodyEn:
            'Displays real-time command bytes sent to the robot based on your input.',
        targetKey: _tutorialCmdKey,
      ),
      _TutorialStep(
        titleTh: 'JL',
        bodyTh: 'JL แสดงค่าพิกัด X,Y ของจอยฝั่งซ้าย',
        titleEn: 'JL',
        bodyEn: 'JL shows left joystick X,Y values.',
        targetKey: _tutorialJlKey,
      ),
      _TutorialStep(
        titleTh: 'JR',
        bodyTh: 'JR แสดงค่าพิกัด X,Y ของจอยฝั่งขวา',
        titleEn: 'JR',
        bodyEn: 'JR shows right joystick X,Y values.',
        targetKey: _tutorialJrKey,
      ),
      _TutorialStep(
        titleTh: 'สถานะ BLE',
        bodyTh:
            'ตรวจสอบการเชื่อมต่อ และแตะเพื่อเปิดเมนูจัดการอุปกรณ์ (ระบบจะเชื่อมต่ออุปกรณ์ล่าสุดให้เองอัตโนมัติ)',
        titleEn: 'BLE Status',
        bodyEn:
            'View connection status and tap to manage devices. (Automatically reconnects to the last device).',
        targetKey: _tutorialBtKey,
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
      ),
      _TutorialStep(
        titleTh: 'โหมดแก้ไข',
        bodyTh: 'แตะเพื่อเข้าสู่โหมดการปรับแต่งเลย์เอาต์ปุ่ม',
        titleEn: 'Edit Mode',
        bodyEn: 'Enter layout customization mode.',
        targetKey: _tutorialCustomizeKey,
        requiresPlayMode: true,
      ),
      _TutorialStep(
        titleTh: 'เลือกใช้งานปุ่ม',
        bodyTh: 'เลือกปุ่มฝั่งซ้ายหรือขวาที่ต้องการแสดงบนหน้าจอ',
        titleEn: 'Buttons',
        bodyEn: 'Select which left or right buttons to display.',
        targetKey: _tutorialItemsKey,
        requiresEditMode: true,
      ),
      _TutorialStep(
        titleTh: 'เมนูเลือกปุ่ม',
        bodyTh: 'แสดงรายการปุ่มทั้งหมดที่คุณสามารถเลือกใช้งานได้',
        titleEn: 'Button Menu',
        bodyEn: 'View all available buttons you can add to the layout.',
        openButtonsSheet: true,
        requiresEditMode: true,
      ),
      _TutorialStep(
        titleTh: 'ลบปุ่ม',
        bodyTh: 'นำปุ่มที่เลือกไว้ออกจากหน้าจอ',
        titleEn: 'Delete',
        bodyEn: 'Remove the selected button from the layout.',
        targetKey: _tutorialRemoveKey,
        requiresEditMode: true,
      ),
      _TutorialStep(
        titleTh: 'รีเซ็ต',
        bodyTh: 'รีเซ็ตตำแหน่งและขนาดปุ่มทั้งหมดกลับเป็นค่าเริ่มต้น',
        titleEn: 'Reset Layout',
        bodyEn: 'Reset all button positions and sizes to defaults.',
        targetKey: _tutorialResetKey,
        requiresEditMode: true,
      ),
      _TutorialStep(
        titleTh: 'ย้อน',
        bodyTh: 'ย้อนการแก้ไขล่าสุด',
        titleEn: 'Undo',
        bodyEn: 'Undo latest edit action.',
        targetKey: _tutorialUndoKey,
        requiresEditMode: true,
      ),
      _TutorialStep(
        titleTh: 'ทำซ้ำ',
        bodyTh: 'ทำซ้ำการแก้ไขที่ย้อนกลับไป',
        titleEn: 'Redo',
        bodyEn: 'Redo the undone edit action.',
        targetKey: _tutorialRedoKey,
        requiresEditMode: true,
      ),
      _TutorialStep(
        titleTh: 'กริด',
        bodyTh: 'เปิด/ปิดเส้นกริดเพื่อช่วยในการจัดวางปุ่มให้แม่นยำ',
        titleEn: 'Grid',
        bodyEn: 'Toggle grid lines for precise button alignment.',
        targetKey: _tutorialGridKey,
        requiresEditMode: true,
      ),
      _TutorialStep(
        titleTh: 'ขนาด',
        bodyTh: 'ย่อหรือขยายขนาดของปุ่มที่เลือกอยู่',
        titleEn: 'Size',
        bodyEn: 'Scale the selected button up or down.',
        targetKey: _tutorialSizeKey,
        requiresEditMode: true,
      ),
      _TutorialStep(
        titleTh: 'ล็อก',
        bodyTh: 'ล็อกตำแหน่งปุ่มเพื่อป้องกันการเคลื่อนย้ายโดยไม่ตั้งใจ',
        titleEn: 'Lock',
        bodyEn: 'Lock button position to prevent accidental moving.',
        targetKey: _tutorialLockKey,
        requiresEditMode: true,
      ),
      _TutorialStep(
        titleTh: 'เสร็จสิ้น',
        bodyTh: 'บันทึกการตั้งค่าและออกจากโหมดแก้ไข',
        titleEn: 'Done',
        bodyEn: 'Save changes and exit edit mode.',
        targetKey: _tutorialDoneKey,
        requiresEditMode: true,
      ),
      _TutorialStep(
        titleTh: 'ค่าที่ตั้งไว้ (Preset)',
        bodyTh: 'บันทึกหรือเรียกใช้รูปแบบปุ่มและค่าความเร็วที่คุณตั้งไว้',
        titleEn: 'Presets',
        bodyEn: 'Save or load your custom layouts and speed settings.',
        targetKey: _tutorialPresetKey,
        requiresPlayMode: true,
      ),
      _TutorialStep(
        titleTh: 'หน้าจัดการพรีเซ็ต',
        bodyTh: 'เลือกดูและจัดการรายการการตั้งค่าทั้งหมดที่บันทึกไว้',
        titleEn: 'Preset Management',
        bodyEn: 'View and manage all your saved configuration presets.',
        targetKey: _tutorialPresetPanelKey,
        requiresPlayMode: true,
      ),
      _TutorialStep(
        titleTh: 'คำแนะนำการใช้งาน',
        bodyTh: 'แตะที่นี่เพื่อดูคำแนะนำการใช้งานนี้อีกครั้งได้ทุกเมื่อ',
        titleEn: 'Tutorial',
        bodyEn: 'Tap here to replay this tutorial anytime.',
        targetKey: _tutorialHelpKey,
        requiresPlayMode: true,
      ),
    ];
  }

  Color _tutorialHighlightColor(_TutorialStep step) {
    final key = step.targetKey;
    if (key == _tutorialCustomizeKey) {
      return step.requiresEditMode
          ? const Color(0xFF22C55E)
          : const Color(0xFF38BDF8);
    }
    if (key == _tutorialBackKey) return const Color(0xFF93C5FD);
    if (key == _tutorialItemsKey) return const Color(0xFF14B8A6);
    if (key == _tutorialRemoveKey) return const Color(0xFFEF4444);
    if (key == _tutorialResetKey) return const Color(0xFFF59E0B);
    if (key == _tutorialUndoKey || key == _tutorialRedoKey) {
      return const Color(0xFFA78BFA);
    }
    if (key == _tutorialGridKey) return const Color(0xFF38BDF8);
    if (key == _tutorialSizeKey) return const Color(0xFF34D399);
    if (key == _tutorialLockKey) return const Color(0xFFFBBF24);
    if (key == _tutorialEditBarKey) return const Color(0xFF7DD3FC);
    if (key == _tutorialPresetKey) return const Color(0xFFEAB308);
    if (key == _tutorialPresetPanelKey) return const Color(0xFF7DD3FC);
    if (key == _tutorialCmdKey) return _cmdAccent;
    if (key == _tutorialJlKey) return _jlAccent;
    if (key == _tutorialJrKey) return _jrAccent;
    if (key == _tutorialBtKey) return const Color(0xFF60A5FA);
    if (key == _tutorialBlePanelKey) return const Color(0xFF7DD3FC);
    return const Color(0xFFEC4899);
  }

  void _goTutorialStep(int nextStep) {
    final steps = _tutorialSteps();
    if (nextStep < 0 || nextStep >= steps.length) return;
    final step = steps[nextStep];
    final nextEditMode = step.requiresEditMode
        ? true
        : (step.requiresPlayMode ? false : _editMode);
    setState(() {
      _editMode = nextEditMode;
      _tutorialStep = nextStep;
      if (!step.openButtonsSheet) {
        _tutorialButtonsSheetOpened = false;
      }
    });
    _scheduleTutorialRectUpdate();
  }

  Future<void> _finishTutorial() async {
    setState(() {
      _showTutorial = false;
      _tutorialStep = 0;
      _editMode = false;
      _tutorialButtonsSheetOpened = false;
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
      _tutorialButtonsSheetOpened = false;
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
      'layout': _encodeLayout(_layout),
      'active': _activeIds.toList(),
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
      if (layoutRaw is Map) {
        _layout = _decodeLayout(jsonEncode(layoutRaw));
      }
      if (activeRaw is List) {
        _activeIds = activeRaw.map((e) => e.toString()).toSet();
      }
      if (_panelSize != null) {
        final defaults = _defaultLayout(_panelSize!, _activeIds);
        _layout = {...defaults, ..._layout};
      }
      setState(() {});
      _saveLayout();
      _saveActive();
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
                              ? 'บันทึกและเรียกใช้งานรูปแบบจอยและปุ่มที่ตั้งค่าไว้'
                              : 'Save and load your joystick and button layouts.',
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

  Future<void> _openButtonsMenu({bool showTutorial = false}) async {
    if (Platform.isIOS) {
      await _showEditMenuIOS(showTutorial: showTutorial);
    } else {
      await _showEditMenuAndroid(showTutorial: showTutorial);
    }
  }

  Future<void> _showEditMenuAndroid({bool showTutorial = false}) async {
    if (_menuOpen) return;
    _menuOpen = true;
    if (!mounted) {
      _menuOpen = false;
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: showTutorial,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black87,
      builder: (context) {
        final maxHeight = MediaQuery.of(context).size.height * 0.7;
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final scrollController = ScrollController();

        return SafeArea(
          top: false,
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              if (showTutorial) {
                return _buildButtonsTutorialSheet(
                  context: context,
                  scrollController: scrollController,
                  isDark: isDark,
                  maxHeight: maxHeight,
                  setSheetState: setSheetState,
                );
              }
              return Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                decoration: BoxDecoration(
                  color: isDark
                      ? _opacity(const Color(0xFF020817), 0.86)
                      : _opacity(const Color(0xFFF8FAFC), 0.96),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _opacity(
                      const Color(0xFF7DD3FC),
                      isDark ? 0.46 : 0.26,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _opacity(Colors.black, isDark ? 0.30 : 0.14),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxHeight),
                  child: _buildButtonsSheetContent(
                    context: context,
                    scrollController: scrollController,
                    isDark: isDark,
                    setSheetState: setSheetState,
                    showTutorial: false,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
    _menuOpen = false;
  }

  Future<void> _showEditMenuIOS({bool showTutorial = false}) async {
    if (_menuOpen) return;
    _menuOpen = true;
    if (!mounted) {
      _menuOpen = false;
      return;
    }
    final allowDismiss = ValueNotifier<bool>(false);
    Future.delayed(const Duration(milliseconds: 200), () {
      if (allowDismiss.value) return;
      allowDismiss.value = true;
    });
    await showCupertinoModalPopup<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      anchorPoint: _menuAnchor,
      builder: (context) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final maxHeight = MediaQuery.of(context).size.height * 0.7;
        final scrollController = ScrollController();
        return SizedBox.expand(
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: allowDismiss,
                builder: (context, armed, child) {
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: armed ? () => Navigator.pop(context) : null,
                    child: const SizedBox.expand(),
                  );
                },
              ),
              SafeArea(
                top: false,
                child: StatefulBuilder(
                  builder: (context, setSheetState) {
                    if (showTutorial) {
                      return _buildButtonsTutorialSheet(
                        context: context,
                        scrollController: scrollController,
                        isDark: isDark,
                        maxHeight: maxHeight,
                        setSheetState: setSheetState,
                      );
                    }
                    return Container(
                      margin: const EdgeInsets.all(12),
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? _opacity(const Color(0xFF020817), 0.86)
                            : _opacity(const Color(0xFFF8FAFC), 0.96),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _opacity(
                            const Color(0xFF7DD3FC),
                            isDark ? 0.46 : 0.26,
                          ),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _opacity(Colors.black, isDark ? 0.30 : 0.14),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: maxHeight),
                          child: _buildButtonsSheetContent(
                            context: context,
                            scrollController: scrollController,
                            isDark: isDark,
                            setSheetState: setSheetState,
                            showTutorial: false,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
    _menuOpen = false;
  }

  Widget _buildButtonsSheetContent({
    required BuildContext context,
    required ScrollController scrollController,
    required bool isDark,
    required void Function(VoidCallback fn) setSheetState,
    required bool showTutorial,
  }) {
    final isThai = LanguageController.isThai.value;
    final tutorialLock = showTutorial;
    final accent = const Color(0xFF38BDF8);
    final titleColor = _opacity(
      isDark ? Colors.white : const Color(0xFF0F172A),
      0.94,
    );
    final subtitleColor = _opacity(
      isDark ? Colors.white : const Color(0xFF0F172A),
      0.70,
    );

    Widget row(String id, String label, bool active) {
      final rowTextColor = _opacity(
        isDark ? Colors.white : const Color(0xFF0F172A),
        0.92,
      );
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: tutorialLock
            ? null
            : () {
                gamepadBuzz();
                _toggleActive(id);
                setSheetState(() {});
              },
        child: Opacity(
          opacity: tutorialLock ? 0.6 : 1.0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: _opacity(Colors.white, active ? 0.12 : 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _opacity(
                  active ? accent : Colors.white,
                  active ? 0.56 : 0.12,
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: _opacity(accent, active ? 0.22 : 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _opacity(accent, active ? 0.66 : 0.25),
                    ),
                  ),
                  child: Icon(
                    active ? Icons.check_rounded : Icons.add_rounded,
                    size: 14,
                    color: active
                        ? accent
                        : _opacity(
                            isDark ? Colors.white : const Color(0xFF0F172A),
                            0.62,
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: rowTextColor,
                      fontSize: 13.5,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  active
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  size: 16,
                  color: active
                      ? accent
                      : _opacity(
                          isDark ? Colors.white : const Color(0xFF0F172A),
                          0.30,
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ScrollbarTheme(
      data: isDark
          ? const ScrollbarThemeData()
          : ScrollbarThemeData(
              thumbColor: WidgetStateProperty.all(Colors.white),
            ),
      child: Scrollbar(
        controller: scrollController,
        thumbVisibility: true,
        trackVisibility: true,
        thickness: 4,
        radius: const Radius.circular(999),
        child: SingleChildScrollView(
          controller: scrollController,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!showTutorial)
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
              if (!showTutorial) ...[
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: _opacity(accent, isDark ? 0.20 : 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.tune_rounded,
                              size: 13,
                              color: accent,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            isThai ? 'เลือกใช้งานปุ่ม' : 'Buttons',
                            style: TextStyle(
                              color: titleColor,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        gamepadBuzz();
                        Navigator.pop(context);
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: _opacity(
                          isDark ? Colors.white : const Color(0xFF0F172A),
                          0.72,
                        ),
                      ),
                      child: Text(isThai ? 'ยกเลิก' : 'Cancel'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  isThai
                      ? 'แตะเพื่อเปิดหรือปิดจอยสติ๊กและปุ่มที่ต้องการใช้งาน รายการที่เปิดจะปรากฏบนพื้นที่ควบคุม'
                      : 'Tap to enable or disable joysticks and buttons. Enabled items appear on the control area.',
                  style: TextStyle(
                    color: subtitleColor,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                isThai ? 'จอยสติ๊ก' : 'Joysticks',
                style: TextStyle(
                  color: subtitleColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              row(
                kJoyLeftId,
                isThai ? 'จอยสติ๊กซ้าย' : 'Left Joystick',
                _activeIds.contains(kJoyLeftId),
              ),
              row(
                kJoyRightId,
                isThai ? 'จอยสติ๊กขวา' : 'Right Joystick',
                _activeIds.contains(kJoyRightId),
              ),
              row(
                kJoyYOnlyId,
                isThai ? 'จอยสติ๊กแกน Y' : 'Joystick (Y only)',
                _activeIds.contains(kJoyYOnlyId),
              ),
              row(
                kJoyXOnlyId,
                isThai ? 'จอยสติ๊กแกน X' : 'Joystick (X only)',
                _activeIds.contains(kJoyXOnlyId),
              ),
              const SizedBox(height: 8),
              Text(
                isThai ? 'ปุ่มกด' : 'Buttons',
                style: TextStyle(
                  color: subtitleColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              row(
                kBtnTriangleId,
                isThai ? 'สามเหลี่ยม' : 'Triangle',
                _activeIds.contains(kBtnTriangleId),
              ),
              row(
                kBtnCrossId,
                isThai ? 'กากบาท' : 'Cross',
                _activeIds.contains(kBtnCrossId),
              ),
              row(
                kBtnSquareId,
                isThai ? 'สี่เหลี่ยม' : 'Square',
                _activeIds.contains(kBtnSquareId),
              ),
              row(
                kBtnCircleId,
                isThai ? 'วงกลม' : 'Circle',
                _activeIds.contains(kBtnCircleId),
              ),
              if (!showTutorial) const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildButtonsTutorialSheet({
    required BuildContext context,
    required ScrollController scrollController,
    required bool isDark,
    required double maxHeight,
    required void Function(VoidCallback fn) setSheetState,
  }) {
    final steps = _tutorialSteps();
    final step = steps[_tutorialStep];
    final isFirst = _tutorialStep <= 0;
    final isLast = _tutorialStep == steps.length - 1;

    return Align(
      alignment: Alignment.bottomCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.center,
                child: _TutorialFloatingCard(
                  title: _tutorialThai ? step.titleTh : step.titleEn,
                  body: _tutorialThai ? step.bodyTh : step.bodyEn,
                  isThai: _tutorialThai,
                  isLast: isLast,
                  showBack: !isFirst,
                  maxWidth: 420,
                  minHeight: null,
                  compact: false,
                  surfaceColor: const Color(0xFF1F2329),
                  ctaColor: const Color(0xFF3B82F6),
                  onSkip: () {
                    Navigator.pop(context);
                    _finishTutorial();
                  },
                  onBack: isFirst
                      ? null
                      : () {
                          Navigator.pop(context);
                          _goTutorialStep(_tutorialStep - 1);
                        },
                  onNext: () {
                    Navigator.pop(context);
                    if (isLast) {
                      _finishTutorial();
                    } else {
                      _goTutorialStep(_tutorialStep + 1);
                    }
                  },
                ),
              ),
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: isDark
                      ? _opacity(const Color(0xFF020817), 0.86)
                      : _opacity(const Color(0xFFF8FAFC), 0.96),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _opacity(
                      const Color(0xFF7DD3FC),
                      isDark ? 0.46 : 0.26,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _opacity(Colors.black, isDark ? 0.30 : 0.14),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: math.min(maxHeight * 0.62, 360),
                    ),
                    child: _buildButtonsSheetContent(
                      context: context,
                      scrollController: scrollController,
                      isDark: isDark,
                      setSheetState: setSheetState,
                      showTutorial: true,
                    ),
                  ),
                ),
              ),
            ],
          ),
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
                              ? 'ระบบจะแสดง Tutorial การใช้งานปุ่มและเครื่องมือในหน้า Joystick Mode Edit'
                              : 'The app will show a tutorial for buttons and tools on the Joystick Mode Edit page.',
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
              key: _tutorialPresetPanelKey,
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
                                  ? 'บันทึกและเรียกใช้งานรูปแบบปุ่มพร้อมค่า DRV/TRN'
                                  : 'Save and load button layouts with DRV/TRN values.',
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
    if (step.openButtonsSheet) {
      return const SizedBox.shrink();
    }
    final isLast = _tutorialStep == steps.length - 1;
    final isPreviewBleStep = step.openBleSheet;
    final isPreviewPresetStep =
        step.titleEn == 'Preview Preset' || step.titleEn == 'Preset Management';
    final rect = _tutorialTargetKey == step.targetKey
        ? _tutorialTargetRect
        : null;
    final highlightColor = _tutorialHighlightColor(step);
    final highlightRect = rect == null
        ? null
        : _tutorialHighlightRect(step, rect);
    final highlightRadius = _tutorialHighlightRadius(step);
    final screenSize = MediaQuery.of(context).size;
    final scaledMedia = MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(1.0));
    const double arrowSize = 72;
    const double arrowGap = 4;
    final bool arrowAbove =
        highlightRect != null && highlightRect.top > (arrowSize + 24);
    final double arrowLeft = highlightRect == null
        ? 0
        : (highlightRect.center.dx - (arrowSize / 2)).clamp(
            8.0,
            screenSize.width - arrowSize - 8,
          );
    final double arrowTop = highlightRect == null
        ? 0
        : arrowAbove
        ? (highlightRect.top - arrowSize - arrowGap).clamp(
            8.0,
            screenSize.height - arrowSize - 8,
          )
        : (highlightRect.bottom + arrowGap).clamp(
            8.0,
            screenSize.height - arrowSize - 8,
          );
    final tutorialCardAlignment = (isPreviewBleStep || isPreviewPresetStep)
        ? Alignment.topCenter
        : Alignment.bottomCenter;
    final tutorialCardPadding = (isPreviewBleStep || isPreviewPresetStep)
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
                painter: _TutorialMaskPainter(
                  holeRect: highlightRect,
                  radius: highlightRadius,
                  color: _opacity(
                    Colors.black,
                    Theme.of(context).brightness == Brightness.dark
                        ? 0.58
                        : 0.46,
                  ),
                ),
                child: const SizedBox.expand(),
              ),
            ),
            if (highlightRect != null)
              Positioned.fromRect(
                rect: highlightRect,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(highlightRadius),
                      border: Border.all(
                        color: _opacity(highlightColor, 0.82),
                        width: 2.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _opacity(highlightColor, 0.28),
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
            if (highlightRect != null &&
                !step.openBleSheet &&
                !isPreviewPresetStep)
              Positioned(
                left: arrowLeft,
                top: arrowTop,
                child: IgnorePointer(
                  child: GamepadTutorialPointer(
                    size: arrowSize,
                    color: const Color(0xFF7DD3FC),
                    direction: arrowAbove
                        ? GamepadPointerDirection.down
                        : GamepadPointerDirection.up,
                  ),
                ),
              ),
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
                    maxWidth: isPreviewBleStep
                        ? 380
                        : (isPreviewPresetStep ? 280 : 420),
                    minHeight: isPreviewBleStep ? 130 : null,
                    roomyCompact: isPreviewBleStep,
                    compact: isPreviewBleStep || isPreviewPresetStep,
                    surfaceColor: const Color(0xFF1F2329),
                    ctaColor: const Color(0xFF3B82F6),
                    onSkip: _finishTutorial,
                    onBack: _tutorialStep > 0
                        ? () => _goTutorialStep(_tutorialStep - 1)
                        : null,
                    onNext: isLast
                        ? _finishTutorial
                        : () => _goTutorialStep(_tutorialStep + 1),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const SizedBox.shrink();
  }

  void _showSizeLimit(bool atMax) {
    final isThai = LanguageController.isThai.value;
    final msg = atMax
        ? (isThai ? 'ถึงขนาดสูงสุดแล้ว' : 'Max size reached')
        : (isThai ? 'ถึงขนาดต่ำสุดแล้ว' : 'Min size reached');
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(milliseconds: 900)),
    );
  }

  void _showSizeEdgeWarning() {
    final isThai = LanguageController.isThai.value;
    final msg = isThai
        ? 'ปุ่มต้องอยู่ภายในขอบเขตปลอดภัย'
        : 'Buttons must stay inside the safe zone.';
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(milliseconds: 900)),
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

  void _flashEditWarning(String id) {
    _editWarningTimer?.cancel();
    if (mounted) {
      setState(() => _editWarningId = id);
    }
    _editWarningTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() {
        if (_editWarningId == id) {
          _editWarningId = null;
        }
      });
    });
  }

  void _adjustSelectedSize(double delta) {
    final id = _selectedId;
    if (id == null) return;
    if (_lockedIds.contains(id)) return;
    final panel = _panelSize;
    if (panel == null) return;
    final current = _layout[id];
    if (current == null) return;

    final w = panel.width;
    final h = panel.height;
    final isButton = _isButtonId(id);
    final base = isButton ? _baseBtnSize(panel) : _baseJoySize(panel);
    final normalizedCurrent = _normalizeJoyLayoutForPanel(
      current,
      panel,
      baseSize: base,
      isButton: isButton,
    );
    final maxSize = _maxJoyScaleForPanel(
      panel,
      baseSize: base,
      isButton: isButton,
    );
    final minSize = math.min(isButton ? kJoyBtnMinSize : kJoyMinSize, maxSize);
    final unclamped = normalizedCurrent.size + delta;
    final nextSize = unclamped.clamp(minSize, maxSize).toDouble();
    if (nextSize == normalizedCurrent.size) {
      _showSizeLimit(unclamped >= maxSize);
      _flashEditWarning(id);
      return;
    }
    _pushHistory();
    final sizePx = base * nextSize;

    const safeEdgePad = 16.0;
    final rawCx = normalizedCurrent.cx * w;
    final rawCy = normalizedCurrent.cy * h;
    double cx = GamepadEditMetrics.safeCenterCoordinate(
      value: rawCx,
      extent: w,
      itemExtent: sizePx,
      leadingPadding: safeEdgePad,
      trailingPadding: safeEdgePad,
    );
    double cy = GamepadEditMetrics.safeCenterCoordinate(
      value: rawCy,
      extent: h,
      itemExtent: sizePx,
      leadingPadding: safeEdgePad,
      trailingPadding: safeEdgePad,
    );
    final edgeAdjusted = (cx - rawCx).abs() > 0.01 || (cy - rawCy).abs() > 0.01;

    var collides = false;
    for (final entry in _layout.entries) {
      if (entry.key == id) continue;
      final otherBase = _isButtonId(entry.key)
          ? _baseBtnSize(panel)
          : _baseJoySize(panel);
      final other = _normalizeJoyLayoutForPanel(
        entry.value,
        panel,
        baseSize: otherBase,
        isButton: _isButtonId(entry.key),
      );
      final ox = other.cx * w;
      final oy = other.cy * h;
      final otherSizePx = otherBase * other.size;
      final minDist = (sizePx / 2) + (otherSizePx / 2);
      final dx = cx - ox;
      final dy = cy - oy;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist < minDist) {
        collides = true;
        break;
      }
    }
    if (collides) {
      HapticFeedback.vibrate();
      _showOverlapWarning();
      _flashEditWarning(id);
      return;
    }

    setState(() {
      final next = Map<String, _JoyLayout>.from(_layout);
      next[id] = _JoyLayout(cx / w, cy / h, nextSize);
      _layout = next;
      _editWarningId = null;
    });
    _saveLayout();
    if (edgeAdjusted) {
      _showSizeEdgeWarning();
    }
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

  bool _isButtonId(String id) {
    return id == kBtnTriangleId ||
        id == kBtnCrossId ||
        id == kBtnSquareId ||
        id == kBtnCircleId;
  }

  void _onButtonChanged(String id, bool down) {
    if (_editMode) return;
    if (id == kBtnTriangleId) _triangle = down;
    if (id == kBtnCrossId) _cross = down;
    if (id == kBtnSquareId) _square = down;
    if (id == kBtnCircleId) _circle = down;

    _lastButtonsKey = _buttonsKey();
    _sendBinary(_controller.buildPacket(), buttons: _pressedButtons());
    if (mounted) {
      setState(() {});
    }
  }

  Future<bool> _onBack() async {
    OrientationUtils.restoreAfterControl(
      isTablet: _restoreAutoOrientationOnExit,
    );
    unawaited(_sendZeroAndClear());
    _stopTimer();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const ControllerHomePage()),
      (route) => false,
    );
    return false;
  }

  GamepadAppBarMetrics _metricsWithOverrides(
    GamepadAppBarMetrics base, {
    double? labelButtonWidth,
    double? telemetryValueMaxWidth,
  }) {
    return GamepadAppBarMetrics(
      toolbarExtent: base.toolbarExtent,
      controlHeight: base.controlHeight,
      iconButtonExtent: base.iconButtonExtent,
      labelButtonWidth: labelButtonWidth ?? base.labelButtonWidth,
      controlGap: base.controlGap,
      sectionGap: base.sectionGap,
      contentPadding: base.contentPadding,
      iconSize: base.iconSize,
      borderRadius: base.borderRadius,
      labelIconGap: base.labelIconGap,
      telemetryLabelFontSize: base.telemetryLabelFontSize,
      telemetryValueFontSize: base.telemetryValueFontSize,
      telemetryValueMaxWidth:
          telemetryValueMaxWidth ?? base.telemetryValueMaxWidth,
    );
  }

  Widget _buildAlignmentGuides() {
    if (!_editMode || _dragCount == 0 || (!_showVGuide && !_showHGuide)) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final color = _guideSnap
        ? _opacity(const Color(0xFFFACC15), isDark ? 0.92 : 0.85)
        : _opacity(cs.primary, isDark ? 0.35 : 0.25);

    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: GamepadEditAlignmentGuidesPainter(
            color: color,
            showVertical: _showVGuide,
            showHorizontal: _showHGuide,
            verticalX: _guideV,
            horizontalY: _guideH,
            strokeWidth: 1.2,
          ),
        ),
      ),
    );
  }

  Widget _buildAppBarActionsRow({
    required bool isThai,
    required GamepadAppBarMetrics appBarMetrics,
    required double actionGap,
    required _TutorialStep? activeTutorialStep,
    required bool tutorialIsFirst,
    required bool tutorialIsLast,
  }) {
    final children = <Widget>[];

    void addAction(Widget widget) {
      if (children.isNotEmpty) {
        children.add(SizedBox(width: actionGap));
      }
      children.add(widget);
    }

    addAction(
      ConnectionStatusBadge(
        key: _tutorialBtKey,
        controller: _bleBadgeController,
        appBarMetrics: appBarMetrics,
        showTutorial: false,
        tutorialIsFirst: tutorialIsFirst,
        tutorialIsLast: tutorialIsLast,
        tutorialTitle: activeTutorialStep == null
            ? null
            : (_tutorialThai
                  ? activeTutorialStep.titleTh
                  : activeTutorialStep.titleEn),
        tutorialBody: activeTutorialStep == null
            ? null
            : (_tutorialThai
                  ? activeTutorialStep.bodyTh
                  : activeTutorialStep.bodyEn),
        onTutorialSkip: _finishTutorial,
        onTutorialBack: tutorialIsFirst
            ? null
            : () => _goTutorialStep(_tutorialStep - 1),
        onTutorialNext: tutorialIsLast
            ? null
            : () => _goTutorialStep(_tutorialStep + 1),
        onTutorialFinish: _finishTutorial,
      ),
    );

    addAction(
      GamepadAppBarActionGroup(
        gap: actionGap,
        items: [
          GamepadAppBarActionItem(
            key: _tutorialCustomizeKey,
            label: isThai ? 'แก้ไข' : 'Edit',
            icon: Icons.edit,
            accent: const Color(0xFF38BDF8),
            compactOnNarrow: false,
            onTap: () {
              gamepadBuzz();
              _toggleEdit();
            },
          ),
          GamepadAppBarActionItem(
            key: _tutorialPresetKey,
            label: isThai ? 'ค่าที่ตั้งไว้' : 'Preset',
            icon: Icons.folder_open,
            accent: const Color(0xFFF59E0B),
            onTap: () {
              gamepadBuzz();
              _showPresetSheet();
            },
          ),
          GamepadAppBarActionItem(
            key: _tutorialHelpKey,
            label: isThai ? 'วิธีใช้งาน' : 'Tutorial',
            icon: Icons.help_outline,
            accent: const Color(0xFFEC4899),
            iconOnly: true,
            onTap: () {
              gamepadBuzz();
              _restartTutorial();
            },
          ),
        ],
      ),
    );

    return SizedBox(
      height: appBarMetrics.controlHeight,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }

  Widget _buildAppBarToolbarRow({
    required bool isThai,
    required GamepadAppBarMetrics appBarMetrics,
    required GamepadAppBarMetrics cmdMetrics,
    required GamepadAppBarMetrics axisMetrics,
    required double uniformGap,
    required _TutorialStep? activeTutorialStep,
    required bool tutorialIsFirst,
    required bool tutorialIsLast,
  }) {
    final children = <Widget>[
      SizedBox(
        key: _tutorialCmdKey,
        child: GamepadTelemetryChip(
          icon: Icons.flash_on,
          label: 'CMD',
          value: _cmdLabel(),
          metrics: cmdMetrics,
          accentColor: _cmdAccent,
        ),
      ),
      SizedBox(width: uniformGap),
      SizedBox(
        key: _tutorialJlKey,
        child: GamepadTelemetryChip(
          icon: Icons.west,
          label: 'JL',
          value: _leftDebug,
          metrics: axisMetrics,
          accentColor: _jlAccent,
        ),
      ),
      SizedBox(width: uniformGap),
      SizedBox(
        key: _tutorialJrKey,
        child: GamepadTelemetryChip(
          icon: Icons.east,
          label: 'JR',
          value: _rightDebug,
          metrics: axisMetrics,
          accentColor: _jrAccent,
        ),
      ),
      SizedBox(width: uniformGap),
      _buildAppBarActionsRow(
        isThai: isThai,
        appBarMetrics: appBarMetrics,
        actionGap: uniformGap,
        activeTutorialStep: activeTutorialStep,
        tutorialIsFirst: tutorialIsFirst,
        tutorialIsLast: tutorialIsLast,
      ),
    ];

    return SizedBox(
      height: appBarMetrics.controlHeight,
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Row(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildEditModeAppBar(bool isThai) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final metrics = GamepadAppBarMetrics.forWidth(
      MediaQuery.of(context).size.width,
    );
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
    final middleChildren = <Widget>[
      _actionPill(
        key: _tutorialRemoveKey,
        label: isThai ? 'ลบ' : 'Delete',
        icon: Icons.delete_outline,
        accent: const Color(0xFFF87171),
        compact: true,
        onTap: _selectedId == null
            ? null
            : () {
                gamepadBuzz();
                _removeSelected();
              },
      ),
      _actionPill(
        key: _tutorialResetKey,
        label: isThai ? 'รีเซ็ต' : 'Reset',
        icon: Icons.restart_alt,
        accent: const Color(0xFFF59E0B),
        compact: true,
        onTap: () {
          gamepadBuzz();
          _resetLayout();
        },
      ),
      _toolIconPill(
        key: _tutorialUndoKey,
        icon: Icons.undo_rounded,
        label: isThai ? 'ย้อน' : 'Undo',
        accent: const Color(0xFFA78BFA),
        onTap: _undoStack.isNotEmpty
            ? () {
                gamepadBuzz();
                _undo();
              }
            : null,
      ),
      _toolIconPill(
        key: _tutorialRedoKey,
        icon: Icons.redo_rounded,
        label: isThai ? 'ทำซ้ำ' : 'Redo',
        accent: const Color(0xFFA78BFA),
        onTap: _redoStack.isNotEmpty
            ? () {
                gamepadBuzz();
                _redo();
              }
            : null,
      ),
      _toolIconPill(
        key: _tutorialGridKey,
        icon: _showGrid ? Icons.grid_on_rounded : Icons.grid_off_rounded,
        label: isThai ? 'กริด' : 'Grid',
        accent: const Color(0xFF38BDF8),
        active: _showGrid,
        onTap: () {
          gamepadBuzz();
          setState(() => _showGrid = !_showGrid);
        },
      ),
      _sizeToolPill(
        key: _tutorialSizeKey,
        isThai: isThai,
        enabled: _selectedId != null && !_lockedIds.contains(_selectedId),
      ),
      _toolIconPill(
        key: _tutorialLockKey,
        icon: _selectedId != null && _lockedIds.contains(_selectedId)
            ? Icons.lock_rounded
            : Icons.lock_open_rounded,
        label: isThai ? 'ล็อก' : 'Lock',
        accent: const Color(0xFFFBBF24),
        active: _selectedId != null && _lockedIds.contains(_selectedId),
        onTap: _selectedId != null
            ? () {
                gamepadBuzz();
                _toggleSelectedLock();
              }
            : null,
      ),
    ];
    final allChildren = <Widget>[
      _buildEditMenu(compact: true),
      ...middleChildren,
      _actionPill(
        key: _tutorialDoneKey,
        label: isThai ? 'เสร็จสิ้น' : 'Done',
        icon: Icons.edit,
        accent: const Color(0xFF60A5FA),
        compact: true,
        onTap: () {
          gamepadBuzz();
          _toggleEdit();
        },
      ),
    ];

    return AppBar(
      automaticallyImplyLeading: false,
      toolbarHeight: metrics.toolbarExtent,
      elevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      foregroundColor: cs.onSurface,
      titleSpacing: 0,
      flexibleSpace: ClipRRect(
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
      ),
      title: SizedBox(
        key: _tutorialEditBarKey,
        height: metrics.controlHeight,
        child: Padding(
          padding: metrics.contentPadding,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: allChildren,
          ),
        ),
      ),
    );
  }

  Widget _buildAppBarBackButton(GamepadAppBarMetrics metrics) {
    return GamepadAppBarBackButton(
      buttonKey: _tutorialBackKey,
      metrics: metrics,
      onPressed: () {
        gamepadBuzz();
        _onBack();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final steps = _tutorialSteps();
    final activeTutorialStep =
        (_showTutorial && _tutorialStep >= 0 && _tutorialStep < steps.length)
        ? steps[_tutorialStep]
        : null;
    final tutorialIsFirst = _tutorialStep <= 0;
    final tutorialIsLast = _tutorialStep == steps.length - 1;
    final width = MediaQuery.of(context).size.width;
    final appBarMetrics = GamepadAppBarMetrics.forWidth(width);
    final cmdMetrics = _metricsWithOverrides(
      appBarMetrics,
      labelButtonWidth: 86,
      telemetryValueMaxWidth: 28,
    );
    final axisMetrics = _metricsWithOverrides(
      appBarMetrics,
      labelButtonWidth: width >= 1200 ? 172 : 156,
      telemetryValueMaxWidth: width >= 1200 ? 144 : 132,
    );
    final presetMetrics = _metricsWithOverrides(
      appBarMetrics,
      labelButtonWidth: width >= 1200 ? 118 : 108,
    );
    final isThai = LanguageController.isThai.value;
    final cmdWidth = cmdMetrics.labelButtonWidth;
    final axisWidth = axisMetrics.labelButtonWidth;
    final bleWidth = appBarMetrics.labelButtonWidth;
    final centerBaseWidth = cmdWidth + axisWidth + axisWidth;
    final rightButtonWidth =
        bleWidth +
        78.0 +
        presetMetrics.labelButtonWidth +
        appBarMetrics.iconButtonExtent;
    final gapSlots = 5.0;
    final availableWidth = math.max(0.0, width - 24.0);
    final uniformGap =
        ((availableWidth - centerBaseWidth - rightButtonWidth) / gapSlots)
            .clamp(3.0, 10.0)
            .toDouble();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _onBack();
      },
      child: Stack(
        key: _tutorialStackKey,
        children: [
          Scaffold(
            extendBodyBehindAppBar: true,
            appBar: _editMode
                ? _buildEditModeAppBar(isThai)
                : GamepadUnifiedAppBar(
                    toolbarHeight: appBarMetrics.toolbarExtent,
                    leading: _buildAppBarBackButton(appBarMetrics),
                    toolbarPadding: const EdgeInsets.symmetric(horizontal: 12),
                    toolbarContent: _buildAppBarToolbarRow(
                      isThai: isThai,
                      appBarMetrics: appBarMetrics,
                      cmdMetrics: cmdMetrics,
                      axisMetrics: axisMetrics,
                      uniformGap: uniformGap,
                      activeTutorialStep: activeTutorialStep,
                      tutorialIsFirst: tutorialIsFirst,
                      tutorialIsLast: tutorialIsLast,
                    ),
                  ),
            body: Stack(
              children: [
                SafeArea(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _buildGridOverlay(),
                      _buildAlignmentGuides(),
                      Container(
                        key: _tutorialAreaKey,
                        child: LayoutBuilder(
                          builder: (context, c) {
                            final size = Size(c.maxWidth, c.maxHeight);
                            _panelSize = size;
                            final defaults = _defaultLayout(size, _activeIds);
                            final effective = {...defaults, ..._layout};

                            final base = _baseJoySize(size);
                            final btnBase = _baseBtnSize(size);
                            final normalizedSavedLayout =
                                Map<String, _JoyLayout>.from(_layout);
                            var normalizedSavedChanged = false;
                            for (final entry in _layout.entries) {
                              if (!_activeIds.contains(entry.key)) continue;
                              final isButton = _isButtonId(entry.key);
                              final normalized = _normalizeJoyLayoutForPanel(
                                entry.value,
                                size,
                                baseSize: isButton ? btnBase : base,
                                isButton: isButton,
                              );
                              if (!_sameJoyLayout(entry.value, normalized)) {
                                normalizedSavedLayout[entry.key] = normalized;
                                normalizedSavedChanged = true;
                              }
                            }
                            if (normalizedSavedChanged) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!mounted) return;
                                setState(() => _layout = normalizedSavedLayout);
                                _saveLayout();
                              });
                            }

                            final widgets = <Widget>[];
                            if (_activeIds.contains(kJoyLeftId)) {
                              widgets.add(
                                _buildJoystick(
                                  id: kJoyLeftId,
                                  size: size,
                                  baseSize: base,
                                  layout: effective[kJoyLeftId]!,
                                  allLayouts: effective,
                                  isLeft: true,
                                  axisLock: JoystickAxisLock.none,
                                ),
                              );
                            }
                            if (_activeIds.contains(kJoyYOnlyId)) {
                              widgets.add(
                                _buildJoystick(
                                  id: kJoyYOnlyId,
                                  size: size,
                                  baseSize: base,
                                  layout: effective[kJoyYOnlyId]!,
                                  allLayouts: effective,
                                  isLeft: true,
                                  axisLock: JoystickAxisLock.yOnly,
                                ),
                              );
                            }
                            if (_activeIds.contains(kJoyRightId)) {
                              widgets.add(
                                _buildJoystick(
                                  id: kJoyRightId,
                                  size: size,
                                  baseSize: base,
                                  layout: effective[kJoyRightId]!,
                                  allLayouts: effective,
                                  isLeft: false,
                                  axisLock: JoystickAxisLock.none,
                                ),
                              );
                            }
                            if (_activeIds.contains(kJoyXOnlyId)) {
                              widgets.add(
                                _buildJoystick(
                                  id: kJoyXOnlyId,
                                  size: size,
                                  baseSize: base,
                                  layout: effective[kJoyXOnlyId]!,
                                  allLayouts: effective,
                                  isLeft: false,
                                  axisLock: JoystickAxisLock.xOnly,
                                ),
                              );
                            }
                            if (_activeIds.contains(kBtnTriangleId)) {
                              widgets.add(
                                _buildButton(
                                  id: kBtnTriangleId,
                                  label: 'Triangle',
                                  asset: kGamepad8AssetTriangle,
                                  size: size,
                                  baseSize: btnBase,
                                  layout: effective[kBtnTriangleId]!,
                                  allLayouts: effective,
                                ),
                              );
                            }
                            if (_activeIds.contains(kBtnCrossId)) {
                              widgets.add(
                                _buildButton(
                                  id: kBtnCrossId,
                                  label: 'Cross',
                                  asset: kGamepad8AssetCross,
                                  size: size,
                                  baseSize: btnBase,
                                  layout: effective[kBtnCrossId]!,
                                  allLayouts: effective,
                                ),
                              );
                            }
                            if (_activeIds.contains(kBtnSquareId)) {
                              widgets.add(
                                _buildButton(
                                  id: kBtnSquareId,
                                  label: 'Square',
                                  asset: kGamepad8AssetSquare,
                                  size: size,
                                  baseSize: btnBase,
                                  layout: effective[kBtnSquareId]!,
                                  allLayouts: effective,
                                ),
                              );
                            }
                            if (_activeIds.contains(kBtnCircleId)) {
                              widgets.add(
                                _buildButton(
                                  id: kBtnCircleId,
                                  label: 'Circle',
                                  asset: kGamepad8AssetCircle,
                                  size: size,
                                  baseSize: btnBase,
                                  layout: effective[kBtnCircleId]!,
                                  allLayouts: effective,
                                ),
                              );
                            }

                            return Stack(children: widgets);
                          },
                        ),
                      ),
                      _buildEmptyState(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _buildBlePreviewPanel(),
          _buildPresetPreviewPanel(),
          _buildTutorialOverlay(),
          _buildTutorialPromptOverlay(),
        ],
      ),
    );
  }

  Widget _buildJoystick({
    required String id,
    required Size size,
    required double baseSize,
    required _JoyLayout layout,
    required Map<String, _JoyLayout> allLayouts,
    required bool isLeft,
    required JoystickAxisLock axisLock,
  }) {
    final selected = _selectedId == id;
    final dimmed = _selectedId != null && _selectedId != id;
    final normalized = _normalizeJoyLayoutForPanel(
      layout,
      size,
      baseSize: baseSize,
      isButton: false,
    );
    final joySize = _joyDiameterForPanel(normalized, size, baseSize: baseSize);
    final half = joySize / 2;
    final cx = GamepadEditMetrics.safeCenterCoordinate(
      value: normalized.cx * size.width,
      extent: size.width,
      itemExtent: joySize,
      leadingPadding: 16.0,
      trailingPadding: 16.0,
    );
    final cy = GamepadEditMetrics.safeCenterCoordinate(
      value: normalized.cy * size.height,
      extent: size.height,
      itemExtent: joySize,
      leadingPadding: 16.0,
      trailingPadding: 16.0,
    );

    final joyWidget = SizedBox(
      width: joySize,
      height: joySize,
      child: JoystickWidget(
        controller: _controller,
        isLeft: isLeft,
        axisLock: axisLock,
        baseImage: isLeft
            ? joystickTheme.leftBaseImage
            : joystickTheme.rightBaseImage,
        knobImage: isLeft
            ? joystickTheme.leftKnobImage
            : joystickTheme.rightKnobImage,
        onChanged: (x, y) {
          if (_editMode) return;
          if (isLeft) {
            final (sx, sy) = _process(x, y, _smoothLX, _smoothLY);
            _smoothLX = sx;
            _smoothLY = sy;
            _controller.setLeftJoystick(sx, sy);
            if (x == 0 && y == 0) {
              _resetLeftJoystick();
              return;
            }
          } else {
            final (sx, sy) = _process(x, y, _smoothRX, _smoothRY);
            _smoothRX = sx;
            _smoothRY = sy;
            _controller.setRightJoystick(sx, sy);
            if (x == 0 && y == 0) {
              _resetRightJoystick();
              return;
            }
          }
        },
      ),
    );

    if (!_editMode) {
      return Positioned(left: cx - half, top: cy - half, child: joyWidget);
    }

    return _EditableJoystick(
      id: id,
      panelSize: size,
      baseSize: baseSize,
      layout: normalized,
      allLayouts: allLayouts,
      snapToGrid: _showGrid,
      selected: selected,
      dimmed: dimmed,
      locked: _lockedIds.contains(id),
      onSelect: () => _selectJoystick(id),
      onChanged: (next) {
        setState(() => _layout[id] = next);
      },
      onStart: () {
        _pushHistory();
        _beginDrag();
      },
      onEnd: () {
        _saveLayout();
        _endDrag();
      },
      onGuideChanged: (guide) {
        _setGuideVisibility(
          guide.showVertical,
          guide.showHorizontal,
          snap: guide.snap,
          guideV: guide.verticalX,
          guideH: guide.horizontalY,
        );
      },
      onCollision: _showOverlapWarning,
      onBoundaryWarning: _showBoundaryWarning,
      externalWarning: _editWarningId == id,
      child: joyWidget,
    );
  }

  Widget _buildButton({
    required String id,
    required String label,
    required String asset,
    required Size size,
    required double baseSize,
    required _JoyLayout layout,
    required Map<String, _JoyLayout> allLayouts,
  }) {
    final selected = _selectedId == id;
    final dimmed = _selectedId != null && _selectedId != id;
    final normalized = _normalizeJoyLayoutForPanel(
      layout,
      size,
      baseSize: baseSize,
      isButton: true,
    );
    final btnSize = _joyDiameterForPanel(normalized, size, baseSize: baseSize);
    final half = btnSize / 2;
    final cx = GamepadEditMetrics.safeCenterCoordinate(
      value: normalized.cx * size.width,
      extent: size.width,
      itemExtent: btnSize,
      leadingPadding: 16.0,
      trailingPadding: 16.0,
    );
    final cy = GamepadEditMetrics.safeCenterCoordinate(
      value: normalized.cy * size.height,
      extent: size.height,
      itemExtent: btnSize,
      leadingPadding: 16.0,
      trailingPadding: 16.0,
    );
    final btnWidget = SizedBox(
      width: btnSize,
      height: btnSize,
      child: _JoyImagePressHoldButton(
        label: label,
        asset: asset,
        diameter: btnSize,
        onPressChanged: (down) => _onButtonChanged(id, down),
      ),
    );

    if (!_editMode) {
      return Positioned(left: cx - half, top: cy - half, child: btnWidget);
    }

    return _EditableButtonItem(
      id: id,
      panelSize: size,
      baseSize: baseSize,
      layout: normalized,
      allLayouts: allLayouts,
      snapToGrid: _showGrid,
      selected: selected,
      dimmed: dimmed,
      locked: _lockedIds.contains(id),
      onSelect: () => _selectJoystick(id),
      onChanged: (next) {
        setState(() => _layout[id] = next);
      },
      onStart: () {
        _pushHistory();
        _beginDrag();
      },
      onEnd: () {
        _saveLayout();
        _endDrag();
      },
      onGuideChanged: (guide) {
        _setGuideVisibility(
          guide.showVertical,
          guide.showHorizontal,
          snap: guide.snap,
          guideV: guide.verticalX,
          guideH: guide.horizontalY,
        );
      },
      onCollision: _showOverlapWarning,
      onBoundaryWarning: _showBoundaryWarning,
      externalWarning: _editWarningId == id,
      child: btnWidget,
    );
  }

  Rect _tutorialHighlightRect(_TutorialStep step, Rect rect) {
    final key = step.targetKey;
    if (key == _tutorialBackKey) {
      return Rect.fromLTRB(
        rect.left + 1.0,
        rect.top - 1.0,
        rect.right - 1.0,
        rect.bottom + 1.0,
      );
    }
    if (key == _tutorialCmdKey ||
        key == _tutorialJlKey ||
        key == _tutorialJrKey) {
      return Rect.fromLTRB(
        rect.left - 2.0,
        rect.top - 1.0,
        rect.right + 2.0,
        rect.bottom + 1.0,
      );
    }
    if (key == _tutorialBtKey) {
      return Rect.fromLTRB(
        rect.left - 2.0,
        rect.top - 1.0,
        rect.right + 2.0,
        rect.bottom + 1.0,
      );
    }
    if (key == _tutorialBlePanelKey) {
      return Rect.fromLTRB(
        rect.left - 4.0,
        rect.top - 4.0,
        rect.right + 4.0,
        rect.bottom + 4.0,
      );
    }
    if (key == _tutorialPresetPanelKey) {
      return Rect.fromLTRB(
        rect.left - 4.0,
        rect.top - 4.0,
        rect.right + 4.0,
        rect.bottom + 4.0,
      );
    }
    if (key == _tutorialCustomizeKey ||
        key == _tutorialItemsKey ||
        key == _tutorialRemoveKey ||
        key == _tutorialResetKey ||
        key == _tutorialUndoKey ||
        key == _tutorialRedoKey ||
        key == _tutorialGridKey ||
        key == _tutorialSizeKey ||
        key == _tutorialLockKey ||
        key == _tutorialDoneKey ||
        key == _tutorialPresetKey ||
        key == _tutorialHelpKey) {
      return Rect.fromLTRB(
        rect.left - 2.0,
        rect.top - 1.0,
        rect.right + 2.0,
        rect.bottom + 1.0,
      );
    }
    if (key == _tutorialEditBarKey) {
      return Rect.fromLTRB(
        rect.left - 4.0,
        rect.top - 3.0,
        rect.right + 4.0,
        rect.bottom + 3.0,
      );
    }
    return Rect.fromLTRB(
      rect.left - 2.0,
      rect.top - 1.0,
      rect.right + 2.0,
      rect.bottom + 1.0,
    );
  }

  double _tutorialHighlightRadius(_TutorialStep step) {
    final key = step.targetKey;
    if (key == _tutorialBackKey) return 999.0;
    if (key == _tutorialEditBarKey) return 18.0;
    if (key == _tutorialBlePanelKey) return 12.0;
    if (key == _tutorialPresetPanelKey) return 12.0;
    if (key == _tutorialCmdKey ||
        key == _tutorialJlKey ||
        key == _tutorialJrKey) {
      return 999.0;
    }
    if (key == _tutorialBtKey ||
        key == _tutorialCustomizeKey ||
        key == _tutorialItemsKey ||
        key == _tutorialRemoveKey ||
        key == _tutorialResetKey ||
        key == _tutorialUndoKey ||
        key == _tutorialRedoKey ||
        key == _tutorialGridKey ||
        key == _tutorialSizeKey ||
        key == _tutorialLockKey ||
        key == _tutorialDoneKey ||
        key == _tutorialPresetKey ||
        key == _tutorialHelpKey) {
      return 999.0;
    }
    return 12.0;
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
  final bool requiresEditMode;
  final bool requiresPlayMode;
  final bool openButtonsSheet;
  final bool openBleSheet;
  const _TutorialStep({
    required this.titleTh,
    required this.bodyTh,
    required this.titleEn,
    required this.bodyEn,
    this.targetKey,
    this.requiresEditMode = false,
    this.requiresPlayMode = false,
    this.openButtonsSheet = false,
    this.openBleSheet = false,
  });
}

class _TutorialFloatingCard extends StatelessWidget {
  final String title;
  final String body;
  final bool isThai;
  final bool isLast;
  final bool showBack;
  final double maxWidth;
  final double? minHeight;
  final bool compact;
  final Color surfaceColor;
  final Color ctaColor;
  final VoidCallback onSkip;
  final VoidCallback? onBack;
  final VoidCallback onNext;

  const _TutorialFloatingCard({
    required this.title,
    required this.body,
    required this.isThai,
    required this.isLast,
    required this.showBack,
    this.maxWidth = 420,
    this.minHeight,
    this.compact = false,
    required this.surfaceColor,
    required this.ctaColor,
    required this.onSkip,
    required this.onBack,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    Color withOpacity(Color color, double opacity) =>
        color.withAlpha((opacity * 255).round());
    final double cardWidth = math.min<double>(
      MediaQuery.of(context).size.width - 40,
      maxWidth,
    );
    final titleStyle = TextStyle(
      color: Colors.white,
      fontSize: compact ? (isThai ? 16.0 : 15.5) : (isThai ? 19.0 : 18.0),
      fontWeight: FontWeight.w800,
      fontFamily: isThai ? 'Kanit' : 'Roboto',
      decoration: TextDecoration.none,
      height: 1.15,
    );
    final bodyStyle = TextStyle(
      color: const Color(0xFFD3DAE6),
      fontSize: compact ? (isThai ? 12.5 : 12.0) : (isThai ? 14.5 : 14.0),
      fontWeight: FontWeight.w500,
      fontFamily: isThai ? 'Kanit' : 'Roboto',
      decoration: TextDecoration.none,
      height: 1.45,
    );
    final linkStyle = TextStyle(
      color: const Color(0xFFB6BEC9),
      fontSize: isThai ? 13.5 : 13.0,
      fontWeight: FontWeight.w500,
      fontFamily: isThai ? 'Kanit' : 'Roboto',
      decoration: TextDecoration.none,
    );
    final ctaStyle = TextStyle(
      color: Colors.white,
      fontSize: isThai ? 13.5 : 13.0,
      fontWeight: FontWeight.w700,
      fontFamily: isThai ? 'Kanit' : 'Roboto',
      decoration: TextDecoration.none,
    );

    return SizedBox(
      width: cardWidth,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: withOpacity(Colors.white, 0.08), width: 1),
          boxShadow: [
            BoxShadow(
              color: withOpacity(Colors.black, 0.34),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight ?? 0),
          child: Padding(
            padding: compact
                ? const EdgeInsets.fromLTRB(14, 14, 14, 12)
                : const EdgeInsets.fromLTRB(20, 20, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: titleStyle),
                SizedBox(height: compact ? 6 : 10),
                Text(body, style: bodyStyle),
                SizedBox(height: compact ? 10 : 18),
                Row(
                  children: [
                    TextButton(
                      onPressed: onSkip,
                      child: Text(isThai ? 'ข้าม' : 'Skip', style: linkStyle),
                    ),
                    const Spacer(),
                    if (showBack) ...[
                      TextButton(
                        onPressed: onBack,
                        child: Text(
                          isThai ? 'ย้อนกลับ' : 'Back',
                          style: linkStyle,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    ElevatedButton(
                      onPressed: onNext,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ctaColor,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(
                        isLast
                            ? (isThai ? 'เสร็จสิ้น' : 'Finish')
                            : (isThai ? 'ถัดไป' : 'Next'),
                        style: ctaStyle,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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

class _JoyImagePressHoldButton extends StatefulWidget {
  final String label;
  final String asset;
  final double diameter;
  final ValueChanged<bool>? onPressChanged;

  const _JoyImagePressHoldButton({
    required this.label,
    required this.asset,
    this.diameter = 120,
    this.onPressChanged,
  });

  @override
  State<_JoyImagePressHoldButton> createState() =>
      _JoyImagePressHoldButtonState();
}

class _JoyImagePressHoldButtonState extends State<_JoyImagePressHoldButton> {
  bool _pressed = false;

  Color _opacity(Color color, double opacity) =>
      color.withAlpha((opacity * 255).round());

  void _onDown() {
    if (_pressed) return;
    setState(() => _pressed = true);
    HapticFeedback.lightImpact();
    gamepadBuzz();
    widget.onPressChanged?.call(true);
  }

  void _onUpOrCancel() {
    if (!_pressed) return;
    setState(() => _pressed = false);
    widget.onPressChanged?.call(false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = _pressed ? 0.95 : 1.0;
    final glowColor = _opacity(
      theme.colorScheme.primary,
      theme.brightness == Brightness.dark ? 0.65 : 0.45,
    );

    return Listener(
      onPointerDown: (_) => _onDown(),
      onPointerUp: (_) => _onUpOrCancel(),
      onPointerCancel: (_) => _onUpOrCancel(),
      child: SizedBox(
        width: widget.diameter,
        height: widget.diameter,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOutBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 50),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: _pressed
                  ? [
                      BoxShadow(
                        color: glowColor,
                        blurRadius: 18,
                        spreadRadius: 2,
                      ),
                    ]
                  : const [],
            ),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: ColorFiltered(
                colorFilter: _pressed
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
                child: Image.asset(
                  widget.asset,
                  fit: BoxFit.contain,
                  errorBuilder: (context, _, __) {
                    return SizedBox.expand(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _opacity(theme.colorScheme.onSurface, 0.35),
                            width: 1.4,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            widget.label,
                            style: theme.textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TutorialMaskPainter extends CustomPainter {
  const _TutorialMaskPainter({
    required this.holeRect,
    required this.radius,
    required this.color,
  });

  final Rect? holeRect;
  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPaint = Paint()..color = color;
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(Offset.zero & size, overlayPaint);
    if (holeRect != null) {
      final clearPaint = Paint()..blendMode = BlendMode.clear;
      canvas.drawRRect(
        RRect.fromRectAndRadius(holeRect!, Radius.circular(radius)),
        clearPaint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TutorialMaskPainter oldDelegate) {
    return oldDelegate.holeRect != holeRect ||
        oldDelegate.radius != radius ||
        oldDelegate.color != color;
  }
}

class _EditSnapshot {
  final Map<String, _JoyLayout> layout;
  final Set<String> activeIds;
  final Set<String> lockedIds;
  final String? selectedId;

  const _EditSnapshot({
    required this.layout,
    required this.activeIds,
    required this.lockedIds,
    required this.selectedId,
  });
}

class _JoyLayout {
  final double cx;
  final double cy;
  final double size;

  const _JoyLayout(this.cx, this.cy, this.size);

  _JoyLayout copyWith({double? cx, double? cy, double? size}) {
    return _JoyLayout(cx ?? this.cx, cy ?? this.cy, size ?? this.size);
  }

  Map<String, double> toJson() => {'cx': cx, 'cy': cy, 'size': size};
}

bool _sameJoyLayout(_JoyLayout a, _JoyLayout b) {
  return a.cx == b.cx && a.cy == b.cy && a.size == b.size;
}

double _maxJoyScaleForPanel(
  Size panel, {
  required double baseSize,
  required bool isButton,
  double safeEdgePad = 16.0,
}) {
  return GamepadEditMetrics.maxScaleForBaseSize(
    panel,
    baseSize: baseSize,
    minSize: isButton ? kJoyBtnMinSize : kJoyMinSize,
    maxSize: isButton ? kJoyBtnMaxSize : kJoyMaxSize,
    leftPadding: safeEdgePad,
    topPadding: safeEdgePad,
    rightPadding: safeEdgePad,
    bottomPadding: safeEdgePad,
  );
}

_JoyLayout _normalizeJoyLayoutForPanel(
  _JoyLayout layout,
  Size panel, {
  required double baseSize,
  required bool isButton,
  double safeEdgePad = 16.0,
}) {
  final maxSize = _maxJoyScaleForPanel(
    panel,
    baseSize: baseSize,
    isButton: isButton,
    safeEdgePad: safeEdgePad,
  );
  final minSize = math.min(isButton ? kJoyBtnMinSize : kJoyMinSize, maxSize);
  return _JoyLayout(
    GamepadEditMetrics.clampUnit(layout.cx, 0.5),
    GamepadEditMetrics.clampUnit(layout.cy, 0.5),
    GamepadEditMetrics.finiteDouble(
      layout.size,
      1.0,
    ).clamp(minSize, maxSize).toDouble(),
  );
}

double _joyDiameterForPanel(
  _JoyLayout layout,
  Size panel, {
  required double baseSize,
  double safeEdgePad = 16.0,
}) {
  return GamepadEditMetrics.fittedCircleDiameter(
    baseSize * layout.size,
    panel,
    leftPadding: safeEdgePad,
    topPadding: safeEdgePad,
    rightPadding: safeEdgePad,
    bottomPadding: safeEdgePad,
  );
}

class _EditableJoystick extends StatefulWidget {
  final String id;
  final Size panelSize;
  final double baseSize;
  final _JoyLayout layout;
  final Map<String, _JoyLayout> allLayouts;
  final bool snapToGrid;
  final bool selected;
  final bool dimmed;
  final bool locked;
  final VoidCallback onSelect;
  final ValueChanged<_JoyLayout> onChanged;
  final VoidCallback onEnd;
  final VoidCallback? onStart;
  final ValueChanged<_GuideState>? onGuideChanged;
  final VoidCallback? onCollision;
  final VoidCallback? onBoundaryWarning;
  final bool externalWarning;
  final Widget child;

  const _EditableJoystick({
    required this.id,
    required this.panelSize,
    required this.baseSize,
    required this.layout,
    required this.allLayouts,
    required this.snapToGrid,
    required this.selected,
    required this.dimmed,
    required this.locked,
    required this.onSelect,
    required this.onChanged,
    required this.onEnd,
    this.onStart,
    this.onGuideChanged,
    this.onCollision,
    this.onBoundaryWarning,
    this.externalWarning = false,
    required this.child,
  });

  @override
  State<_EditableJoystick> createState() => _EditableJoystickState();
}

class _EditableJoystickState extends State<_EditableJoystick> {
  late Offset _startFocal;
  late _JoyLayout _startLayout;
  static const double _safeEdgePad = 16.0;
  static const double _edgeWarnThresholdPx = 6.0;
  static const double _guideShowThreshold = 0.035;
  static const double _guideSnapThreshold = 0.018;
  bool _dragging = false;
  bool _colliding = false;
  bool _nearEdgeWarning = false;

  Color _opacity(Color color, double opacity) =>
      color.withAlpha((opacity * 255).round());

  void _onScaleStart(ScaleStartDetails d) {
    if (widget.locked) return;
    if (!widget.selected) {
      widget.onSelect();
      return;
    }
    _startFocal = d.focalPoint;
    _startLayout = _normalizeJoyLayoutForPanel(
      widget.layout,
      widget.panelSize,
      baseSize: widget.baseSize,
      isButton: false,
      safeEdgePad: _safeEdgePad,
    );
    _dragging = false;
    _nearEdgeWarning = false;
    widget.onGuideChanged?.call(const _GuideState.hidden());
    widget.onStart?.call();
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (widget.locked || !widget.selected) return;
    final w = widget.panelSize.width;
    final h = widget.panelSize.height;
    final dx = d.focalPoint.dx - _startFocal.dx;
    final dy = d.focalPoint.dy - _startFocal.dy;
    final moved = dx.abs() > 1 || dy.abs() > 1;
    if (moved && !_dragging) {
      setState(() => _dragging = true);
    }

    final maxSize = _maxJoyScaleForPanel(
      widget.panelSize,
      baseSize: widget.baseSize,
      isButton: false,
      safeEdgePad: _safeEdgePad,
    );
    final minSize = math.min(kJoyMinSize, maxSize);
    final nextSize = (_startLayout.size * d.scale)
        .clamp(minSize, maxSize)
        .toDouble();
    final sizePx = widget.baseSize * nextSize;
    final half = sizePx / 2;

    double cx = _startLayout.cx * w + dx;
    double cy = _startLayout.cy * h + dy;

    if (widget.snapToGrid) {
      double nx = _snapToGrid(cx / w);
      double ny = _snapToGrid(cy / h);
      cx = nx * w;
      cy = ny * h;
    }

    final normalizedCx = cx / w;
    final normalizedCy = cy / h;
    final dxCenter = (normalizedCx - 0.5).abs();
    final dyCenter = (normalizedCy - 0.5).abs();
    final showV = dxCenter <= _guideShowThreshold;
    final showH = dyCenter <= _guideShowThreshold;
    final snapV = dxCenter <= _guideSnapThreshold;
    final snapH = dyCenter <= _guideSnapThreshold;

    if (snapV) cx = w * 0.5;
    if (snapH) cy = h * 0.5;

    widget.onGuideChanged?.call(
      _GuideState(
        showVertical: showV,
        showHorizontal: showH,
        verticalX: 0.5,
        horizontalY: 0.5,
        snap: snapV || snapH,
      ),
    );

    final minX = _safeEdgePad + half;
    final maxX = w - _safeEdgePad - half;
    final minY = _safeEdgePad + half;
    final maxY = h - _safeEdgePad - half;
    final attemptedOutOfBounds =
        maxX < minX ||
        maxY < minY ||
        cx < minX ||
        cx > maxX ||
        cy < minY ||
        cy > maxY;
    cx = GamepadEditMetrics.safeCenterCoordinate(
      value: cx,
      extent: w,
      itemExtent: sizePx,
      leadingPadding: _safeEdgePad,
      trailingPadding: _safeEdgePad,
    );
    cy = GamepadEditMetrics.safeCenterCoordinate(
      value: cy,
      extent: h,
      itemExtent: sizePx,
      leadingPadding: _safeEdgePad,
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

    var collides = false;
    for (final entry in widget.allLayouts.entries) {
      if (entry.key == widget.id) continue;
      final otherBase = _isButtonId(entry.key)
          ? (_baseBtnSize(w, h))
          : widget.baseSize;
      final other = _normalizeJoyLayoutForPanel(
        entry.value,
        widget.panelSize,
        baseSize: otherBase,
        isButton: _isButtonId(entry.key),
        safeEdgePad: _safeEdgePad,
      );
      final ox = other.cx * w;
      final oy = other.cy * h;
      final otherSizePx = otherBase * other.size;
      final minDist = (sizePx / 2) + (otherSizePx / 2);
      final dxItem = cx - ox;
      final dyItem = cy - oy;
      final dist = math.sqrt(dxItem * dxItem + dyItem * dyItem);
      if (dist < minDist) {
        collides = true;
        break;
      }
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

    widget.onChanged(_JoyLayout(cx / w, cy / h, nextSize));
  }

  double _baseBtnSize(double w, double h) => math.min(w, h) * 0.45 * 0.55;

  bool _isButtonId(String id) {
    return id == kBtnTriangleId ||
        id == kBtnCrossId ||
        id == kBtnSquareId ||
        id == kBtnCircleId;
  }

  @override
  Widget build(BuildContext context) {
    final layout = _normalizeJoyLayoutForPanel(
      widget.layout,
      widget.panelSize,
      baseSize: widget.baseSize,
      isButton: false,
      safeEdgePad: _safeEdgePad,
    );
    final joySize = _joyDiameterForPanel(
      layout,
      widget.panelSize,
      baseSize: widget.baseSize,
      safeEdgePad: _safeEdgePad,
    );
    final half = joySize / 2;
    final cx = GamepadEditMetrics.safeCenterCoordinate(
      value: layout.cx * widget.panelSize.width,
      extent: widget.panelSize.width,
      itemExtent: joySize,
      leadingPadding: _safeEdgePad,
      trailingPadding: _safeEdgePad,
    );
    final cy = GamepadEditMetrics.safeCenterCoordinate(
      value: layout.cy * widget.panelSize.height,
      extent: widget.panelSize.height,
      itemExtent: joySize,
      leadingPadding: _safeEdgePad,
      trailingPadding: _safeEdgePad,
    );
    final dimOpacity = widget.dimmed ? 0.35 : 1.0;
    final warningColor = const Color(0xFFEF4444);
    final showWarning =
        _colliding || _nearEdgeWarning || widget.externalWarning;
    final borderColor = showWarning
        ? warningColor
        : (widget.selected ? const Color(0xFF00F0FF) : Colors.white70);
    final borderWidth = widget.selected ? 3.0 : 2.0;
    final glowColor = widget.selected
        ? _opacity(const Color(0xFF00F0FF), 0.45)
        : Colors.transparent;

    return Positioned(
      left: cx - half,
      top: cy - half,
      child: GestureDetector(
        onScaleStart: widget.locked ? null : _onScaleStart,
        onScaleUpdate: widget.locked ? null : _onScaleUpdate,
        onScaleEnd: widget.locked
            ? null
            : (_) {
                widget.onGuideChanged?.call(const _GuideState.hidden());
                if (_colliding || _dragging || _nearEdgeWarning) {
                  setState(() {
                    _colliding = false;
                    _dragging = false;
                    _nearEdgeWarning = false;
                  });
                }
                widget.onEnd();
              },
        onTap: widget.onSelect,
        child: Opacity(
          opacity: dimOpacity,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: borderColor, width: borderWidth),
              boxShadow: [
                if (showWarning)
                  BoxShadow(
                    color: _opacity(warningColor, 0.46),
                    blurRadius: 14,
                    spreadRadius: 2,
                  ),
                BoxShadow(color: glowColor, blurRadius: 18, spreadRadius: 2),
              ],
            ),
            child: IgnorePointer(child: widget.child),
          ),
        ),
      ),
    );
  }
}

class _EditableButtonItem extends StatefulWidget {
  final String id;
  final Size panelSize;
  final double baseSize;
  final _JoyLayout layout;
  final Map<String, _JoyLayout> allLayouts;
  final bool snapToGrid;
  final bool selected;
  final bool dimmed;
  final bool locked;
  final VoidCallback onSelect;
  final ValueChanged<_JoyLayout> onChanged;
  final VoidCallback onEnd;
  final VoidCallback? onStart;
  final ValueChanged<_GuideState>? onGuideChanged;
  final VoidCallback? onCollision;
  final VoidCallback? onBoundaryWarning;
  final bool externalWarning;
  final Widget child;

  const _EditableButtonItem({
    required this.id,
    required this.panelSize,
    required this.baseSize,
    required this.layout,
    required this.allLayouts,
    required this.snapToGrid,
    required this.selected,
    required this.dimmed,
    required this.locked,
    required this.onSelect,
    required this.onChanged,
    required this.onEnd,
    this.onStart,
    this.onGuideChanged,
    this.onCollision,
    this.onBoundaryWarning,
    this.externalWarning = false,
    required this.child,
  });

  @override
  State<_EditableButtonItem> createState() => _EditableButtonItemState();
}

class _EditableButtonItemState extends State<_EditableButtonItem> {
  late Offset _startFocal;
  late _JoyLayout _startLayout;
  static const double _safeEdgePad = 16.0;
  static const double _snapThresholdPx = 5.0;
  static const double _edgeWarnThresholdPx = 6.0;
  bool _dragging = false;
  bool _colliding = false;
  bool _nearEdgeWarning = false;

  void _onScaleStart(ScaleStartDetails d) {
    if (widget.locked) return;
    if (!widget.selected) {
      widget.onSelect();
      return;
    }
    _startFocal = d.focalPoint;
    _startLayout = _normalizeJoyLayoutForPanel(
      widget.layout,
      widget.panelSize,
      baseSize: widget.baseSize,
      isButton: true,
      safeEdgePad: _safeEdgePad,
    );
    _dragging = false;
    _nearEdgeWarning = false;
    widget.onGuideChanged?.call(const _GuideState.hidden());
    widget.onStart?.call();
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (widget.locked || !widget.selected) return;
    final w = widget.panelSize.width;
    final h = widget.panelSize.height;
    final dx = d.focalPoint.dx - _startFocal.dx;
    final dy = d.focalPoint.dy - _startFocal.dy;
    final moved = dx.abs() > 1 || dy.abs() > 1;
    if (moved && !_dragging) {
      setState(() => _dragging = true);
    }

    final maxSize = _maxJoyScaleForPanel(
      widget.panelSize,
      baseSize: widget.baseSize,
      isButton: true,
      safeEdgePad: _safeEdgePad,
    );
    final minSize = math.min(kJoyBtnMinSize, maxSize);
    final nextSize = (_startLayout.size * d.scale)
        .clamp(minSize, maxSize)
        .toDouble();
    final sizePx = widget.baseSize * nextSize;
    final half = sizePx / 2;

    double cx = _startLayout.cx * w + dx;
    double cy = _startLayout.cy * h + dy;

    if (widget.snapToGrid) {
      double nx = _snapToGrid(cx / w);
      double ny = _snapToGrid(cy / h);
      cx = nx * w;
      cy = ny * h;
    }

    double? snapX;
    double? snapY;
    var bestDx = _snapThresholdPx + 1;
    var bestDy = _snapThresholdPx + 1;

    final centerX = w / 2;
    final centerY = h / 2;
    final dxCenter = (cx - centerX).abs();
    if (dxCenter <= _snapThresholdPx) {
      snapX = centerX;
      bestDx = dxCenter;
    }
    final dyCenter = (cy - centerY).abs();
    if (dyCenter <= _snapThresholdPx) {
      snapY = centerY;
      bestDy = dyCenter;
    }

    for (final entry in widget.allLayouts.entries) {
      if (entry.key == widget.id) continue;
      if (!_isButtonEditId(entry.key)) continue;
      final other = entry.value;
      final ox = other.cx * w;
      final oy = other.cy * h;
      final dxOther = (cx - ox).abs();
      final dyOther = (cy - oy).abs();
      if (dxOther <= _snapThresholdPx && dxOther < bestDx) {
        snapX = ox;
        bestDx = dxOther;
      }
      if (dyOther <= _snapThresholdPx && dyOther < bestDy) {
        snapY = oy;
        bestDy = dyOther;
      }
    }

    if (snapX != null) cx = snapX;
    if (snapY != null) cy = snapY;

    widget.onGuideChanged?.call(
      _GuideState(
        showVertical: snapX != null,
        showHorizontal: snapY != null,
        verticalX: snapX != null ? snapX / w : null,
        horizontalY: snapY != null ? snapY / h : null,
        snap: snapX != null || snapY != null,
      ),
    );

    final minX = _safeEdgePad + half;
    final maxX = w - _safeEdgePad - half;
    final minY = _safeEdgePad + half;
    final maxY = h - _safeEdgePad - half;

    final attemptedOutOfBounds =
        maxX < minX ||
        maxY < minY ||
        cx < minX ||
        cx > maxX ||
        cy < minY ||
        cy > maxY;
    cx = GamepadEditMetrics.safeCenterCoordinate(
      value: cx,
      extent: w,
      itemExtent: sizePx,
      leadingPadding: _safeEdgePad,
      trailingPadding: _safeEdgePad,
    );
    cy = GamepadEditMetrics.safeCenterCoordinate(
      value: cy,
      extent: h,
      itemExtent: sizePx,
      leadingPadding: _safeEdgePad,
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

    var collides = false;
    for (final entry in widget.allLayouts.entries) {
      if (entry.key == widget.id) continue;
      if (!_isButtonEditId(entry.key)) continue;
      final other = _normalizeJoyLayoutForPanel(
        entry.value,
        widget.panelSize,
        baseSize: widget.baseSize,
        isButton: true,
        safeEdgePad: _safeEdgePad,
      );
      final ox = other.cx * w;
      final oy = other.cy * h;
      final otherSizePx = widget.baseSize * other.size;
      final minDist = (sizePx / 2) + (otherSizePx / 2);
      final dxButton = cx - ox;
      final dyButton = cy - oy;
      final dist = math.sqrt(dxButton * dxButton + dyButton * dyButton);
      if (dist < minDist) {
        collides = true;
        break;
      }
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

    widget.onChanged(_JoyLayout(cx / w, cy / h, nextSize));
  }

  @override
  Widget build(BuildContext context) {
    final layout = _normalizeJoyLayoutForPanel(
      widget.layout,
      widget.panelSize,
      baseSize: widget.baseSize,
      isButton: true,
      safeEdgePad: _safeEdgePad,
    );
    final btnSize = _joyDiameterForPanel(
      layout,
      widget.panelSize,
      baseSize: widget.baseSize,
      safeEdgePad: _safeEdgePad,
    );
    final half = btnSize / 2;
    final cx = GamepadEditMetrics.safeCenterCoordinate(
      value: layout.cx * widget.panelSize.width,
      extent: widget.panelSize.width,
      itemExtent: btnSize,
      leadingPadding: _safeEdgePad,
      trailingPadding: _safeEdgePad,
    );
    final cy = GamepadEditMetrics.safeCenterCoordinate(
      value: layout.cy * widget.panelSize.height,
      extent: widget.panelSize.height,
      itemExtent: btnSize,
      leadingPadding: _safeEdgePad,
      trailingPadding: _safeEdgePad,
    );
    final buttonContent = SizedBox(
      width: btnSize,
      height: btnSize,
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
                        color: Theme.of(context).colorScheme.primary.withAlpha(
                          ((Theme.of(context).brightness == Brightness.dark
                                      ? 0.65
                                      : 0.45) *
                                  255)
                              .round(),
                        ),
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
              child: IgnorePointer(child: widget.child),
            ),
          ),
        ),
      ),
    );

    return GamepadEditableButtonFrame(
      left: cx - half,
      top: cy - half,
      width: btnSize,
      height: btnSize,
      locked: widget.locked,
      selected: widget.selected,
      dimmed: widget.dimmed,
      colliding: _colliding || _nearEdgeWarning || widget.externalWarning,
      dragging: _dragging || widget.externalWarning,
      selectedScale: 1.0,
      onScaleStart: _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      onScaleEnd: (_) {
        widget.onGuideChanged?.call(const _GuideState.hidden());
        if (_colliding || _dragging || _nearEdgeWarning) {
          setState(() {
            _colliding = false;
            _dragging = false;
            _nearEdgeWarning = false;
          });
        }
        widget.onEnd();
      },
      onTap: widget.onSelect,
      selectedShadows: const [],
      child: buttonContent,
    );
  }

  bool _isButtonEditId(String id) {
    return id == kBtnTriangleId ||
        id == kBtnCrossId ||
        id == kBtnSquareId ||
        id == kBtnCircleId;
  }
}
