// lib/features/gamepad/gamepad_mode_edit.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/ble/ble_manager.dart';
import '../../core/ble/joystick_packet.dart';
import '../../core/ui/gamepad_assets.dart';
import '../../core/ui/gamepad_components.dart';
import '../../core/ui/gamepad_edit_metrics.dart';
import '../../core/ui/gamepad_skin.dart';
import '../../core/ui/gamepad_tutorial_overlay_components.dart';
import '../../core/widgets/gamepad_appbar_controls.dart';
import '../../core/widgets/connection_status_badge.dart';
import '../../core/widgets/gamepad_app_bar.dart';
import '../../core/utils/orientation_utils.dart';
import '../../core/ui/language_controller.dart';
import 'widgets/gamepad_telemetry_chip.dart';

const String kIdle = '0';

const String kCmdUp = 'F';
const String kCmdDown = 'B';
const String kCmdLeft = 'L';
const String kCmdRight = 'R';

const String kCmdTriangle = 'T';
const String kCmdCross = 'X';
const String kCmdSquare = 'S';
const String kCmdCircle = 'C';

const int kLoopHz = 60;
const int kLoopMs = 1000 ~/ kLoopHz;
const int kMinActiveMs = 150;
const int kMinIdleMs = 150;

const int kMaxSendHz = 40;
const int kMaxSendMs = 1000 ~/ kMaxSendHz;

const double _minBtnSize = 0.18;
const double _maxBtnSize = 0.8;
const double _gridStep = 0.05;

const double speedRowGap = 6.0;
const double _speedPanelTopGap = 6.0;
const Set<String> _defaultLeftActiveIds = {
  'L:up',
  'L:down',
  'L:left',
  'L:right',
};
const Set<String> _defaultRightActiveIds = {
  'R:triangle',
  'R:cross',
  'R:square',
  'R:circle',
};

Color _opacity(Color color, double opacity) =>
    color.withAlpha((opacity * 255).round());

double _clampInitialButtonSize(double? value) {
  return GamepadEditMetrics.finiteDouble(
    value,
    0.30,
  ).clamp(_minBtnSize, _maxBtnSize).toDouble();
}

double _snapToGrid(double value) {
  if (_gridStep <= 0) return value;
  return (value / _gridStep).round() * _gridStep;
}

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

class GamepadModeEdit extends StatefulWidget {
  const GamepadModeEdit({super.key});

  @override
  State<GamepadModeEdit> createState() => _GamepadModeEditState();
}

class _GamepadModeEditState extends State<GamepadModeEdit> {
  static const _prefsLayoutLeft = 'gp8_layout_left';
  static const _prefsLayoutRight = 'gp8_layout_right';
  static const _prefsLayoutAll = 'gp8_layout_all';
  static const _prefsActiveLeft = 'gp8_active_left';
  static const _prefsActiveRight = 'gp8_active_right';
  static const _prefsDriveSpeed = 'gp8_drive_speed';
  static const _prefsTurnSpeed = 'gp8_turn_speed';
  static const _prefsTutorialSeen = 'gp8_tutorial_seen';
  static const _prefsTutorialPromptSeen = 'gp8_tutorial_prompt_seen';
  static const _prefsPreset1 = 'gp8_preset_1';
  static const _prefsPreset2 = 'gp8_preset_2';
  static const _prefsPreset3 = 'gp8_preset_3';

  bool _up = false;
  bool _down = false;
  bool _left = false;
  bool _right = false;

  bool _triangle = false;
  bool _cross = false;
  bool _square = false;
  bool _circle = false;

  String _command = kIdle;

  String _moveCmd = kIdle;
  String _actionCmd = '';

  int _driveSpeed = 50;
  int _turnSpeed = 50;
  bool _speedPanelOpen = false;
  bool _showTutorial = false;
  bool _showTutorialPrompt = false;
  int _tutorialStep = 0;
  bool _tutorialThai = true;
  bool _restoreAutoOrientationOnExit = false;
  late final VoidCallback _langListener;
  Rect? _tutorialTargetRect;
  GlobalKey? _tutorialTargetKey;
  final GlobalKey _tutorialStackKey = GlobalKey();
  final GlobalKey _tutorialBackKey = GlobalKey();
  final GlobalKey _tutorialCustomizeKey = GlobalKey();
  final GlobalKey _tutorialDoneKey = GlobalKey();
  final GlobalKey _tutorialButtonsKey = GlobalKey();
  final GlobalKey _tutorialSpeedKey = GlobalKey();
  final GlobalKey _tutorialSpeedPanelKey = GlobalKey();
  final GlobalKey _tutorialBtKey = GlobalKey();
  final GlobalKey _tutorialPresetKey = GlobalKey();
  final GlobalKey _tutorialHelpKey = GlobalKey();
  final GlobalKey _tutorialCmdKey = GlobalKey();
  final GlobalKey _tutorialDrvKey = GlobalKey();
  final GlobalKey _tutorialTrnKey = GlobalKey();
  final GlobalKey _tutorialDeleteKey = GlobalKey();
  final GlobalKey _tutorialResetKey = GlobalKey();
  final GlobalKey _tutorialUndoKey = GlobalKey();
  final GlobalKey _tutorialRedoKey = GlobalKey();
  final GlobalKey _tutorialGridKey = GlobalKey();
  final GlobalKey _tutorialSizeKey = GlobalKey();
  final GlobalKey _tutorialLockKey = GlobalKey();
  final GlobalKey _tutorialBlePanelKey = GlobalKey();
  final GlobalKey _tutorialButtonsPanelKey = GlobalKey();

  bool _editMode = false;
  bool _showGrid = false;
  final Set<String> _lockedIds = {};
  bool _menuOpen = false;
  Offset? _menuAnchor;
  Map<String, _ButtonLayout> _layoutAll = {};
  Set<String> _leftActive = Set<String>.from(_defaultLeftActiveIds);
  Set<String> _rightActive = Set<String>.from(_defaultRightActiveIds);
  final Set<String> _pressedIds = {};
  DateTime _lastRejectHapticAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _selectedId;
  String? _editWarningId;
  int _lastBoundaryWarningMs = 0;
  int _lastOverlapWarningMs = 0;
  Size? _panelSize;
  Timer? _editWarningTimer;
  final List<_EditSnapshot> _undoStack = [];
  final List<_EditSnapshot> _redoStack = [];
  static const int _maxHistory = 30;

  Timer? _tick;
  String _lastPacketKey = '';
  int _lastSendMs = 0;
  StreamSubscription<bool>? _bleConnSub;
  int? _bleTrafficOwner;

  void _resetInputState() {
    void apply() {
      _up = false;
      _down = false;
      _left = false;
      _right = false;
      _triangle = false;
      _cross = false;
      _square = false;
      _circle = false;
      _command = kIdle;
      _moveCmd = kIdle;
      _actionCmd = '';
      _pressedIds.clear();
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

    if (_up && !_down) btns.add(kBleBtnUp);
    if (_down && !_up) btns.add(kBleBtnDown);
    if (_left && !_right) btns.add(kBleBtnLeft);
    if (_right && !_left) btns.add(kBleBtnRight);

    if (_triangle) btns.add(kBleBtnTriangle);
    if (_cross) btns.add(kBleBtnCross);
    if (_square) btns.add(kBleBtnSquare);
    if (_circle) btns.add(kBleBtnCircle);

    return btns;
  }

  String _packetKey() => '$_command|$_driveSpeed|$_turnSpeed';

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

  String _driveSpeedLabel() => _driveSpeed.toString();
  String _turnSpeedLabel() => _turnSpeed.toString();

  void _sendBinary({bool force = false}) {
    if (!BleManager.instance.isConnected) return;
    final owner = _bleTrafficOwner;
    if (owner == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final key = _packetKey();

    if (!force) {
      if ((now - _lastSendMs) < kMaxSendMs) return;

      final changed = key != _lastPacketKey;
      final active = _command != kIdle;
      final minInterval = active ? kMinActiveMs : kMinIdleMs;

      if (!changed && (now - _lastSendMs) < minInterval) {
        return;
      }
    }

    _lastPacketKey = key;
    _lastSendMs = now;

    unawaited(
      BleManager.instance.sendJoystickBinary(
        packet: JoystickPacket(
          lx: (_driveSpeed / 100.0).clamp(0.0, 1.0),
          ly: 0,
          rx: (_turnSpeed / 100.0).clamp(0.0, 1.0),
          ry: 0,
        ),
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
      ownerName: 'gamepad_8',
    );
    final trafficOwner = _bleTrafficOwner;
    if (trafficOwner != null) {
      BleManager.instance.enableControlReconnect(
        owner: trafficOwner,
        ownerName: 'gamepad_8',
      );
      unawaited(
        BleManager.instance.autoConnectLastDevice(
          source: 'control_initial',
          owner: trafficOwner,
        ),
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
    _loadLayouts();
    _loadSpeedPrefs();
    _maybeStartTutorial();

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _restoreAutoOrientationOnExit =
        MediaQuery.sizeOf(context).shortestSide >=
        OrientationUtils.tabletShortestSide;
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

    OrientationUtils.restoreAfterControl(
      isTablet: _restoreAutoOrientationOnExit,
    );
    super.dispose();
  }

  Future<void> _loadSpeedPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final int? drive = prefs.getInt(_prefsDriveSpeed);
    final int? turn = prefs.getInt(_prefsTurnSpeed);
    if (!mounted) return;
    setState(() {
      if (drive != null) _driveSpeed = drive.clamp(0, 100);
      if (turn != null) _turnSpeed = turn.clamp(0, 100);
    });
  }

  Future<void> _saveSpeedPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsDriveSpeed, _driveSpeed);
    await prefs.setInt(_prefsTurnSpeed, _turnSpeed);
  }

  void _setDriveSpeed(int value) {
    if (_driveSpeed == value) return;
    setState(() => _driveSpeed = value);
    _saveSpeedPrefs();
  }

  void _setTurnSpeed(int value) {
    if (_turnSpeed == value) return;
    setState(() => _turnSpeed = value);
    _saveSpeedPrefs();
  }

  Future<void> _resetSpeedPrefs() async {
    setState(() {
      _driveSpeed = 50;
      _turnSpeed = 50;
    });
    await _saveSpeedPrefs();
    _sendBinary(force: true);
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
      _speedPanelOpen = false;
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
    var changed = false;

    if (_speedPanelOpen != shouldOpenSpeedPanel) {
      setState(() => _speedPanelOpen = shouldOpenSpeedPanel);
      changed = true;
    }

    return changed;
  }

  List<_TutorialStep> _tutorialSteps() {
    return [
      const _TutorialStep(
        titleTh: 'Gamepad Mode Edit',
        bodyTh: 'ภาพรวมการปรับปุ่ม ค่าควบคุม และเครื่องมือทั้งหมดในหน้านี้',
        titleEn: 'Gamepad Mode Edit',
        bodyEn:
            'Overview of button layout, control settings, and tools on this page.',
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
        titleTh: 'SPD',
        bodyTh: 'ปุ่มเปิดแผงปรับความเร็ว (SPD)',
        titleEn: 'SPD',
        bodyEn: 'Tap to open the SPD tuning panel.',
        targetKey: _tutorialSpeedKey,
        editMode: false,
      ),
      _TutorialStep(
        titleTh: 'แผงปรับความเร็ว (SPD)',
        bodyTh:
            'ปรับระดับความเร็วการขับเคลื่อน (DRV) และการเลี้ยว (TRN) ได้ตั้งแต่ 0-100% พร้อมปุ่มรีเซ็ตค่า',
        titleEn: 'SPD Tuning Panel',
        bodyEn:
            'Adjust Drive (DRV) and Turn (TRN) speed from 0-100% with a quick reset option.',
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
        titleTh: 'ความเร็วหลัก (DRV)',
        bodyTh:
            'ปรับความเร็วในการเคลื่อนที่หลัก ซึ่งนำไปประยุกต์ใช้ได้กับทุกทิศทาง',
        titleEn: 'Main Speed (DRV)',
        bodyEn: 'Adjust your primary movement speed for any direction.',
        targetKey: _tutorialDrvKey,
        editMode: false,
      ),
      _TutorialStep(
        titleTh: 'ความเร็วเสริม (TRN)',
        bodyTh:
            'ปรับความเร็วในการเลี้ยว หมุนตัว หรือใช้เป็นความเร็วเสริมในฟังก์ชันอื่นๆ',
        titleEn: 'Extra Speed (TRN)',
        bodyEn:
            'Control turning, rotation, or other secondary speed functions.',
        targetKey: _tutorialTrnKey,
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
        titleTh: 'เลือกใช้งานปุ่ม',
        bodyTh: 'เลือกปุ่มฝั่งซ้ายหรือขวาที่ต้องการแสดงบนหน้าจอ',
        titleEn: 'Buttons',
        bodyEn: 'Select which left or right buttons to display.',
        targetKey: _tutorialButtonsKey,
        editMode: true,
      ),
      _TutorialStep(
        titleTh: 'เมนูเลือกปุ่ม',
        bodyTh: 'แสดงรายการปุ่มทั้งหมดที่คุณสามารถเลือกใช้งานได้',
        titleEn: 'Button Menu',
        bodyEn: 'View all available buttons you can add to the layout.',
        editMode: true,
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
        titleTh: 'ล็อก',
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
      _speedPanelOpen = false;
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
      _speedPanelOpen = false;
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
      'layout': _encodeLayout(_layoutAll),
      'leftActive': _leftActive.toList(),
      'rightActive': _rightActive.toList(),
      'drive': _driveSpeed,
      'turn': _turnSpeed,
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
      final leftRaw = obj['leftActive'];
      final rightRaw = obj['rightActive'];
      final drive = obj['drive'];
      final turn = obj['turn'];
      if (layoutRaw is Map) {
        _layoutAll = _decodeLayout(jsonEncode(layoutRaw));
      }
      if (leftRaw is List) {
        _leftActive = leftRaw.map((e) => e.toString()).toSet();
      }
      if (rightRaw is List) {
        _rightActive = rightRaw.map((e) => e.toString()).toSet();
      }
      if (drive is num) _driveSpeed = drive.round().clamp(0, 100);
      if (turn is num) _turnSpeed = turn.round().clamp(0, 100);
      setState(() {});

      _saveLayout(_prefsLayoutAll, _layoutAll);
      _saveActive(_prefsActiveLeft, _leftActive);
      _saveActive(_prefsActiveRight, _rightActive);
      _saveSpeedPrefs();
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
                              ? 'บันทึกและเรียกใช้งานรูปแบบปุ่มพร้อมค่า DRV/TRN'
                              : 'Save and load button layouts with DRV/TRN values.',
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

  String _computeMoveCmd() {
    final bool up = _up && !_down;
    final bool down = _down && !_up;
    final bool left = _left && !_right;
    final bool right = _right && !_left;

    final v = up ? kCmdUp : (down ? kCmdDown : '');
    final h = left ? kCmdLeft : (right ? kCmdRight : '');

    if (v.isEmpty && h.isEmpty) {
      return kIdle;
    } else if (v.isNotEmpty && h.isEmpty) {
      return v;
    } else if (v.isEmpty && h.isNotEmpty) {
      return h;
    } else {
      return '$v$h';
    }
  }

  String _computeActionCmd() {
    final buf = StringBuffer();
    if (_triangle) buf.write(kCmdTriangle);
    if (_cross) buf.write(kCmdCross);
    if (_square) buf.write(kCmdSquare);
    if (_circle) buf.write(kCmdCircle);
    return buf.toString();
  }

  void _updateCommand() {
    _moveCmd = _computeMoveCmd();
    _actionCmd = _computeActionCmd();

    String combined;
    if (_moveCmd == kIdle && _actionCmd.isEmpty) {
      combined = kIdle;
    } else if (_moveCmd != kIdle && _actionCmd.isEmpty) {
      combined = _moveCmd;
    } else if (_moveCmd == kIdle && _actionCmd.isNotEmpty) {
      combined = _actionCmd;
    } else {
      combined = '$_moveCmd$_actionCmd';
    }

    setState(() {
      _command = combined;
    });
    if (combined == kIdle && BleManager.instance.isConnected) {
      _sendBinary(force: true);
    }
  }

  Future<void> _loadLayouts() async {
    final prefs = await SharedPreferences.getInstance();
    final leftRaw = prefs.getString(_prefsLayoutLeft);
    final rightRaw = prefs.getString(_prefsLayoutRight);
    final allRaw = prefs.getString(_prefsLayoutAll);
    final leftActiveRaw = prefs.getString(_prefsActiveLeft);
    final rightActiveRaw = prefs.getString(_prefsActiveRight);

    if (allRaw != null && allRaw.isNotEmpty) {
      _layoutAll = _decodeLayout(allRaw);
    } else {
      if (leftRaw != null && leftRaw.isNotEmpty) {
        final leftLayout = _decodeLayout(leftRaw);
        _layoutAll.addAll(_remapLayout(leftLayout, 0.0, 0.5));
      }
      if (rightRaw != null && rightRaw.isNotEmpty) {
        final rightLayout = _decodeLayout(rightRaw);
        _layoutAll.addAll(_remapLayout(rightLayout, 0.5, 0.5));
      }
    }
    if (leftActiveRaw != null && leftActiveRaw.isNotEmpty) {
      _leftActive = _decodeIdList(leftActiveRaw);
    } else {
      _leftActive = Set<String>.from(_defaultLeftActiveIds);
    }
    if (rightActiveRaw != null && rightActiveRaw.isNotEmpty) {
      _rightActive = _decodeIdList(rightActiveRaw);
    } else {
      _rightActive = Set<String>.from(_defaultRightActiveIds);
    }

    _layoutAll.removeWhere(
      (k, _) => !_leftActive.contains(k) && !_rightActive.contains(k),
    );
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

  Map<String, _ButtonLayout> _remapLayout(
    Map<String, _ButtonLayout> layout,
    double offsetX,
    double scaleX,
  ) {
    final out = <String, _ButtonLayout>{};
    layout.forEach((k, v) {
      out[k] = _ButtonLayout(offsetX + v.cx * scaleX, v.cy, v.size);
    });
    return out;
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
              GamepadEditMetrics.clampUnit(cx, 0.5),
              GamepadEditMetrics.clampUnit(cy, 0.5),
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
      leftActive: Set<String>.from(_leftActive),
      rightActive: Set<String>.from(_rightActive),
      lockedIds: Set<String>.from(_lockedIds),
      selectedId: _selectedId,
    );
  }

  void _applySnapshot(_EditSnapshot snap) {
    _layoutAll = _cloneLayout(snap.layoutAll);
    _leftActive = Set<String>.from(snap.leftActive);
    _rightActive = Set<String>.from(snap.rightActive);
    _lockedIds
      ..clear()
      ..addAll(snap.lockedIds);
    _selectedId = snap.selectedId;

    _layoutAll.removeWhere(
      (k, _) => !_leftActive.contains(k) && !_rightActive.contains(k),
    );
    _lockedIds.removeWhere((id) => !_layoutAll.containsKey(id));

    _pressedIds.removeWhere((id) => !_layoutAll.containsKey(id));
    _up = false;
    _down = false;
    _left = false;
    _right = false;
    _triangle = false;
    _cross = false;
    _square = false;
    _circle = false;
    _command = kIdle;
  }

  void _persistEditState() {
    _saveLayout(_prefsLayoutAll, _layoutAll);
    _saveActive(_prefsActiveLeft, _leftActive);
    _saveActive(_prefsActiveRight, _rightActive);
  }

  void _pushHistory() {
    _undoStack.add(_captureSnapshot());
    if (_undoStack.length > _maxHistory) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void _startEditTransform() {
    _pushHistory();
    if (_editWarningId != null) {
      setState(() => _editWarningId = null);
    }
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    setState(() {
      _redoStack.add(_captureSnapshot());
      _applySnapshot(_undoStack.removeLast());
    });
    _persistEditState();
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    setState(() {
      _undoStack.add(_captureSnapshot());
      _applySnapshot(_redoStack.removeLast());
    });
    _persistEditState();
  }

  void _adjustSelectedSize(double delta) {
    final id = _selectedId;
    if (id == null) return;
    if (_lockedIds.contains(id)) return;

    final panelSize = _panelSize;
    final current = _layoutAll[id];
    if (panelSize == null || current == null) return;

    final w = panelSize.width;
    final h = panelSize.height;
    final normalizedCurrent = _normalizeButtonLayoutForPanel(
      current,
      panelSize,
    );
    final maxSize = _maxButtonSizeForPanel(panelSize);
    final minSize = math.min(_minBtnSize, maxSize);
    final unclamped = normalizedCurrent.size + delta;
    final nextSize = unclamped.clamp(minSize, maxSize).toDouble();
    if (nextSize == normalizedCurrent.size) {
      final atMax = unclamped >= maxSize;
      _showSizeLimit(atMax);
      _flashEditWarning(id);
      return;
    }
    final sizePx = GamepadEditMetrics.sizePx(panelSize, nextSize);
    final cx = GamepadEditMetrics.safeCenterCoordinate(
      value: normalizedCurrent.cx * w,
      extent: w,
      itemExtent: sizePx,
      leadingPadding: GamepadEditMetrics.safeEdgePad,
      trailingPadding: GamepadEditMetrics.safeEdgePad,
    );
    final cy = GamepadEditMetrics.safeCenterCoordinate(
      value: normalizedCurrent.cy * h,
      extent: h,
      itemExtent: sizePx,
      leadingPadding: GamepadEditMetrics.safeTopEdgePad,
      trailingPadding: GamepadEditMetrics.safeEdgePad,
    );

    var collides = false;
    for (final entry in _layoutAll.entries) {
      if (entry.key == id) continue;
      if (!entry.key.startsWith('L:') && !entry.key.startsWith('R:')) continue;
      final other = _normalizeButtonLayoutForPanel(entry.value, panelSize);
      final ox = other.cx * w;
      final oy = other.cy * h;
      final otherSizePx = GamepadEditMetrics.sizePx(panelSize, other.size);
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
      setState(() => _editWarningId = id);
      _showOverlapWarning();
      return;
    }

    _pushHistory();
    setState(() {
      final nextLayout = Map<String, _ButtonLayout>.from(_layoutAll);
      nextLayout[id] = _ButtonLayout(cx / w, cy / h, nextSize);
      _layoutAll = nextLayout;
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
    final msg = atMax
        ? 'Max size reached / ถึงขนาดสูงสุดแล้ว'
        : 'Min size reached / ถึงขนาดต่ำสุดแล้ว';
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

  // ignore: unused_element
  Widget _buildResizeBar() {
    return const SizedBox.shrink();
  }

  Widget _buildGridOverlay() {
    if (!_editMode || !_showGrid) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final themeB = theme.brightness;
    final platformB = MediaQuery.of(context).platformBrightness;
    final isDark = themeB == Brightness.dark || platformB == Brightness.dark;
    final base = isDark ? Colors.white : Colors.black;
    final minor = _opacity(base, isDark ? 0.16 : 0.14);
    final major = _opacity(base, isDark ? 0.30 : 0.24);
    return Positioned.fill(
      child: IgnorePointer(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: CustomPaint(
            painter: _GridPainter(
              step: _gridStep,
              minorColor: minor,
              majorColor: major,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }

  void _resetLayouts() async {
    _pushHistory();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsLayoutAll);
    await prefs.remove(_prefsLayoutLeft);
    await prefs.remove(_prefsLayoutRight);
    await prefs.remove(_prefsActiveLeft);
    await prefs.remove(_prefsActiveRight);
    setState(() {
      _layoutAll = {};
      _leftActive = Set<String>.from(_defaultLeftActiveIds);
      _rightActive = Set<String>.from(_defaultRightActiveIds);
      _lockedIds.clear();
      _pressedIds.clear();
      _selectedId = null;
      _editWarningId = null;
      _up = false;
      _down = false;
      _left = false;
      _right = false;
      _triangle = false;
      _cross = false;
      _square = false;
      _circle = false;
    });
    _updateCommand();
  }

  void _toggleActive(String id, bool isLeft) {
    _pushHistory();
    setState(() {
      if (isLeft) {
        if (_leftActive.contains(id)) {
          _leftActive.remove(id);
          _layoutAll.remove(id);
          _pressedIds.remove(id);
          _lockedIds.remove(id);
          if (_selectedId == id) _selectedId = null;
          if (id == 'L:up') _up = false;
          if (id == 'L:down') _down = false;
          if (id == 'L:left') _left = false;
          if (id == 'L:right') _right = false;
        } else {
          _leftActive.add(id);
        }
        _saveActive(_prefsActiveLeft, _leftActive);
      } else {
        if (_rightActive.contains(id)) {
          _rightActive.remove(id);
          _layoutAll.remove(id);
          _pressedIds.remove(id);
          _lockedIds.remove(id);
          if (_selectedId == id) _selectedId = null;
          if (id == 'R:triangle') _triangle = false;
          if (id == 'R:cross') _cross = false;
          if (id == 'R:square') _square = false;
          if (id == 'R:circle') _circle = false;
        } else {
          _rightActive.add(id);
        }
        _saveActive(_prefsActiveRight, _rightActive);
      }
    });
  }

  void _removeSelected() {
    final id = _selectedId;
    if (id == null) return;
    _toggleActive(id, id.startsWith('L:'));
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
    if (Platform.isIOS) {
      return GestureDetector(
        key: _tutorialButtonsKey,
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _menuAnchor = d.globalPosition,
        onTap: () {
          gamepadBuzz();
          _showEditMenuIOS();
        },
        child: _glassTopPill(
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
        ),
      );
    }

    return _glassTopPill(
      key: _tutorialButtonsKey,
      onTap: () {
        gamepadBuzz();
        _showEditMenuAndroid();
      },
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 0),
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

  Future<void> _showEditMenuAndroid() async {
    if (_menuOpen) return;
    _menuOpen = true;
    if (!mounted) {
      _menuOpen = false;
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: false,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black87,
      builder: (context) {
        final isThai = LanguageController.isThai.value;
        Widget row(
          String id,
          String label,
          bool active,
          void Function(VoidCallback fn) setSheetState,
        ) {
          final accent = const Color(0xFF38BDF8);
          final rowIsDark = Theme.of(context).brightness == Brightness.dark;
          final rowTextColor = _opacity(
            rowIsDark ? Colors.white : const Color(0xFF0F172A),
            0.92,
          );
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              gamepadBuzz();
              if (id.startsWith('L:')) {
                _toggleActive(id, true);
              } else if (id.startsWith('R:')) {
                _toggleActive(id, false);
              }
              setSheetState(() {});
            },
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
                              rowIsDark
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
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
                            rowIsDark ? Colors.white : const Color(0xFF0F172A),
                            0.30,
                          ),
                  ),
                ],
              ),
            ),
          );
        }

        final maxHeight = MediaQuery.of(context).size.height * 0.7;
        final scrollController = ScrollController();
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final accent = const Color(0xFF38BDF8);
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(
              color: isDark
                  ? _opacity(const Color(0xFF020817), 0.86)
                  : _opacity(const Color(0xFFF8FAFC), 0.96),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _opacity(const Color(0xFF7DD3FC), isDark ? 0.46 : 0.26),
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
              child: StatefulBuilder(
                builder: (context, setSheetState) {
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
                                        width: 20,
                                        height: 20,
                                        decoration: BoxDecoration(
                                          color: _opacity(
                                            accent,
                                            isDark ? 0.20 : 0.12,
                                          ),
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
                                          color: _opacity(
                                            isDark
                                                ? Colors.white
                                                : const Color(0xFF0F172A),
                                            0.94,
                                          ),
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
                                      isDark
                                          ? Colors.white
                                          : const Color(0xFF0F172A),
                                      0.72,
                                    ),
                                  ),
                                  child: Text(isThai ? 'ยกเลิก' : 'Cancel'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              isThai ? 'ปุ่มซ้าย' : 'Left pad',
                              style: TextStyle(
                                color: _opacity(
                                  isDark
                                      ? Colors.white
                                      : const Color(0xFF0F172A),
                                  0.70,
                                ),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            row(
                              'L:up',
                              isThai ? 'ซ้าย: ขึ้น' : 'Left: Up',
                              _leftActive.contains('L:up'),
                              setSheetState,
                            ),
                            const SizedBox(height: 6),
                            row(
                              'L:down',
                              isThai ? 'ซ้าย: ลง' : 'Left: Down',
                              _leftActive.contains('L:down'),
                              setSheetState,
                            ),
                            const SizedBox(height: 6),
                            row(
                              'L:left',
                              isThai ? 'ซ้าย: ซ้าย' : 'Left: Left',
                              _leftActive.contains('L:left'),
                              setSheetState,
                            ),
                            const SizedBox(height: 6),
                            row(
                              'L:right',
                              isThai ? 'ซ้าย: ขวา' : 'Left: Right',
                              _leftActive.contains('L:right'),
                              setSheetState,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              isThai ? 'ปุ่มขวา' : 'Right pad',
                              style: TextStyle(
                                color: _opacity(
                                  isDark
                                      ? Colors.white
                                      : const Color(0xFF0F172A),
                                  0.70,
                                ),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            row(
                              'R:triangle',
                              isThai ? 'ขวา: Triangle' : 'Right: Triangle',
                              _rightActive.contains('R:triangle'),
                              setSheetState,
                            ),
                            const SizedBox(height: 6),
                            row(
                              'R:cross',
                              isThai ? 'ขวา: Cross' : 'Right: Cross',
                              _rightActive.contains('R:cross'),
                              setSheetState,
                            ),
                            const SizedBox(height: 6),
                            row(
                              'R:square',
                              isThai ? 'ขวา: Square' : 'Right: Square',
                              _rightActive.contains('R:square'),
                              setSheetState,
                            ),
                            const SizedBox(height: 6),
                            row(
                              'R:circle',
                              isThai ? 'ขวา: Circle' : 'Right: Circle',
                              _rightActive.contains('R:circle'),
                              setSheetState,
                            ),
                            const SizedBox(height: 4),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );

    _menuOpen = false;
  }

  Future<void> _showEditMenuIOS() async {
    if (_menuOpen) return;
    _menuOpen = true;
    if (!mounted) {
      _menuOpen = false;
      return;
    }
    await showCupertinoModalPopup<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      anchorPoint: _menuAnchor,
      builder: (context) {
        CupertinoActionSheetAction action(
          String id,
          String label,
          bool active,
          void Function(VoidCallback fn) setSheetState,
        ) {
          return CupertinoActionSheetAction(
            onPressed: () {
              gamepadBuzz();
              if (id.startsWith('L:')) {
                _toggleActive(id, true);
              } else if (id.startsWith('R:')) {
                _toggleActive(id, false);
              }
              setSheetState(() {});
            },
            child: Row(
              children: [
                Icon(
                  active ? CupertinoIcons.check_mark : CupertinoIcons.square,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(label),
              ],
            ),
          );
        }

        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF7DD3FC)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: StatefulBuilder(
                builder: (context, setSheetState) {
                  return CupertinoActionSheet(
                    title: Row(
                      children: [
                        const Expanded(child: Text('Buttons')),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          onPressed: () {
                            gamepadBuzz();
                            Navigator.pop(context);
                          },
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                    actions: [
                      action(
                        'L:up',
                        'Left: Up',
                        _leftActive.contains('L:up'),
                        setSheetState,
                      ),
                      action(
                        'L:down',
                        'Left: Down',
                        _leftActive.contains('L:down'),
                        setSheetState,
                      ),
                      action(
                        'L:left',
                        'Left: Left',
                        _leftActive.contains('L:left'),
                        setSheetState,
                      ),
                      action(
                        'L:right',
                        'Left: Right',
                        _leftActive.contains('L:right'),
                        setSheetState,
                      ),
                      action(
                        'R:triangle',
                        'Right: Triangle',
                        _rightActive.contains('R:triangle'),
                        setSheetState,
                      ),
                      action(
                        'R:cross',
                        'Right: Cross',
                        _rightActive.contains('R:cross'),
                        setSheetState,
                      ),
                      action(
                        'R:square',
                        'Right: Square',
                        _rightActive.contains('R:square'),
                        setSheetState,
                      ),
                      action(
                        'R:circle',
                        'Right: Circle',
                        _rightActive.contains('R:circle'),
                        setSheetState,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
    _menuOpen = false;
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

  Widget _glassTopPill({
    required Widget child,
    VoidCallback? onTap,
    Key? key,
    EdgeInsets padding = const EdgeInsets.symmetric(
      horizontal: 10,
      vertical: 6,
    ),
  }) {
    return GamepadGlassTopPill(
      pillKey: key,
      onTap: onTap,
      padding: padding,
      child: child,
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

  Widget _appBarBadge(String label, String value) {
    IconData icon;
    Color accent;
    switch (label) {
      case 'SPD':
        icon = Icons.speed_rounded;
        accent = const Color(0xFF38BDF8);
        break;
      case 'CMD':
        icon = Icons.tune_rounded;
        accent = const Color(0xFFF59E0B);
        break;
      case 'DRV':
        icon = Icons.sports_motorsports_rounded;
        accent = const Color(0xFF22C55E);
        break;
      case 'TRN':
        icon = Icons.rotate_right_rounded;
        accent = const Color(0xFF38BDF8);
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

  Widget _speedToggle() {
    return GamepadSpeedTogglePill(
      pillKey: _tutorialSpeedKey,
      expanded: _speedPanelOpen,
      accent: _barAccent('SPD'),
      label: 'D$_driveSpeed T$_turnSpeed',
      onTap: () {
        setState(() => _speedPanelOpen = !_speedPanelOpen);
      },
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
      _buildEditMenu(compact: true),
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
      _actionPill(
        key: _tutorialDeleteKey,
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
          _resetLayouts();
        },
      ),
      _toolIconPill(
        key: _tutorialUndoKey,
        icon: Icons.undo_rounded,
        label: isThai ? 'ย้อน' : 'Undo',
        accent: const Color(0xFFA78BFA),
        onTap: canUndo
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
        onTap: canRedo
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
        enabled: sizeEnabled,
      ),
      _toolIconPill(
        key: _tutorialLockKey,
        icon: selectedLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
        label: isThai ? 'ล็อก' : 'Lock',
        accent: const Color(0xFFFBBF24),
        active: selectedLocked,
        onTap: hasSelection
            ? () {
                gamepadBuzz();
                _toggleSelectedLock();
              }
            : null,
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
        key: _tutorialDeleteKey,
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
          _resetLayouts();
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

  Widget _speedSlider({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = label == 'DRV'
        ? const Color(0xFF22C55E)
        : const Color(0xFF38BDF8);
    final surface = isDark
        ? _opacity(const Color(0xFF0F172A), 0.84)
        : _opacity(Colors.white, 0.9);
    final border = _opacity(accent, isDark ? 0.28 : 0.18);

    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: border),
          boxShadow: [
            BoxShadow(
              color: _opacity(Colors.black, isDark ? 0.18 : 0.06),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 24,
              decoration: BoxDecoration(
                color: _opacity(accent, isDark ? 0.18 : 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: accent,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: 40,
              height: 26,
              decoration: BoxDecoration(
                color: _opacity(accent, isDark ? 0.14 : 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                value.toString(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : theme.colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 110,
              child: RotatedBox(
                quarterTurns: 3,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 6,
                    activeTrackColor: accent,
                    inactiveTrackColor: _opacity(accent, 0.16),
                    thumbColor: Colors.white,
                    overlayColor: _opacity(accent, 0.12),
                    trackShape: const _GradientTrackShape(),
                  ),
                  child: Slider(
                    value: value.toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 100,
                    label: value.toString(),
                    onChanged: (v) => onChanged(_snapSpeed(v)),
                    onChangeEnd: (_) => _sendBinary(force: true),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _speedScaleLabel('0'),
                _speedScaleLabel('50'),
                _speedScaleLabel('100'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  int _snapSpeed(double v) {
    final int raw = v.round();
    const int step = 10;
    const int snapRadius = 2; // snap when within ?2 of a 10s step
    final int mod = raw % step;
    if (mod <= snapRadius || mod >= (step - snapRadius)) {
      return ((raw + step ~/ 2) ~/ step) * step;
    }
    return raw;
  }

  Widget _speedScaleLabel(String label) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Text(
      label,
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        color: _opacity(
          isDark ? Colors.white : theme.colorScheme.onSurface,
          0.58,
        ),
      ),
    );
  }

  Widget _buildSpeedPanel() {
    if (!_speedPanelOpen) return const SizedBox.shrink();
    final isThai = LanguageController.isThai.value;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    final topInset = media.padding.top;
    final screenWidth = media.size.width;
    final panelTop =
        topInset +
        GamepadAppBarMetrics.forWidth(screenWidth).toolbarExtent +
        _speedPanelTopGap;
    final panelWidth = math.min(screenWidth - 24, 250.0);
    final screenHeight = MediaQuery.of(context).size.height;
    final maxPanelHeight = math.max(180.0, screenHeight - panelTop - 10);

    return Positioned(
      top: panelTop,
      right: 12,
      child: SizedBox(
        key: _tutorialSpeedPanelKey,
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
                child: SingleChildScrollView(
                  padding: EdgeInsets.zero,
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
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: _opacity(
                                  const Color(0xFF38BDF8),
                                  isDark ? 0.18 : 0.12,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.speed_rounded,
                                size: 13,
                                color: Color(0xFF38BDF8),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                isThai
                                    ? 'ปรับความเร็วการควบคุม'
                                    : 'Speed Tuning',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  color: isDark
                                      ? Colors.white
                                      : theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            TextButton.icon(
                              onPressed: _resetSpeedPrefs,
                              icon: const Icon(
                                Icons.restart_alt_rounded,
                                size: 13,
                              ),
                              label: Text(isThai ? 'รีเซ็ต' : 'Reset'),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF7DD3FC),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                minimumSize: const Size(40, 40),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                textStyle: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                  side: BorderSide(
                                    color: _opacity(
                                      const Color(0xFF7DD3FC),
                                      0.28,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip: isThai ? 'ปิด' : 'Close',
                              onPressed: () =>
                                  setState(() => _speedPanelOpen = false),
                              icon: const Icon(Icons.close_rounded, size: 17),
                              color: _opacity(
                                isDark
                                    ? Colors.white
                                    : theme.colorScheme.onSurface,
                                0.72,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                width: 40,
                                height: 40,
                              ),
                              style: IconButton.styleFrom(
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                backgroundColor: _opacity(
                                  isDark
                                      ? Colors.white
                                      : const Color(0xFF0F172A),
                                  isDark ? 0.06 : 0.04,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _speedSlider(
                              label: 'DRV',
                              value: _driveSpeed,
                              onChanged: _setDriveSpeed,
                            ),
                            const SizedBox(width: 8),
                            _speedSlider(
                              label: 'TRN',
                              value: _turnSpeed,
                              onChanged: _setTurnSpeed,
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
    if (step.titleEn != 'Preview Buttons') return const SizedBox.shrink();

    final isThai = LanguageController.isThai.value;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final panelWidth = math.min(screenWidth - 24, 560.0);
    final maxPanelHeight = math.max(220.0, screenHeight * 0.58);
    final listMaxHeight = math.min(180.0, maxPanelHeight * 0.48);
    const accent = Color(0xFF38BDF8);
    final titleColor = isDark
        ? _opacity(Colors.white, 0.94)
        : _opacity(theme.colorScheme.onSurface, 0.95);
    final bodyColor = isDark
        ? _opacity(Colors.white, 0.72)
        : _opacity(theme.colorScheme.onSurface, 0.72);

    return Positioned.fill(
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: SizedBox(
              key: _tutorialButtonsPanelKey,
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
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                                        width: 20,
                                        height: 20,
                                        decoration: BoxDecoration(
                                          color: _opacity(
                                            accent,
                                            isDark ? 0.20 : 0.12,
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
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
                                  onPressed: null,
                                  style: TextButton.styleFrom(
                                    foregroundColor: _opacity(bodyColor, 0.95),
                                  ),
                                  child: Text(isThai ? 'ยกเลิก' : 'Cancel'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              isThai ? 'ปุ่มซ้าย' : 'Left pad',
                              style: TextStyle(
                                color: bodyColor,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
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
                                    _buttonsPreviewRow(
                                      label: isThai ? 'ซ้าย: ขึ้น' : 'Left: Up',
                                      active: true,
                                      isDark: isDark,
                                    ),
                                    const SizedBox(height: 6),
                                    _buttonsPreviewRow(
                                      label: isThai ? 'ซ้าย: ลง' : 'Left: Down',
                                      active: false,
                                      isDark: isDark,
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

  Widget _buttonsPreviewRow({
    required String label,
    required bool active,
    required bool isDark,
  }) {
    const accent = Color(0xFF38BDF8);
    final rowTextColor = _opacity(
      isDark ? Colors.white : const Color(0xFF0F172A),
      0.92,
    );
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
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: _opacity(accent, active ? 0.22 : 0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _opacity(accent, active ? 0.66 : 0.25)),
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
    final isPreviewButtonsStep = step.titleEn == 'Preview Buttons';
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
                              ? 'ระบบจะแสดง Tutorial การใช้งานปุ่มและเครื่องมือในหน้า Gamepad Mode Edit'
                              : 'The app will show a tutorial for buttons and tools on the Gamepad Mode Edit page.',
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

  Widget _buildDimOverlay() {
    return const SizedBox.shrink();
  }

  void _sendLoop() {
    _sendBinary();
  }

  bool _applyPressLimit(String id, bool isDown) {
    if (isDown) {
      if (_pressedIds.length >= 2 && !_pressedIds.contains(id)) {
        final now = DateTime.now();
        if (now.difference(_lastRejectHapticAt) >
            const Duration(milliseconds: 200)) {
          HapticFeedback.selectionClick();
          _lastRejectHapticAt = now;
        }
        return false;
      }
      _pressedIds.add(id);
    } else {
      _pressedIds.remove(id);
    }
    return true;
  }

  void _onLeftPress(String id, bool isDown) {
    if (!_applyPressLimit(id, isDown)) {
      return;
    }

    if (id == kCmdUp) _up = isDown;
    if (id == kCmdDown) _down = isDown;
    if (id == kCmdLeft) _left = isDown;
    if (id == kCmdRight) _right = isDown;

    _updateCommand();
  }

  void _onRightPress(String id, bool isDown) {
    if (!_applyPressLimit(id, isDown)) {
      return;
    }

    if (id == kCmdTriangle) _triangle = isDown;
    if (id == kCmdCross) _cross = isDown;
    if (id == kCmdSquare) _square = isDown;
    if (id == kCmdCircle) _circle = isDown;

    _updateCommand();
  }

  void _onAnyPress(String id, bool isDown) {
    if (id == kCmdUp || id == kCmdDown || id == kCmdLeft || id == kCmdRight) {
      _onLeftPress(id, isDown);
      return;
    }
    _onRightPress(id, isDown);
  }

  List<String> _allActiveIds() {
    return [..._leftActive, ..._rightActive];
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
          appBar: _editMode
              ? _buildEditModeAppBar(isThai)
              : GamepadUnifiedAppBar(
                  toolbarHeight: appBarMetrics.toolbarExtent,
                  leading: _editMode ? null : _buildAppBarBackButton(),
                  speedToggle: _editMode
                      ? _buildEditAppBarRow(
                          isThai,
                          _editAppBarGap(
                            isThai: isThai,
                            metrics: appBarMetrics,
                          ),
                        )
                      : _speedToggle(),
                  cmdChip: _editMode
                      ? null
                      : SizedBox(
                          key: _tutorialCmdKey,
                          child: _appBarBadge('CMD', _commandByteLabel()),
                        ),
                  drvChip: _editMode
                      ? null
                      : SizedBox(
                          key: _tutorialDrvKey,
                          child: _appBarBadge('DRV', _driveSpeedLabel()),
                        ),
                  trnChip: _editMode
                      ? null
                      : SizedBox(
                          key: _tutorialTrnKey,
                          child: _appBarBadge('TRN', _turnSpeedLabel()),
                        ),
                  bleBadge: _editMode
                      ? null
                      : ConnectionStatusBadge(
                          key: _tutorialBtKey,
                          appBarMetrics: appBarMetrics,
                        ),
                  actionsBuilder: _editMode
                      ? null
                      : (gap) {
                          return GamepadAppBarActionGroup(
                            gap: gap,
                            items: [
                              GamepadAppBarActionItem(
                                key: _tutorialCustomizeKey,
                                label: isThai ? 'แก้ไข' : 'Edit',
                                icon: Icons.edit,
                                accent: const Color(0xFF60A5FA),
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
                                accent: _barAccent('PRESET'),
                                onTap: () {
                                  gamepadBuzz();
                                  _showPresetSheet();
                                },
                              ),
                              GamepadAppBarActionItem(
                                key: _tutorialHelpKey,
                                label: '?',
                                icon: Icons.help_outline,
                                accent: const Color(0xFFEC4899),
                                iconOnly: true,
                                onTap: () {
                                  gamepadBuzz();
                                  _restartTutorial();
                                },
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
                          child: Column(
                            children: [
                              Expanded(
                                child: _editMode
                                    ? _EditablePadPanel(
                                        ids: _allActiveIds(),
                                        specs: const {
                                          'L:up': _BtnSpec(
                                            'Up',
                                            kCmdUp,
                                            kGamepad8AssetUp,
                                          ),
                                          'L:down': _BtnSpec(
                                            'Down',
                                            kCmdDown,
                                            kGamepad8AssetDown,
                                          ),
                                          'L:left': _BtnSpec(
                                            'Left',
                                            kCmdLeft,
                                            kGamepad8AssetLeft,
                                          ),
                                          'L:right': _BtnSpec(
                                            'Right',
                                            kCmdRight,
                                            kGamepad8AssetRight,
                                          ),
                                          'R:triangle': _BtnSpec(
                                            'Triangle',
                                            kCmdTriangle,
                                            kGamepad8AssetTriangle,
                                          ),
                                          'R:cross': _BtnSpec(
                                            'Cross',
                                            kCmdCross,
                                            kGamepad8AssetCross,
                                          ),
                                          'R:square': _BtnSpec(
                                            'Square',
                                            kCmdSquare,
                                            kGamepad8AssetSquare,
                                          ),
                                          'R:circle': _BtnSpec(
                                            'Circle',
                                            kCmdCircle,
                                            kGamepad8AssetCircle,
                                          ),
                                        },
                                        layout: _layoutAll,
                                        onLayoutChanged: (next) {
                                          setState(() {
                                            _layoutAll = next;
                                            _editWarningId = null;
                                          });
                                          _saveLayout(
                                            _prefsLayoutAll,
                                            _layoutAll,
                                          );
                                        },
                                        selectedId: _selectedId,
                                        lockedIds: _lockedIds,
                                        snapToGrid: _showGrid,
                                        onSelect: _selectButton,
                                        onPanelSize: (size) {
                                          _panelSize = size;
                                        },
                                        onStart: _startEditTransform,
                                        onCollision: _showOverlapWarning,
                                        onBoundaryWarning: _showBoundaryWarning,
                                        warningId: _editWarningId,
                                      )
                                    : _LayoutPadPanel(
                                        ids: _allActiveIds(),
                                        specs: const {
                                          'L:up': _BtnSpec(
                                            'Up',
                                            kCmdUp,
                                            kGamepad8AssetUp,
                                          ),
                                          'L:down': _BtnSpec(
                                            'Down',
                                            kCmdDown,
                                            kGamepad8AssetDown,
                                          ),
                                          'L:left': _BtnSpec(
                                            'Left',
                                            kCmdLeft,
                                            kGamepad8AssetLeft,
                                          ),
                                          'L:right': _BtnSpec(
                                            'Right',
                                            kCmdRight,
                                            kGamepad8AssetRight,
                                          ),
                                          'R:triangle': _BtnSpec(
                                            'Triangle',
                                            kCmdTriangle,
                                            kGamepad8AssetTriangle,
                                          ),
                                          'R:cross': _BtnSpec(
                                            'Cross',
                                            kCmdCross,
                                            kGamepad8AssetCross,
                                          ),
                                          'R:square': _BtnSpec(
                                            'Square',
                                            kCmdSquare,
                                            kGamepad8AssetSquare,
                                          ),
                                          'R:circle': _BtnSpec(
                                            'Circle',
                                            kCmdCircle,
                                            kGamepad8AssetCircle,
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
                                        onPressChanged: _onAnyPress,
                                      ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              _buildDimOverlay(),
              _buildSpeedPanel(),
              _buildBlePreviewPanel(),
            ],
          ),
        ),
        _buildTutorialOverlay(),
        _buildTutorialPromptOverlay(),
      ],
    );
  }
}

class _GradientTrackShape extends SliderTrackShape {
  const _GradientTrackShape();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackHeight = sliderTheme.trackHeight ?? 2;
    final double trackLeft = offset.dx;
    final double trackTop =
        offset.dy + (parentBox.size.height - trackHeight) / 2;
    final double trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    required TextDirection textDirection,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final radius = Radius.circular(trackRect.height / 2);
    final rrect = RRect.fromRectAndRadius(trackRect, radius);

    const gradient = LinearGradient(
      colors: [
        Color(0xFF22C55E), // green
        Color(0xFFFACC15), // yellow
        Color(0xFFEF4444), // red
      ],
      stops: [0.0, 0.55, 1.0],
    );

    final paint = Paint()..shader = gradient.createShader(trackRect);
    context.canvas.drawRRect(rrect, paint);
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
  final String label, sendValue, asset;
  const _BtnSpec(this.label, this.sendValue, this.asset);
}

Map<String, _ButtonLayout> _defaultLayoutForIds(Size size, List<String> ids) {
  final w = size.width;
  final h = size.height;
  final s = GamepadEditMetrics.panelUnit(size);
  final btn = s * 0.30;
  final gap = s * 0.08;
  final frame = GamepadEditMetrics.defaultLayoutFrame(size);
  final cy = frame.center.dy;

  _ButtonLayout make(double x, double y) {
    return _ButtonLayout(x / w, y / h, btn / s);
  }

  final suffixMap = <String, String>{};
  for (final id in ids) {
    final parts = id.split(':');
    final key = parts.length > 1 ? parts[1] : id;
    suffixMap[key] = id;
  }

  final out = <String, _ButtonLayout>{};
  final hasMove =
      suffixMap.containsKey('up') ||
      suffixMap.containsKey('down') ||
      suffixMap.containsKey('left') ||
      suffixMap.containsKey('right');
  final hasAction =
      suffixMap.containsKey('triangle') ||
      suffixMap.containsKey('cross') ||
      suffixMap.containsKey('square') ||
      suffixMap.containsKey('circle');

  if (hasMove) {
    final cxLeft = frame.left + frame.width * 0.28;
    if (suffixMap.containsKey('up')) {
      out[suffixMap['up']!] = make(cxLeft, cy - gap - btn / 2);
    }
    if (suffixMap.containsKey('down')) {
      out[suffixMap['down']!] = make(cxLeft, cy + gap + btn / 2);
    }
    if (suffixMap.containsKey('left')) {
      out[suffixMap['left']!] = make(cxLeft - gap - btn / 2, cy);
    }
    if (suffixMap.containsKey('right')) {
      out[suffixMap['right']!] = make(cxLeft + gap + btn / 2, cy);
    }
  }

  if (hasAction) {
    final cxRight = frame.left + frame.width * 0.72;
    if (suffixMap.containsKey('triangle')) {
      out[suffixMap['triangle']!] = make(cxRight, cy - gap - btn / 2);
    }
    if (suffixMap.containsKey('cross')) {
      out[suffixMap['cross']!] = make(cxRight, cy + gap + btn / 2);
    }
    if (suffixMap.containsKey('square')) {
      out[suffixMap['square']!] = make(cxRight - gap - btn / 2, cy);
    }
    if (suffixMap.containsKey('circle')) {
      out[suffixMap['circle']!] = make(cxRight + gap + btn / 2, cy);
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

double _maxButtonSizeForPanel(Size panel) {
  return GamepadEditMetrics.maxCircleSizeFactorForPanel(
    panel,
    minSize: _minBtnSize,
    maxSize: _maxBtnSize,
  );
}

_ButtonLayout _normalizeButtonLayoutForPanel(_ButtonLayout layout, Size panel) {
  final maxSize = _maxButtonSizeForPanel(panel);
  final minSize = math.min(_minBtnSize, maxSize);
  return _ButtonLayout(
    GamepadEditMetrics.clampUnit(layout.cx, 0.5),
    GamepadEditMetrics.clampUnit(layout.cy, 0.5),
    GamepadEditMetrics.finiteDouble(
      layout.size,
      0.30,
    ).clamp(minSize, maxSize).toDouble(),
  );
}

bool _sameButtonLayout(_ButtonLayout a, _ButtonLayout b) {
  return a.cx == b.cx && a.cy == b.cy && a.size == b.size;
}

double _buttonDiameterForPanel(_ButtonLayout layout, Size panel) {
  final normalized = _normalizeButtonLayoutForPanel(layout, panel);
  return GamepadEditMetrics.fittedCircleDiameter(
    GamepadEditMetrics.sizePx(panel, normalized.size),
    panel,
  );
}

class _EditSnapshot {
  final Map<String, _ButtonLayout> layoutAll;
  final Set<String> leftActive;
  final Set<String> rightActive;
  final Set<String> lockedIds;
  final String? selectedId;

  const _EditSnapshot({
    required this.layoutAll,
    required this.leftActive,
    required this.rightActive,
    required this.lockedIds,
    required this.selectedId,
  });
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
    this.warningId,
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
  bool _showGuideX = false;
  bool _showGuideY = false;
  bool _guideSnapActive = false;
  double? _guideX;
  double? _guideY;

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
    if (oldWidget.selectedId != widget.selectedId) {
      _resetGuide(notify: false);
    }
  }

  void _resetGuide({bool notify = true}) {
    if (!_showGuideX &&
        !_showGuideY &&
        !_guideSnapActive &&
        _guideX == null &&
        _guideY == null) {
      return;
    }
    void clearState() {
      _showGuideX = false;
      _showGuideY = false;
      _guideSnapActive = false;
      _guideX = null;
      _guideY = null;
    }

    if (notify) {
      setState(clearState);
    } else {
      clearState();
    }
  }

  void _handleGuideChanged(_GuideState guide) {
    final nextShowX = guide.showVertical;
    final nextShowY = guide.showHorizontal;
    final nextSnap = guide.snap && (nextShowX || nextShowY);
    final nextX = nextShowX ? guide.verticalX : null;
    final nextY = nextShowY ? guide.horizontalY : null;
    if (_showGuideX == nextShowX &&
        _showGuideY == nextShowY &&
        _guideSnapActive == nextSnap &&
        _guideX == nextX &&
        _guideY == nextY) {
      return;
    }
    setState(() {
      _showGuideX = nextShowX;
      _showGuideY = nextShowY;
      _guideSnapActive = nextSnap;
      _guideX = nextX;
      _guideY = nextY;
    });
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
        final defaults = _defaultLayoutForIds(size, widget.ids);

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
          final current = _layout[id];
          if (current != null) {
            final normalized = _normalizeButtonLayoutForPanel(current, size);
            if (!_sameButtonLayout(current, normalized)) {
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

        return Stack(
          children: [
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
                asset: spec.asset,
                allLayouts: _layout,
                selected: widget.selectedId == id,
                externalWarning: widget.warningId == id,
                dimmed: widget.selectedId != null && widget.selectedId != id,
                locked: widget.lockedIds.contains(id),
                snapToGrid: widget.snapToGrid,
                onChanged: (next) {
                  setState(() => _layout[id] = next);
                },
                onGuideChanged: _handleGuideChanged,
                onEnd: () {
                  _resetGuide();
                  widget.onLayoutChanged(_layout);
                },
                onTap: () => widget.onSelect(id),
                onStart: widget.onStart,
                onCollision: widget.onCollision,
                onBoundaryWarning: widget.onBoundaryWarning,
              );
            }),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _EditGuidePainter(
                    showVertical: _showGuideX,
                    showHorizontal: _showGuideY,
                    verticalXFactor: _guideX,
                    horizontalYFactor: _guideY,
                    color: _guideSnapActive
                        ? _opacity(const Color(0xFFFACC15), 0.95)
                        : _opacity(const Color(0xFFFACC15), 0.60),
                  ),
                ),
              ),
            ),
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
        final defaults = _defaultLayoutForIds(size, ids);
        final effective = <String, _ButtonLayout>{...defaults, ...layout};
        final normalizedSavedLayout = Map<String, _ButtonLayout>.from(layout);
        var normalizedSavedChanged = false;

        final w = size.width;
        final h = size.height;

        final children = ids.map((id) {
          final spec = specs[id];
          final l = effective[id];
          if (spec == null || l == null) {
            return const SizedBox.shrink();
          }
          final normalized = _normalizeButtonLayoutForPanel(l, size);
          final saved = layout[id];
          if (saved != null && !_sameButtonLayout(saved, normalized)) {
            normalizedSavedLayout[id] = normalized;
            normalizedSavedChanged = true;
          }
          final d = _buttonDiameterForPanel(normalized, size);
          final cx = GamepadEditMetrics.safeCenterCoordinate(
            value: normalized.cx * w,
            extent: w,
            itemExtent: d,
            leadingPadding: GamepadEditMetrics.safeEdgePad,
            trailingPadding: GamepadEditMetrics.safeEdgePad,
          );
          final cy = GamepadEditMetrics.safeCenterCoordinate(
            value: normalized.cy * h,
            extent: h,
            itemExtent: d,
            leadingPadding: GamepadEditMetrics.safeTopEdgePad,
            trailingPadding: GamepadEditMetrics.safeEdgePad,
          );

          return Positioned(
            left: cx - d / 2,
            top: cy - d / 2,
            child: GamepadImageHoldButton(
              label: spec.label,
              sendValue: spec.sendValue,
              asset: spec.asset,
              diameter: d,
              showLabel: false,
              lightImpactBeforeBuzz: true,
              onPressChanged: onPressChanged,
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
  final String asset;
  final Map<String, _ButtonLayout> allLayouts;
  final bool selected;
  final bool externalWarning;
  final bool dimmed;
  final bool locked;
  final bool snapToGrid;
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
    required this.asset,
    required this.allLayouts,
    required this.selected,
    this.externalWarning = false,
    required this.dimmed,
    required this.locked,
    required this.snapToGrid,
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
  static const double _safeEdgePad = GamepadEditMetrics.safeEdgePad;
  static const double _safeTopEdgePad = GamepadEditMetrics.safeTopEdgePad;
  static const double _snapThresholdPx = 5.0;
  static const double _edgeWarnThresholdPx =
      GamepadEditMetrics.edgeWarnThresholdPx;
  bool _dragging = false;
  bool _colliding = false;
  bool _nearEdgeWarning = false;

  void _onScaleStart(ScaleStartDetails d) {
    if (widget.locked) return;
    if (!widget.selected) {
      widget.onTap();
      return;
    }
    _startFocal = d.focalPoint;
    _startLayout = _normalizeButtonLayoutForPanel(
      widget.layout,
      widget.panelSize,
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
    final normalizedStart = _normalizeButtonLayoutForPanel(
      _startLayout,
      widget.panelSize,
    );

    final dx = d.focalPoint.dx - _startFocal.dx;
    final dy = d.focalPoint.dy - _startFocal.dy;
    final moved = dx.abs() > 1 || dy.abs() > 1;
    if (moved && !_dragging) {
      setState(() => _dragging = true);
    }

    final maxSize = _maxButtonSizeForPanel(widget.panelSize);
    final minSize = math.min(_minBtnSize, maxSize);
    double size = (normalizedStart.size * d.scale)
        .clamp(minSize, maxSize)
        .toDouble();

    final sizePx = GamepadEditMetrics.sizePx(widget.panelSize, size);
    final half = sizePx / 2;

    double cx = normalizedStart.cx * w + dx;
    double cy = normalizedStart.cy * h + dy;

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

    final minX = _safeEdgePad + half;
    final maxX = w - _safeEdgePad - half;
    final minY = _safeTopEdgePad + half;
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

    var collides = false;
    for (final entry in widget.allLayouts.entries) {
      if (entry.key == widget.id) continue;
      if (!_isButtonEditId(entry.key)) continue;
      final other = _normalizeButtonLayoutForPanel(
        entry.value,
        widget.panelSize,
      );
      final ox = other.cx * w;
      final oy = other.cy * h;
      final otherSizePx = GamepadEditMetrics.sizePx(
        widget.panelSize,
        other.size,
      );
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

    widget.onChanged(_ButtonLayout(cx / w, cy / h, size));
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.panelSize.width;
    final h = widget.panelSize.height;
    final layout = _normalizeButtonLayoutForPanel(
      widget.layout,
      widget.panelSize,
    );
    final size = _buttonDiameterForPanel(layout, widget.panelSize);
    final cx = GamepadEditMetrics.safeCenterCoordinate(
      value: layout.cx * w,
      extent: w,
      itemExtent: size,
      leadingPadding: _safeEdgePad,
      trailingPadding: _safeEdgePad,
    );
    final cy = GamepadEditMetrics.safeCenterCoordinate(
      value: layout.cy * h,
      extent: h,
      itemExtent: size,
      leadingPadding: _safeTopEdgePad,
      trailingPadding: _safeEdgePad,
    );
    final dimOpacity = widget.dimmed ? 0.35 : 1.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final selectedGlow = primary.withAlpha(
      ((isDark ? 0.65 : 0.45) * 255).round(),
    );
    final warningColor = const Color(0xFFEF4444);
    final showWarning =
        _colliding || _nearEdgeWarning || widget.externalWarning;

    final buttonContent = SizedBox(
      width: size,
      height: size,
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
                padding: EdgeInsets.all(size * 0.08),
                child: ClipOval(
                  child: Image.asset(
                    widget.asset,
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
      left: cx - size / 2,
      top: cy - size / 2,
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
        onTap: widget.onTap,
        child: Opacity(
          opacity: dimOpacity,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            width: size,
            height: size,
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
            child: buttonContent,
          ),
        ),
      ),
    );
  }

  bool _isButtonEditId(String id) {
    return id.startsWith('L:') || id.startsWith('R:');
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
