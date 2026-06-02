// lib/features/linesonic/linesonic_pid_page.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/ble/ble_manager.dart';
import '../../core/ui/adaptive_page_metrics.dart';
import '../../core/ui/language_controller.dart';
import '../../core/widgets/connection_status_badge.dart';

enum _StepMode { time, checksum }

class _StepData {
  _StepData({
    required this.id,
    required this.mode,
    required String kp,
    required String kd,
    required String speed,
    required String value,
    required String afterMs,
    required String afterSpeed,
    required String stopMs,
    required String holdMs,
    required String holdThreshold,
    required this.lineColor,
    required this.holdMode,
    required this.continueAfter,
    required this.stopBetween,
    this.collapsed = false,
    bool? showOptions,
  }) : kpCtrl = TextEditingController(text: kp),
       kdCtrl = TextEditingController(text: kd),
       speedCtrl = TextEditingController(text: speed),
       valueCtrl = TextEditingController(text: value),
       afterMsCtrl = TextEditingController(text: afterMs),
       afterSpeedCtrl = TextEditingController(text: afterSpeed),
       stopMsCtrl = TextEditingController(text: stopMs),
       holdMsCtrl = TextEditingController(text: holdMs),
       holdThresholdCtrl = TextEditingController(text: holdThreshold),
       showOptions = showOptions ?? (mode != null);

  final int id;
  _StepMode? mode;
  final TextEditingController kpCtrl;
  final TextEditingController kdCtrl;
  final TextEditingController speedCtrl;
  final TextEditingController valueCtrl;
  final TextEditingController afterMsCtrl;
  final TextEditingController afterSpeedCtrl;
  final TextEditingController stopMsCtrl;
  final TextEditingController holdMsCtrl;
  final TextEditingController holdThresholdCtrl;
  int lineColor;
  int holdMode; // 0=off, 1=all black, 2=all white
  bool continueAfter;
  bool stopBetween;
  bool collapsed;
  bool showOptions;

  Map<String, dynamic> toJson() => {
    'mode': mode == null
        ? ''
        : (mode == _StepMode.checksum ? 'CHECKSUM' : 'TIME'),
    'kp': kpCtrl.text.trim().isEmpty ? '0' : kpCtrl.text.trim(),
    'kd': kdCtrl.text.trim().isEmpty ? '0' : kdCtrl.text.trim(),
    'speed': speedCtrl.text.trim().isEmpty ? '0' : speedCtrl.text.trim(),
    'value': valueCtrl.text.trim().isEmpty ? '0' : valueCtrl.text.trim(),
    'continueAfter': continueAfter,
    'afterMs': afterMsCtrl.text.trim().isEmpty ? '0' : afterMsCtrl.text.trim(),
    'afterSpeed': afterSpeedCtrl.text.trim().isEmpty
        ? '0'
        : afterSpeedCtrl.text.trim(),
    'stopBetween': stopBetween,
    'stopMs': stopMsCtrl.text.trim().isEmpty ? '0' : stopMsCtrl.text.trim(),
    'holdMode': holdMode,
    'holdMs': holdMsCtrl.text.trim().isEmpty ? '0' : holdMsCtrl.text.trim(),
    'holdThreshold': holdThresholdCtrl.text.trim().isEmpty
        ? '0'
        : holdThresholdCtrl.text.trim(),
    'lineColor': lineColor,
    'collapsed': collapsed,
    'showOptions': showOptions,
  };

  void dispose() {
    kpCtrl.dispose();
    kdCtrl.dispose();
    speedCtrl.dispose();
    valueCtrl.dispose();
    afterMsCtrl.dispose();
    afterSpeedCtrl.dispose();
    stopMsCtrl.dispose();
    holdMsCtrl.dispose();
    holdThresholdCtrl.dispose();
  }
}

class _PresetSlot {
  _PresetSlot({required this.name, required this.steps});

  String name;
  List<Map<String, dynamic>> steps;

  bool get isEmpty => steps.isEmpty;

  Map<String, dynamic> toJson() => {'name': name, 'steps': steps};

  static _PresetSlot fromJson(Map<String, dynamic> json) => _PresetSlot(
    name: (json['name'] as String?) ?? 'Preset',
    steps:
        (json['steps'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [],
  );
}

class LineSonicPidPage extends StatefulWidget {
  const LineSonicPidPage({super.key});

  @override
  State<LineSonicPidPage> createState() => _LineSonicPidPageState();
}

class _LineSonicPidPageState extends State<LineSonicPidPage> {
  static const _prefsStepsKey = 'linesonic_steps_v2';
  static const _prefsPresetsKey = 'linesonic_presets_v1';
  static const _presetCount = 10;

  final List<_StepData> _steps = [];
  final List<_PresetSlot> _presets = List.generate(
    _presetCount,
    (i) => _PresetSlot(name: 'Preset ${i + 1}', steps: []),
  );
  int _selectedPreset = 0;

  DateTime _lastSend = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastSeqSend = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastPdSend = DateTime.fromMillisecondsSinceEpoch(0);
  bool _sending = false;
  Timer? _autosaveTimer;
  int? _bleTrafficOwner;
  bool get _isThai => LanguageController.isThai.value;

  @override
  void initState() {
    super.initState();
    _bleTrafficOwner = BleManager.instance.claimTrafficMode(
      BleTrafficMode.textCommand,
      ownerName: 'linesonic_pid',
    );
    _initAsync();
  }

  Future<void> _initAsync() async {
    final prefs = await SharedPreferences.getInstance();
    _loadPresets(prefs);
    _loadSteps(prefs);
    if (_steps.isEmpty) {
      _steps.add(_newStep());
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    for (final s in _steps) {
      s.dispose();
    }
    final trafficOwner = _bleTrafficOwner;
    _bleTrafficOwner = null;
    if (trafficOwner != null) {
      BleManager.instance.releaseTrafficMode(trafficOwner);
    }
    super.dispose();
  }

  void _scheduleAutoSave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(
      const Duration(milliseconds: 400),
      _saveStepsToPrefs,
    );
  }

  void _onSpeedChanged() {
    setState(() {});
    _scheduleAutoSave();
  }

  Future<void> _saveStepsToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _steps.map((e) => e.toJson()).toList();
    await prefs.setString(_prefsStepsKey, jsonEncode(data));
  }

  void _loadSteps(SharedPreferences prefs) {
    final raw = prefs.getString(_prefsStepsKey);
    if (raw == null || raw.trim().isEmpty) return;
    final data = jsonDecode(raw);
    if (data is! List) return;
    for (final s in _steps) {
      s.dispose();
    }
    _steps.clear();
    var nextId = 1;
    for (final item in data) {
      if (item is! Map<String, dynamic>) continue;
      final modeRaw = (item['mode'] as String?) ?? '';
      final continueAfter = (item['continueAfter'] as bool?) ?? false;
      final parsedMode = modeRaw.toUpperCase() == 'CHECKSUM'
          ? _StepMode.checksum
          : (modeRaw.toUpperCase() == 'TIME' ? _StepMode.time : null);
      final collapsed = (item['collapsed'] as bool?) ?? false;
      final showOptions =
          (item['showOptions'] as bool?) ?? (parsedMode != null);
      _steps.add(
        _StepData(
          id: nextId++,
          mode: parsedMode,
          kp: (item['kp'] as String?) ?? '0',
          kd: (item['kd'] as String?) ?? '0',
          speed: (item['speed'] as String?) ?? '0',
          value: (item['value'] as String?) ?? '0',
          afterMs: (item['afterMs'] as String?) ?? '0',
          afterSpeed: (item['afterSpeed'] as String?) ?? '0',
          stopMs: (item['stopMs'] as String?) ?? '0',
          holdMs: (item['holdMs'] as String?) ?? '0',
          holdThreshold: (item['holdThreshold'] as String?) ?? '0',
          lineColor: (item['lineColor'] as int?) ?? 0,
          holdMode: (item['holdMode'] as int?) ?? 0,
          continueAfter: continueAfter,
          stopBetween: (item['stopBetween'] as bool?) ?? false,
          collapsed: collapsed,
          showOptions: showOptions,
        ),
      );
    }
  }

  Future<void> _savePresetsToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _presets.map((e) => e.toJson()).toList();
    await prefs.setString(_prefsPresetsKey, jsonEncode(data));
  }

  void _loadPresets(SharedPreferences prefs) {
    final raw = prefs.getString(_prefsPresetsKey);
    if (raw == null || raw.trim().isEmpty) return;
    final data = jsonDecode(raw);
    if (data is! List) return;
    for (var i = 0; i < _presetCount && i < data.length; i++) {
      final item = data[i];
      if (item is! Map<String, dynamic>) continue;
      _presets[i] = _PresetSlot.fromJson(item);
      if (_presets[i].name.trim().isEmpty) {
        _presets[i].name = 'Preset ${i + 1}';
      }
    }
  }

  _StepData _newStep({
    _StepMode? mode,
    String kp = '0',
    String kd = '0',
    String speed = '0',
    String value = '0',
    String afterMs = '0',
    String afterSpeed = '0',
    String stopMs = '0',
    String holdMs = '0',
    String holdThreshold = '0',
    int lineColor = 0,
    int holdMode = 0,
    bool continueAfter = false,
    bool stopBetween = false,
  }) {
    final nextId = _steps.isEmpty
        ? 1
        : _steps.map((e) => e.id).reduce((a, b) => a > b ? a : b) + 1;
    return _StepData(
      id: nextId,
      mode: mode,
      kp: kp,
      kd: kd,
      speed: speed,
      value: value,
      afterMs: afterMs,
      afterSpeed: afterSpeed,
      stopMs: stopMs,
      holdMs: holdMs,
      holdThreshold: holdThreshold,
      lineColor: lineColor,
      holdMode: holdMode,
      continueAfter: continueAfter,
      stopBetween: stopBetween,
      showOptions: mode != null,
    );
  }

  String _numOrZero(String raw) {
    final v = raw.trim();
    return v.isEmpty ? '0' : v;
  }

  Future<void> _sendCommand(String msg, {String? toast}) async {
    final now = DateTime.now();
    if (_sending ||
        now.difference(_lastSend) < const Duration(milliseconds: 200)) {
      return;
    }
    _sending = true;
    _lastSend = now;

    if (!BleManager.instance.isConnected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isThai
                ? '\u0e22\u0e31\u0e07\u0e44\u0e21\u0e48\u0e40\u0e0a\u0e37\u0e48\u0e2d\u0e21\u0e15\u0e48\u0e2d BLE'
                : 'BLE not connected',
          ),
        ),
      );
      _sending = false;
      return;
    }

    final owner = _bleTrafficOwner;
    if (owner == null) {
      _sending = false;
      return;
    }
    await BleManager.instance.send(msg, owner: owner);
    _sending = false;
    if (toast != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(toast)));
    }
  }

  String _buildSeqPayload() {
    final parts = <String>[];
    for (final s in _steps) {
      final mode = s.mode == _StepMode.checksum ? 'CHECKSUM' : 'TIME';
      final value = _numOrZero(s.valueCtrl.text);
      final kp = _numOrZero(s.kpCtrl.text);
      final kd = _numOrZero(s.kdCtrl.text);
      final speed = _numOrZero(s.speedCtrl.text);
      final afterMs = s.continueAfter ? _numOrZero(s.afterMsCtrl.text) : '0';
      final afterSpeed = s.continueAfter
          ? _numOrZero(s.afterSpeedCtrl.text)
          : '0';
      final stopMs = s.stopBetween ? _numOrZero(s.stopMsCtrl.text) : '0';
      final holdMs = s.holdMode == 0 ? '0' : _numOrZero(s.holdMsCtrl.text);
      final holdThreshold = s.holdMode == 0
          ? '0'
          : _numOrZero(s.holdThresholdCtrl.text);
      final holdMode = s.holdMode;
      final lineColor = s.lineColor;
      parts.add(
        '$mode,$value,$kp,$kd,$speed,$afterMs,$afterSpeed,$stopMs,$lineColor,$holdMs,$holdThreshold,$holdMode',
      );
    }
    return 'SEQ=${parts.join(';')}';
  }

  String _buildSeqPdPayload() {
    final parts = <String>[];
    for (final s in _steps) {
      final kp = _numOrZero(s.kpCtrl.text);
      final kd = _numOrZero(s.kdCtrl.text);
      final speed = _numOrZero(s.speedCtrl.text);
      parts.add('$kp,$kd,$speed');
    }
    return 'SEQPD=${parts.join(';')}';
  }

  Future<void> _sendSequence() async {
    final now = DateTime.now();
    if (now.difference(_lastSeqSend) < const Duration(seconds: 3)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isThai
                ? 'รอ 3 วินาทีแล้วค่อยส่งใหม่'
                : 'Please wait 3 seconds before sending again',
          ),
        ),
      );
      return;
    }

    if (_steps.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isThai ? 'ยังไม่มี Step ให้ส่ง' : 'No steps to send'),
        ),
      );
      return;
    }

    final payload = _buildSeqPayload();
    await _sendCommand(payload, toast: _isThai ? 'ส่งทั้งหมดแล้ว' : 'Sent all');
    _lastSeqSend = DateTime.now();
  }

  Future<void> _sendSequencePd() async {
    final now = DateTime.now();
    if (now.difference(_lastPdSend) < const Duration(seconds: 1)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isThai
                ? 'รอ 1 วินาทีแล้วค่อยส่งใหม่'
                : 'Please wait 1 second before sending again',
          ),
        ),
      );
      return;
    }

    if (_steps.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isThai ? 'ยังไม่มี Step ให้ส่ง' : 'No steps to send'),
        ),
      );
      return;
    }

    final payload = _buildSeqPdPayload();
    await _sendCommand(
      payload,
      toast: _isThai ? 'ส่ง PD+Speed แล้ว' : 'Sent PD+Speed',
    );
    _lastPdSend = DateTime.now();
  }

  Future<void> _sendSW1() async {
    await _sendCommand('SW1=1', toast: _isThai ? 'ส่ง SW1 แล้ว' : 'Sent SW1');
  }

  Future<void> _sendReset() async {
    await _sendCommand(
      'RESET=1',
      toast: _isThai ? 'ส่ง Reset แล้ว' : 'Sent Reset',
    );
  }

  void _duplicateStep(int index) {
    final s = _steps[index];
    setState(() {
      _steps.insert(
        index + 1,
        _newStep(
          mode: s.mode,
          kp: _numOrZero(s.kpCtrl.text),
          kd: _numOrZero(s.kdCtrl.text),
          speed: _numOrZero(s.speedCtrl.text),
          value: _numOrZero(s.valueCtrl.text),
          afterMs: _numOrZero(s.afterMsCtrl.text),
          afterSpeed: _numOrZero(s.afterSpeedCtrl.text),
          stopMs: _numOrZero(s.stopMsCtrl.text),
          holdMs: _numOrZero(s.holdMsCtrl.text),
          holdThreshold: _numOrZero(s.holdThresholdCtrl.text),
          lineColor: s.lineColor,
          holdMode: s.holdMode,
          continueAfter: s.continueAfter,
          stopBetween: s.stopBetween,
        ),
      );
      _scheduleAutoSave();
    });
  }

  void _deleteStep(int index) {
    setState(() {
      _steps[index].dispose();
      _steps.removeAt(index);
      _scheduleAutoSave();
    });
  }

  Future<void> _savePresetDialog() async {
    final isThai = _isThai;
    final controller = TextEditingController(
      text: _presets[_selectedPreset].name,
    );
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isThai ? 'บันทึกพรีเซ็ต' : 'Save Preset'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            label: Text(isThai ? 'ชื่อพรีเซ็ต' : 'Preset name'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isThai ? 'ยกเลิก' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(isThai ? 'บันทึก' : 'Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    final fallbackName = isThai
        ? 'รูปแบบที่ ${_selectedPreset + 1}'
        : 'Preset ${_selectedPreset + 1}';
    final newName = name.isEmpty ? fallbackName : name;
    setState(() {
      _presets[_selectedPreset] = _PresetSlot(
        name: newName,
        steps: _steps.map((e) => e.toJson()).toList(),
      );
    });
    await _savePresetsToPrefs();
  }

  void _loadPreset(int index) {
    final preset = _presets[index];
    if (preset.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isThai ? 'Preset นี้ยังว่างอยู่' : 'This preset is empty',
          ),
        ),
      );
      return;
    }
    setState(() {
      for (final s in _steps) {
        s.dispose();
      }
      _steps.clear();
      var nextId = 1;
      for (final item in preset.steps) {
        final modeRaw = (item['mode'] as String?) ?? '';
        final continueAfter = (item['continueAfter'] as bool?) ?? false;
        final parsedMode = modeRaw.toUpperCase() == 'CHECKSUM'
            ? _StepMode.checksum
            : (modeRaw.toUpperCase() == 'TIME' ? _StepMode.time : null);
        final collapsed = (item['collapsed'] as bool?) ?? false;
        final showOptions =
            (item['showOptions'] as bool?) ?? (parsedMode != null);
        _steps.add(
          _StepData(
            id: nextId++,
            mode: parsedMode,
            kp: (item['kp'] as String?) ?? '0',
            kd: (item['kd'] as String?) ?? '0',
            speed: (item['speed'] as String?) ?? '0',
            value: (item['value'] as String?) ?? '0',
            afterMs: (item['afterMs'] as String?) ?? '0',
            afterSpeed: (item['afterSpeed'] as String?) ?? '0',
            stopMs: (item['stopMs'] as String?) ?? '0',
            holdMs: (item['holdMs'] as String?) ?? '0',
            holdThreshold: (item['holdThreshold'] as String?) ?? '0',
            lineColor: (item['lineColor'] as int?) ?? 0,
            holdMode: (item['holdMode'] as int?) ?? 0,
            continueAfter: continueAfter,
            stopBetween: (item['stopBetween'] as bool?) ?? false,
            collapsed: collapsed,
            showOptions: showOptions,
          ),
        );
      }
      _scheduleAutoSave();
    });
  }

  Future<void> _deletePreset(int index) async {
    setState(() {
      _presets[index] = _PresetSlot(name: 'Preset ${index + 1}', steps: []);
    });
    await _savePresetsToPrefs();
  }

  void _showTutorial(BuildContext context) {
    final isThai = _isThai;
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(isThai ? 'วิธีใช้งาน' : 'Tutorial'),
          content: SingleChildScrollView(
            child: Text(
              isThai
                  ? '1) \u0e40\u0e1e\u0e34\u0e48\u0e21 Step \u0e14\u0e49\u0e27\u0e22\u0e1b\u0e38\u0e48\u0e21 +\n'
                        '2) \u0e01\u0e33\u0e2b\u0e19\u0e14 KP/KD/Speed \u0e41\u0e25\u0e30\u0e40\u0e25\u0e37\u0e2d\u0e01\u0e42\u0e2b\u0e21\u0e14\n'
                        '3) \u0e43\u0e2a\u0e48\u0e04\u0e48\u0e32 Time \u0e2b\u0e23\u0e37\u0e2d Target \u0e15\u0e32\u0e21\u0e40\u0e07\u0e37\u0e48\u0e2d\u0e19\u0e44\u0e02\n'
                        '4) (\u0e16\u0e49\u0e32\u0e15\u0e49\u0e2d\u0e07\u0e01\u0e32\u0e23) \u0e43\u0e2b\u0e49 PD \u0e27\u0e34\u0e48\u0e07\u0e15\u0e48\u0e2d\u0e2b\u0e25\u0e31\u0e07\u0e16\u0e36\u0e07\u0e40\u0e07\u0e37\u0e48\u0e2d\u0e19\u0e44\u0e02\n'
                        '5) \u0e01\u0e14 \u0e2a\u0e48\u0e07\u0e17\u0e31\u0e49\u0e07\u0e2b\u0e21\u0e14 \u0e40\u0e1e\u0e37\u0e48\u0e2d\u0e2a\u0e48\u0e07\u0e25\u0e33\u0e14\u0e31\u0e1a\u0e17\u0e31\u0e49\u0e07\u0e2b\u0e21\u0e14\n'
                        '6) \u0e01\u0e14 \u0e2a\u0e48\u0e07 PD+Speed \u0e40\u0e1e\u0e37\u0e48\u0e2d\u0e08\u0e39\u0e19\u0e23\u0e30\u0e2b\u0e27\u0e48\u0e32\u0e07\u0e27\u0e34\u0e48\u0e07\n'
                        '7) \u0e40\u0e25\u0e37\u0e2d\u0e01 \u0e40\u0e08\u0e2d\u0e14\u0e33/\u0e40\u0e08\u0e2d\u0e02\u0e32\u0e27 \u0e41\u0e25\u0e30\u0e15\u0e31\u0e49\u0e07\u0e04\u0e48\u0e32 SUM threshold\n'
                        '8) \u0e01\u0e33\u0e2b\u0e19\u0e14 Straight (ms) \u0e40\u0e1e\u0e37\u0e48\u0e2d\u0e27\u0e34\u0e48\u0e07\u0e15\u0e23\u0e07\u0e41\u0e17\u0e19 PD \u0e40\u0e21\u0e37\u0e48\u0e2d\u0e40\u0e08\u0e2d\u0e1e\u0e37\u0e49\u0e19\u0e17\u0e35\u0e48\u0e2a\u0e35\u0e40\u0e14\u0e35\u0e22\u0e27\n'
                        '9) \u0e01\u0e14 \u0e2a\u0e27\u0e34\u0e15\u0e0b\u0e4c SW1 \u0e40\u0e1e\u0e37\u0e48\u0e2d\u0e40\u0e23\u0e34\u0e48\u0e21 \u0e41\u0e25\u0e30 \u0e23\u0e35\u0e40\u0e0b\u0e47\u0e15\u0e1a\u0e2d\u0e23\u0e4c\u0e14'
                  : '1) Add steps with +\n'
                        '2) Set KP/KD/Speed and Mode\n'
                        '3) Use Target/Time value for the condition\n'
                        '4) (Optional) Continue PD after condition\n'
                        '5) Send All to update full sequence\n'
                        '6) Send PD+Speed to tune while running\n'
                        '7) Choose All Black/All White and set SUM threshold\n'
                        '8) Set Straight (ms) to drive straight instead of PD\n'
                        '9) Use SW1 to start, Reset to reboot board',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(isThai ? 'ปิด' : 'Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openPresetPicker() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: _presetCount,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final title = _presets[i].isEmpty
                  ? '${_presets[i].name} (empty)'
                  : _presets[i].name;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(title, overflow: TextOverflow.ellipsis),
                leading: i == _selectedPreset
                    ? const Icon(Icons.check_circle, size: 18)
                    : const SizedBox(width: 18),
                trailing: _presets[i].isEmpty
                    ? null
                    : TextButton(
                        onPressed: () async {
                          await _deletePreset(i);
                          if (ctx.mounted) Navigator.pop(ctx, _selectedPreset);
                        },
                        child: const Text('Delete'),
                      ),
                onTap: () => Navigator.pop(ctx, i),
              );
            },
          ),
        );
      },
    );

    if (selected == null) return;
    setState(() => _selectedPreset = selected);
  }

  Widget _buildPlainBackButton(bool isThai) {
    final metrics = AdaptivePageMetrics.forWidth(
      MediaQuery.of(context).size.width,
    );
    return SizedBox(
      width: metrics.backButtonSize,
      height: metrics.backButtonSize,
      child: IconButton(
        tooltip: isThai ? 'กลับ' : 'Back',
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

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final metrics = AdaptivePageMetrics.forWidth(
      MediaQuery.of(context).size.width,
    );
    final isCompact = MediaQuery.of(context).size.width < 380;
    final sendBg = isDark ? const Color(0xFF38BDF8) : const Color(0xFF2563EB);
    final sendFg = isDark ? const Color(0xFF0B1020) : Colors.white;
    final sw1Fg = isDark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E);
    final resetFg = isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C);
    final pdBg = isDark ? const Color(0xFF22C55E) : const Color(0xFF16A34A);
    final pdFg = isDark ? const Color(0xFF0B1020) : Colors.white;

    return ValueListenableBuilder<bool>(
      valueListenable: LanguageController.isThai,
      builder: (context, isThai, _) {
        final scheme = Theme.of(context).colorScheme;
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
              'PID Tuning',
              style: TextStyle(
                fontSize: metrics.titleSize,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
                color: scheme.onSurface,
              ),
            ),
            actions: [
              IconButton(
                tooltip: isThai ? 'วิธีใช้งาน' : 'Tutorial',
                onPressed: () => _showTutorial(context),
                icon: const Icon(Icons.help_outline),
                iconSize: 20,
              ),
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: ConnectionStatusBadge(),
              ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: metrics.contentMaxWidth),
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isThai ? 'ลำดับภารกิจ' : 'Mission Timeline',
                            style: t.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: _openPresetPicker,
                                  borderRadius: BorderRadius.circular(8),
                                  child: InputDecorator(
                                    decoration: InputDecoration(
                                      label: Text(
                                        isThai ? 'ค่าที่ตั้งไว้' : 'Preset',
                                      ),
                                      border: const OutlineInputBorder(),
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 6,
                                          ),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            _presets[_selectedPreset].isEmpty
                                                ? '${_presets[_selectedPreset].name} (${isThai ? 'ว่าง' : 'empty'})'
                                                : _presets[_selectedPreset]
                                                      .name,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const Icon(Icons.arrow_drop_down),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.filledTonal(
                                tooltip: isThai
                                    ? 'บันทึกพรีเซ็ต'
                                    : 'Save preset',
                                onPressed: _savePresetDialog,
                                icon: const Icon(Icons.save_outlined),
                                visualDensity: const VisualDensity(
                                  horizontal: -2,
                                  vertical: -2,
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton.outlined(
                                tooltip: isThai ? 'โหลดพรีเซ็ต' : 'Load preset',
                                onPressed: () => _loadPreset(_selectedPreset),
                                icon: const Icon(Icons.download_outlined),
                                visualDensity: const VisualDensity(
                                  horizontal: -2,
                                  vertical: -2,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverReorderableList(
                    itemCount: _steps.length,
                    onReorderItem: (oldIndex, newIndex) {
                      setState(() {
                        final item = _steps.removeAt(oldIndex);
                        _steps.insert(newIndex, item);
                        _scheduleAutoSave();
                      });
                    },
                    itemBuilder: (context, index) {
                      final step = _steps[index];
                      final hasMode = step.mode != null;
                      final isTime = step.mode == _StepMode.time;
                      final isCollapsed = step.collapsed;
                      final modeLabel = hasMode
                          ? (isTime
                                ? (isThai ? 'เวลา' : 'Time')
                                : (isThai ? 'เช็กผลรวม' : 'CheckSum'))
                          : '';
                      final tone = hasMode
                          ? (isTime
                                ? const Color(0xFF3B82F6)
                                : const Color(0xFFF59E0B))
                          : (isDark
                                ? const Color(0xFF4B5563)
                                : const Color(0xFF94A3B8));
                      final toneBg = hasMode
                          ? (isTime
                                ? (isDark
                                      ? const Color(0xFF0B1D3A)
                                      : const Color(0xFFEFF6FF))
                                : (isDark
                                      ? const Color(0xFF3A2500)
                                      : const Color(0xFFFFF7ED)))
                          : (isDark
                                ? const Color(0xFF111827)
                                : const Color(0xFFF1F5F9));

                      return Material(
                        key: ValueKey(step.id),
                        color: toneBg,
                        elevation: 0,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: tone.withValues(
                                alpha: isDark ? 0.5 : 0.35,
                              ),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                InkWell(
                                  onTap: () {
                                    setState(() {
                                      step.collapsed = !step.collapsed;
                                      _scheduleAutoSave();
                                    });
                                  },
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: tone,
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                              child: Text(
                                                '${isThai ? 'ขั้นตอน' : 'Step'} ${index + 1}${modeLabel.isEmpty ? '' : ' ($modeLabel)'}',
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Icon(
                                              isCollapsed
                                                  ? Icons.expand_more
                                                  : Icons.expand_less,
                                              size: 18,
                                              color: tone,
                                            ),
                                          ],
                                        ),
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            tooltip: isThai
                                                ? 'ทำซ้ำ'
                                                : 'Duplicate',
                                            onPressed: () =>
                                                _duplicateStep(index),
                                            icon: const Icon(
                                              Icons.copy_all_outlined,
                                            ),
                                            iconSize: 18,
                                            visualDensity: const VisualDensity(
                                              horizontal: -2,
                                              vertical: -2,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: isThai ? 'ลบ' : 'Delete',
                                            onPressed: () => _deleteStep(index),
                                            icon: const Icon(
                                              Icons.delete_outline,
                                            ),
                                            iconSize: 18,
                                            visualDensity: const VisualDensity(
                                              horizontal: -2,
                                              vertical: -2,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: isThai
                                                ? 'เลื่อนขึ้น'
                                                : 'Move up',
                                            onPressed: index == 0
                                                ? null
                                                : () {
                                                    setState(() {
                                                      final item = _steps
                                                          .removeAt(index);
                                                      _steps.insert(
                                                        index - 1,
                                                        item,
                                                      );
                                                      _scheduleAutoSave();
                                                    });
                                                  },
                                            icon: const Icon(
                                              Icons.keyboard_arrow_up,
                                            ),
                                            iconSize: 20,
                                            visualDensity: const VisualDensity(
                                              horizontal: -2,
                                              vertical: -2,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: isThai
                                                ? 'เลื่อนลง'
                                                : 'Move down',
                                            onPressed:
                                                index == _steps.length - 1
                                                ? null
                                                : () {
                                                    setState(() {
                                                      final item = _steps
                                                          .removeAt(index);
                                                      _steps.insert(
                                                        index + 1,
                                                        item,
                                                      );
                                                      _scheduleAutoSave();
                                                    });
                                                  },
                                            icon: const Icon(
                                              Icons.keyboard_arrow_down,
                                            ),
                                            iconSize: 20,
                                            visualDensity: const VisualDensity(
                                              horizontal: -2,
                                              vertical: -2,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  children: [
                                    if (isCollapsed) ...[
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _ValuePill(
                                              label: 'KP',
                                              value: _numOrZero(
                                                step.kpCtrl.text,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: _ValuePill(
                                              label: 'KD',
                                              value: _numOrZero(
                                                step.kdCtrl.text,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: _ValuePill(
                                              label: isThai
                                                  ? 'ความเร็ว'
                                                  : 'Speed',
                                              value: _numOrZero(
                                                step.speedCtrl.text,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    if (!isCollapsed) ...[
                                      const SizedBox(height: 8),
                                      if (isCompact) ...[
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _NumberField(
                                                label: 'KP',
                                                controller: step.kpCtrl,
                                                onChanged: _scheduleAutoSave,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: _NumberField(
                                                label: 'KD',
                                                controller: step.kdCtrl,
                                                onChanged: _scheduleAutoSave,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        _NumberField(
                                          label: isThai ? 'ความเร็ว' : 'Speed',
                                          controller: step.speedCtrl,
                                          onChanged: _onSpeedChanged,
                                        ),
                                        const SizedBox(height: 8),
                                        _PresetChips(
                                          values: const [
                                            '0',
                                            '10',
                                            '20',
                                            '30',
                                            '40',
                                            '50',
                                            '60',
                                            '70',
                                            '80',
                                            '90',
                                            '100',
                                          ],
                                          controller: step.speedCtrl,
                                          onChanged: _onSpeedChanged,
                                        ),
                                      ] else ...[
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _NumberField(
                                                label: 'KP',
                                                controller: step.kpCtrl,
                                                onChanged: _scheduleAutoSave,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: _NumberField(
                                                label: 'KD',
                                                controller: step.kdCtrl,
                                                onChanged: _scheduleAutoSave,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: _NumberField(
                                                label: isThai
                                                    ? 'ความเร็ว'
                                                    : 'Speed',
                                                controller: step.speedCtrl,
                                                onChanged: _onSpeedChanged,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        _PresetChips(
                                          values: const [
                                            '0',
                                            '10',
                                            '20',
                                            '30',
                                            '40',
                                            '50',
                                            '60',
                                            '70',
                                            '80',
                                            '90',
                                            '100',
                                          ],
                                          controller: step.speedCtrl,
                                          onChanged: _onSpeedChanged,
                                        ),
                                      ],
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Text(
                                            isThai ? 'สีเส้น' : 'Line color',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: SegmentedButton<int>(
                                              segments: [
                                                ButtonSegment(
                                                  value: 0,
                                                  label: Text(
                                                    isThai ? 'ดำ' : 'Black',
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                ),
                                                ButtonSegment(
                                                  value: 1,
                                                  label: Text(
                                                    isThai ? 'ขาว' : 'White',
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                              selected: <int>{step.lineColor},
                                              style: const ButtonStyle(
                                                visualDensity: VisualDensity(
                                                  horizontal: -2,
                                                  vertical: -2,
                                                ),
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                                padding: WidgetStatePropertyAll(
                                                  EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 6,
                                                  ),
                                                ),
                                              ),
                                              onSelectionChanged: (s) {
                                                if (s.isEmpty) return;
                                                setState(() {
                                                  step.lineColor = s.first;
                                                  _scheduleAutoSave();
                                                });
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Text(
                                            isThai ? 'โหมด' : 'Mode',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: SegmentedButton<_StepMode>(
                                              segments: [
                                                ButtonSegment(
                                                  value: _StepMode.time,
                                                  label: Text(
                                                    isThai ? 'เวลา' : 'Time',
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                ),
                                                ButtonSegment(
                                                  value: _StepMode.checksum,
                                                  label: Text(
                                                    isThai
                                                        ? 'เช็กผลรวม'
                                                        : 'CheckSum',
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                              emptySelectionAllowed: true,
                                              selected: step.mode == null
                                                  ? const <_StepMode>{}
                                                  : <_StepMode>{step.mode!},
                                              style: const ButtonStyle(
                                                visualDensity: VisualDensity(
                                                  horizontal: -2,
                                                  vertical: -2,
                                                ),
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                                padding: WidgetStatePropertyAll(
                                                  EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 6,
                                                  ),
                                                ),
                                              ),
                                              onSelectionChanged: (s) {
                                                setState(() {
                                                  if (s.isEmpty) {
                                                    // Toggle options visibility without clearing mode
                                                    step.showOptions =
                                                        !step.showOptions;
                                                  } else {
                                                    final nextMode = s.first;
                                                    if (step.mode != nextMode) {
                                                      step.mode = nextMode;
                                                      step.valueCtrl.text = '0';
                                                    }
                                                    step.showOptions = true;
                                                  }
                                                  _scheduleAutoSave();
                                                });
                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Icon(
                                            step.showOptions
                                                ? Icons.expand_less
                                                : Icons.expand_more,
                                            size: 16,
                                            color: tone,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      if (step.mode != null &&
                                          step.showOptions) ...[
                                        _NumberField(
                                          label: isTime
                                              ? (isThai
                                                    ? '\u0e21\u0e34\u0e25\u0e25\u0e34\u0e27\u0e34\u0e19\u0e32\u0e17\u0e35 (ms)'
                                                    : 'Milliseconds (ms)')
                                              : (isThai
                                                    ? '\u0e08\u0e33\u0e19\u0e27\u0e19\u0e40\u0e2a\u0e49\u0e19 / \u0e04\u0e48\u0e32\u0e40\u0e1b\u0e49\u0e32\u0e2b\u0e21\u0e32\u0e22'
                                                    : 'Line Count / Target'),
                                          controller: step.valueCtrl,
                                          onChanged: _scheduleAutoSave,
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: SegmentedButton<int>(
                                                segments: [
                                                  ButtonSegment(
                                                    value: 0,
                                                    label: Text(
                                                      isThai ? 'ปิด' : 'Off',
                                                      style: const TextStyle(
                                                        fontSize: 10,
                                                      ),
                                                    ),
                                                  ),
                                                  ButtonSegment(
                                                    value: 1,
                                                    label: Text(
                                                      isThai
                                                          ? 'เจอดำ'
                                                          : 'All Black',
                                                      style: const TextStyle(
                                                        fontSize: 10,
                                                      ),
                                                    ),
                                                  ),
                                                  ButtonSegment(
                                                    value: 2,
                                                    label: Text(
                                                      isThai
                                                          ? 'เจอขาว'
                                                          : 'All White',
                                                      style: const TextStyle(
                                                        fontSize: 10,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                                selected: <int>{step.holdMode},
                                                style: const ButtonStyle(
                                                  visualDensity: VisualDensity(
                                                    horizontal: -2,
                                                    vertical: -2,
                                                  ),
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                  padding:
                                                      WidgetStatePropertyAll(
                                                        EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 6,
                                                        ),
                                                      ),
                                                ),
                                                onSelectionChanged: (s) {
                                                  if (s.isEmpty) return;
                                                  setState(() {
                                                    step.holdMode = s.first;
                                                    _scheduleAutoSave();
                                                  });
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        IgnorePointer(
                                          ignoring: step.holdMode == 0,
                                          child: Opacity(
                                            opacity: step.holdMode == 0
                                                ? 0.4
                                                : 1.0,
                                            child: Column(
                                              children: [
                                                _NumberField(
                                                  label: isThai
                                                      ? '\u0e40\u0e14\u0e34\u0e19\u0e15\u0e23\u0e07 (ms)'
                                                      : 'Straight (ms)',
                                                  controller: step.holdMsCtrl,
                                                  onChanged: _scheduleAutoSave,
                                                ),
                                                const SizedBox(height: 6),
                                                _NumberField(
                                                  label: isThai
                                                      ? '\u0e04\u0e48\u0e32\u0e40\u0e01\u0e13\u0e11\u0e4c SUM'
                                                      : 'SUM threshold',
                                                  controller:
                                                      step.holdThresholdCtrl,
                                                  onChanged: _scheduleAutoSave,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Transform.scale(
                                              scale: 0.65,
                                              child: Switch(
                                                value: step.continueAfter,
                                                onChanged: (v) {
                                                  setState(() {
                                                    step.continueAfter = v;
                                                    _scheduleAutoSave();
                                                  });
                                                },
                                                materialTapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                isThai
                                                    ? '\u0e27\u0e34\u0e48\u0e07\u0e15\u0e48\u0e2d\u0e2b\u0e25\u0e31\u0e07\u0e16\u0e36\u0e07\u0e40\u0e07\u0e37\u0e48\u0e2d\u0e19\u0e44\u0e02'
                                                    : 'Continue PD after condition',
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodySmall,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        IgnorePointer(
                                          ignoring: !step.continueAfter,
                                          child: Opacity(
                                            opacity: step.continueAfter
                                                ? 1.0
                                                : 0.4,
                                            child: Column(
                                              children: [
                                                _NumberField(
                                                  label: isThai
                                                      ? '\u0e27\u0e34\u0e48\u0e07\u0e15\u0e48\u0e2d (ms)'
                                                      : 'Continue (ms)',
                                                  controller: step.afterMsCtrl,
                                                  onChanged: _scheduleAutoSave,
                                                ),
                                                const SizedBox(height: 6),
                                                _NumberField(
                                                  label: isThai
                                                      ? '\u0e04\u0e27\u0e32\u0e21\u0e40\u0e23\u0e47\u0e27\u0e15\u0e48\u0e2d'
                                                      : 'Continue Speed',
                                                  controller:
                                                      step.afterSpeedCtrl,
                                                  onChanged: _scheduleAutoSave,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Transform.scale(
                                              scale: 0.65,
                                              child: Switch(
                                                value: step.stopBetween,
                                                onChanged: (v) {
                                                  setState(() {
                                                    step.stopBetween = v;
                                                    _scheduleAutoSave();
                                                  });
                                                },
                                                materialTapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                isThai
                                                    ? '\u0e2b\u0e22\u0e38\u0e14\u0e01\u0e48\u0e2d\u0e19 Step \u0e16\u0e31\u0e14\u0e44\u0e1b'
                                                    : 'Stop before next step',
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodySmall,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        IgnorePointer(
                                          ignoring: !step.stopBetween,
                                          child: Opacity(
                                            opacity: step.stopBetween
                                                ? 1.0
                                                : 0.4,
                                            child: _NumberField(
                                              label: isThai
                                                  ? '\u0e2b\u0e22\u0e38\u0e14 (ms)'
                                                  : 'Stop (ms)',
                                              controller: step.stopMsCtrl,
                                              onChanged: _scheduleAutoSave,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 48,
                                  child: ElevatedButton.icon(
                                    onPressed: _sending ? null : _sendSequence,
                                    icon: const Icon(Icons.send),
                                    label: Text(
                                      isThai
                                          ? '\u0e2a\u0e48\u0e07\u0e17\u0e31\u0e49\u0e07\u0e2b\u0e21\u0e14'
                                          : 'Send All',
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: sendBg,
                                      foregroundColor: sendFg,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 44,
                                  child: FilledButton.tonalIcon(
                                    onPressed: _sending
                                        ? null
                                        : _sendSequencePd,
                                    icon: const Icon(Icons.tune),
                                    label: Text(
                                      isThai
                                          ? '\u0e2a\u0e48\u0e07 PD+Speed'
                                          : 'Send PD+Speed',
                                    ),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: pdBg,
                                      foregroundColor: pdFg,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 40,
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: sw1Fg,
                                      side: BorderSide(color: sw1Fg),
                                    ),
                                    onPressed: _sending ? null : _sendSW1,
                                    icon: const Icon(Icons.touch_app, size: 18),
                                    label: Text(
                                      isThai
                                          ? '\u0e2a\u0e27\u0e34\u0e15\u0e0b\u0e4c SW1'
                                          : 'SW1',
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: SizedBox(
                                  height: 40,
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: resetFg,
                                      side: BorderSide(color: resetFg),
                                    ),
                                    onPressed: _sending ? null : _sendReset,
                                    icon: const Icon(
                                      Icons.power_settings_new,
                                      size: 18,
                                    ),
                                    label: Text(
                                      isThai
                                          ? '\u0e23\u0e35\u0e40\u0e0b\u0e47\u0e15\u0e1a\u0e2d\u0e23\u0e4c\u0e14'
                                          : 'Reset Board',
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
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'add_step_linesonic_pid',
            onPressed: () {
              setState(() {
                _steps.add(_newStep());
                _scheduleAutoSave();
              });
            },
            icon: const Icon(Icons.add),
            label: Text(isThai ? 'เพิ่ม Step' : 'Add Step'),
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        );
      },
    );
  }
}

class _NumberField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;

  const _NumberField({
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onTap: () {
        controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: controller.text.length,
        );
      },
      onChanged: (_) => onChanged(),
      onEditingComplete: () {
        if (controller.text.trim().isEmpty) {
          controller.text = '0';
        }
        FocusScope.of(context).unfocus();
        onChanged();
      },
      decoration: InputDecoration(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
    );
  }
}

class _ValuePill extends StatelessWidget {
  final String label;
  final String value;

  const _ValuePill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.15,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Text(
            '$label ',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetChips extends StatelessWidget {
  final List<String> values;
  final TextEditingController controller;
  final VoidCallback onChanged;

  const _PresetChips({
    required this.values,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final current = controller.text.trim();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: values.map((v) {
        final selected = current == v;
        return ChoiceChip(
          label: Text(v, style: const TextStyle(fontSize: 10)),
          selected: selected,
          showCheckmark: false,
          selectedColor: Theme.of(
            context,
          ).colorScheme.primary.withValues(alpha: 0.2),
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onSelected: (_) {
            controller.text = v;
            onChanged();
          },
        );
      }).toList(),
    );
  }
}
