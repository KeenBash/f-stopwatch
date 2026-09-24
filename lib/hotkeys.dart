import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PhysicalKeyboardKey;
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 可被选中的按键。
class KeyOption {
  final String label;
  final PhysicalKeyboardKey key;
  const KeyOption(this.label, this.key);
}

/// 可被选中的修饰键（null 表示无修饰）。
class ModifierOption {
  final String label;
  final HotKeyModifier? modifier;
  const ModifierOption(this.label, this.modifier);
}

/// 常用可选按键列表。
const List<KeyOption> keyChoices = <KeyOption>[
  KeyOption('F2', PhysicalKeyboardKey.f2),
  KeyOption('F3', PhysicalKeyboardKey.f3),
  KeyOption('F4', PhysicalKeyboardKey.f4),
  KeyOption('F5', PhysicalKeyboardKey.f5),
  KeyOption('F6', PhysicalKeyboardKey.f6),
  KeyOption('F7', PhysicalKeyboardKey.f7),
  KeyOption('Space', PhysicalKeyboardKey.space),
  KeyOption('Enter', PhysicalKeyboardKey.enter),
];

/// 常用可选修饰键列表（含“无”）。
const List<ModifierOption> modifierChoices = <ModifierOption>[
  ModifierOption('无', null),
  ModifierOption('Ctrl', HotKeyModifier.control),
  ModifierOption('Shift', HotKeyModifier.shift),
  ModifierOption('Alt', HotKeyModifier.alt),
];

/// 全局热键偏好设置（持久化）。
class HotkeySettings extends ChangeNotifier {
  static const _prefsKey = 'hotkey_config_v1';

  KeyOption toggleKey = keyChoices[0]; // F2
  ModifierOption toggleModifier = modifierChoices[0];
  KeyOption lapKey = keyChoices[1]; // F3
  ModifierOption lapModifier = modifierChoices[0];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    final parts = raw.split('|');
    try {
      if (parts.length >= 4) {
        toggleKey = _keyFor(parts[0]) ?? toggleKey;
        toggleModifier = _modFor(parts[1]) ?? toggleModifier;
        lapKey = _keyFor(parts[2]) ?? lapKey;
        lapModifier = _modFor(parts[3]) ?? lapModifier;
        notifyListeners();
      }
    } catch (_) {/* 配置损坏时回落默认 */}
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, <String>[
      toggleKey.label,
      toggleModifier.label,
      lapKey.label,
      lapModifier.label,
    ].join('|'));
    notifyListeners();
  }

  static KeyOption? _keyFor(String label) {
    for (final k in keyChoices) {
      if (k.label == label) return k;
    }
    return null;
  }

  static ModifierOption? _modFor(String label) {
    for (final m in modifierChoices) {
      if (m.label == label) return m;
    }
    return null;
  }

  /// 根据当前偏好构造两个 [HotKey]。
  List<HotKey> buildHotKeys() => <HotKey>[
        HotKey(
          key: toggleKey.key,
          modifiers: toggleModifier.modifier == null
              ? null
              : <HotKeyModifier>[toggleModifier.modifier!],
          scope: HotKeyScope.system,
        ),
        HotKey(
          key: lapKey.key,
          modifiers: lapModifier.modifier == null
              ? null
              : <HotKeyModifier>[lapModifier.modifier!],
          scope: HotKeyScope.system,
        ),
      ];

  /** 显示当前配置文本 */
  String get toggleDesc =>
      '${toggleModifier.label == "无" ? "" : toggleModifier.label + "+"}${toggleKey.label}';
  String get lapDesc =>
      '${lapModifier.label == "无" ? "" : lapModifier.label + "+"}${lapKey.label}';
}

/// 注册并管理全局热键。
class StopwatchHotkeys {
  StopwatchHotkeys._();

  static final StopwatchHotkeys instance = StopwatchHotkeys._();

  /// 注销旧热键并按其偏好重新注册。回调把事件转发给计时模型。
  Future<void> apply(
    HotkeySettings settings, {
    required VoidCallback onToggle,
    required VoidCallback onLap,
  }) async {
    final hotKeys = settings.buildHotKeys();
    try {
      await hotKeyManager.unregisterAll();
    } catch (_) {/* 注销失败不阻塞 */}
    await hotKeyManager.register(
      hotKeys[0],
      keyDownHandler: (_) => onToggle(),
    );
    await hotKeyManager.register(
      hotKeys[1],
      keyDownHandler: (_) => onLap(),
    );
  }

  Future<void> unregisterAll() => hotKeyManager.unregisterAll();
}