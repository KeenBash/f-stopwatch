import 'package:flutter/material.dart';

import '../../format.dart';
import '../../hotkeys.dart';
import '../../stopwatch_model.dart';

/// Windows 端根应用。
class WindowsStopwatchApp extends StatelessWidget {
  const WindowsStopwatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'F-Stopwatch',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.blueGrey,
        useMaterial3: true,
      ),
      home: const WindowsStopwatchScreen(),
    );
  }
}

/// Windows 主窗口：大号总时间 + 打点列表 + 全局热键设置。
class WindowsStopwatchScreen extends StatefulWidget {
  const WindowsStopwatchScreen({super.key});

  @override
  State<WindowsStopwatchScreen> createState() => _WindowsStopwatchScreenState();
}

class _WindowsStopwatchScreenState extends State<WindowsStopwatchScreen> {
  final StopwatchModel _model = StopwatchModel();
  final HotkeySettings _hotkeys = HotkeySettings();

  bool _showSettings = false;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    await _hotkeys.load();
    await _applyHotkeys();
    if (mounted) setState(() {});
  }

  Future<void> _applyHotkeys() {
    return StopwatchHotkeys.instance.apply(
      _hotkeys,
      onToggle: _model.toggle,
      onLap: _model.lap,
    );
  }

  Future<void> _changeToggleKey(KeyOption key) async {
    _hotkeys.toggleKey = key;
    await _saveAndReapply();
  }

  Future<void> _changeToggleMod(ModifierOption mod) async {
    _hotkeys.toggleModifier = mod;
    await _saveAndReapply();
  }

  Future<void> _changeLapKey(KeyOption key) async {
    _hotkeys.lapKey = key;
    await _saveAndReapply();
  }

  Future<void> _changeLapMod(ModifierOption mod) async {
    _hotkeys.lapModifier = mod;
    await _saveAndReapply();
  }

  Future<void> _saveAndReapply() async {
    await _hotkeys.save();
    await _applyHotkeys();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    StopwatchHotkeys.instance.unregisterAll();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: <Widget>[
                _header(context),
                const SizedBox(height: 12),
                Expanded(child: _buildContent(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        const Text('F-Stopwatch',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        TextButton.icon(
          onPressed: () => setState(() => _showSettings = !_showSettings),
          icon: const Icon(Icons.settings, size: 18),
          label: Text(_showSettings ? '收起设置' : '热键设置'),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_showSettings) {
      return _settingsPanel(context);
    }
    return AnimatedBuilder(
      animation: _model,
      builder: (context, _) => Column(
        children: <Widget>[
          Text(
            formatDuration(_model.elapsed),
            style: const TextStyle(
              fontSize: 72,
              fontWeight: FontWeight.w300,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '本次 ${formatDuration(_model.lapDelta)}',
            style: TextStyle(
                fontSize: 16, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 20),
          _controls(context),
          const SizedBox(height: 20),
          Expanded(child: _lapList()),
        ],
      ),
    );
  }

  Widget _controls(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        FilledButton.tonalIcon(
          onPressed: _model.toggle,
          icon: Icon(_model.isPaused ? Icons.play_arrow : Icons.pause),
          label: Text(_model.isPaused ? '开始' : '暂停'),
          style: FilledButton.styleFrom(
              minimumSize: const Size(120, 48), textStyle: const TextStyle(fontSize: 18)),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: _model.lap,
          icon: const Icon(Icons.flag),
          label: const Text('计次+1'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(120, 48)),
        ),
        const SizedBox(width: 12),
        OutlinedButton(
          onPressed: _model.reset,
          child: const Text('重置'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(72, 48)),
        ),
      ],
    );
  }

  Widget _lapList() {
    final laps = _model.laps;
    if (laps.isEmpty) {
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 32),
          child: Text('尚无打点记录\n按 “计次+1” 或热键记录',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, height: 1.6)),
        ),
      );
    }
    return ListView.builder(
      itemCount: laps.length,
      itemBuilder: (context, i) {
        final cumulative = laps[i];
        final delta = durationDiff(cumulative, i == 0 ? Duration.zero : laps[i - 1]);
        return ListTile(
          dense: true,
          leading: Text('#${i + 1}',
              style: TextStyle(color: Colors.grey.shade500)),
          title: Text('本次 ${formatDuration(delta)}',
              style: const TextStyle(fontFeatures: <FontFeature>[FontFeature.tabularFigures()])),
          trailing: Text('累计 ${formatDuration(cumulative)}',
              style: TextStyle(color: Colors.grey.shade300,
                  fontFeatures: const <FontFeature>[FontFeature.tabularFigures()])),
        );
      },
    );
  }

  Widget _settingsPanel(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('全局热键（应用不在前台也可用）',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _settingRow('暂停/开始', _hotkeys.toggleDesc, _hotkeys.toggleKey, _hotkeys.toggleModifier,
              _changeToggleKey, _changeToggleMod),
          const SizedBox(height: 12),
          _settingRow('计次+1', _hotkeys.lapDesc, _hotkeys.lapKey, _hotkeys.lapModifier,
              _changeLapKey, _changeLapMod),
        ],
      ),
    );
  }

  Widget _settingRow(
    String label,
    String desc,
    KeyOption key,
    ModifierOption modifier,
    void Function(KeyOption) onKey,
    void Function(ModifierOption) onMod,
  ) {
    return Row(
      children: <Widget>[
        SizedBox(width: 90, child: Text(label)),
        DropdownButton<ModifierOption>(
          value: modifier,
          items: <DropdownMenuItem<ModifierOption>>[
            for (final m in modifierChoices)
              DropdownMenuItem<ModifierOption>(
                  value: m, child: Text(m.label)),
          ],
          onChanged: (v) => v == null ? null : onMod(v),
        ),
        const SizedBox(width: 8),
        DropdownButton<KeyOption>(
          value: key,
          items: <DropdownMenuItem<KeyOption>>[
            for (final k in keyChoices)
              DropdownMenuItem<KeyOption>(value: k, child: Text(k.label)),
          ],
          onChanged: (v) => v == null ? null : onKey(v),
        ),
        const SizedBox(width: 16),
        Text('当前: $desc', style: TextStyle(color: Colors.grey.shade500)),
      ],
    );
  }
}