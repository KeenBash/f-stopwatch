import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../format.dart';
import '../../overlay_bridge.dart';
import '../../stopwatch_model.dart';

/// Android 端根应用。
class AndroidStopwatchApp extends StatelessWidget {
  const AndroidStopwatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'F-Stopwatch',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      home: const AndroidStopwatchScreen(),
    );
  }
}

/// Android 主界面：显示总时间与打点，并提供悬浮窗的授权与启停控制。
class AndroidStopwatchScreen extends StatefulWidget {
  const AndroidStopwatchScreen({super.key});

  @override
  State<AndroidStopwatchScreen> createState() => _AndroidStopwatchScreenState();
}

class _AndroidStopwatchScreenState extends State<AndroidStopwatchScreen>
    with WidgetsBindingObserver {
  final StopwatchModel _model = StopwatchModel();

  StreamSubscription<String>? _buttonSub;
  bool _overlayPermission = false;
  bool _overlayActive = false;

  // 悬浮窗配置
  int _fontColor = 0xFFFFFFFF;
  double _sizeScale = 1.0;
  int _bgAlpha = 200;
  // 显示模式：0=总时间(总时间+本次小字) 1=单次(只显示本次/当前轮计时)
  int _overlayMode = 0;
  bool _vibrate = false;
  int _lastLapCount = -1;
  Timer? _styleDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _model.addListener(_syncOverlay);
    _listenOverlayButtons();
    _refreshPermission();
    _loadConfig();
  }

  @override
  void dispose() {
    _styleDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _model.removeListener(_syncOverlay);
    _buttonSub?.cancel();
    _model.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPermission();
      _refreshOverlayActive();
    }
  }

  Future<void> _refreshPermission() async {
    final ok = await OverlayBridge.hasOverlayPermission();
    if (mounted) setState(() => _overlayPermission = ok);
  }

  /// 回到前台时核对原生悬浮窗是否真实在运行，修正主界面开关状态。
  Future<void> _refreshOverlayActive() async {
    final active = await OverlayBridge.isOverlayActive();
    if (mounted && active != _overlayActive) {
      setState(() => _overlayActive = active);
      if (active) {
        _lastLapCount = -1; // 原生重激活后强制重新推送计次列表
        _syncOverlay();
      }
    }
  }

  void _listenOverlayButtons() {
    _buttonSub = OverlayBridge.onButtonPressed().listen((action) {
      // 自愈：即使 Dart 侧临时认为悬浮窗未激活，按钮响应也要强制同步状态并推送，
      // 解决"回到主页才有反应"的周期问题（避免依赖过期的 _overlayActive 判断）。
      if (!_overlayActive) {
        _overlayActive = true;
        if (mounted) setState(() {});
      }
      // 振动由原生侧(OverlayService.vibrateClick)负责，更稳定(部分ROM不依赖窗口焦点)
      switch (action) {
        case 'toggle':
          _model.toggle();
          break;
        case 'lap':
          _model.lap();
          break;
        case 'reset':
          _model.reset();
          break;
        case 'stop':
          _overlayActive = false;
          if (mounted) setState(() {});
          _stopOverlay();
          break;
      }
      _syncOverlay();
    });
  }

  Future<void> _loadConfig() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _fontColor = p.getInt('ov_font_color') ?? 0xFFFFFFFF;
      _sizeScale = (p.getDouble('ov_size') ?? 1.0).clamp(0.6, 1.6);
      _bgAlpha = (p.getInt('ov_bg_alpha') ?? 200).clamp(0, 255);
      _overlayMode = p.getInt('ov_mode') ?? 0;
      _vibrate = p.getBool('ov_vibrate') ?? false;
    });
  }

  Future<void> _saveConfig() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('ov_font_color', _fontColor);
    await p.setDouble('ov_size', _sizeScale);
    await p.setInt('ov_bg_alpha', _bgAlpha);
    await p.setInt('ov_mode', _overlayMode);
    await p.setBool('ov_vibrate', _vibrate);
  }

  Future<void> _pushConfig() async {
    if (!_overlayActive) return;
    await OverlayBridge.updateConfig(
      fontColor: _fontColor,
      sizeScale: _sizeScale,
      bgAlpha: _bgAlpha,
      vibrate: _vibrate,
    );
  }

  /// 把计时状态推送到悬浮窗（主时间 + 小字行 + 按钮图标 + 计次列表）。
  void _syncOverlay() {
    if (!_overlayActive) return;
    if (_overlayMode == 1) {
      // 单次模式：只显示当前轮(本次)计时，小字显示第N次
      OverlayBridge.updateTotal(formatDuration(_model.lapDelta));
      OverlayBridge.updateSecondary('#${_model.laps.length + 1}');
    } else {
      // 总时间模式：大显示总时间，小字显示本次时间 + 轮次
      OverlayBridge.updateTotal(formatDuration(_model.elapsed));
      OverlayBridge.updateSecondary(
          '本次 ${formatDuration(_model.lapDelta)} · 第${_model.laps.length + 1}轮');
    }
    OverlayBridge.updateRunning(paused: _model.isPaused);
    _syncLapList();
  }

  /// 计次列表变化时推送到原生，供悬浮窗的计次列表弹窗展示。
  void _syncLapList() {
    if (!_overlayActive) return;
    if (_model.laps.length == _lastLapCount) return;
    _lastLapCount = _model.laps.length;
    final lines = <String>['计次记录(共${_model.laps.length}次)'];
    for (var i = 0; i < _model.laps.length; i++) {
      final cumulative = _model.laps[i];
      final delta = durationDiff(
          cumulative, i == 0 ? Duration.zero : _model.laps[i - 1]);
      lines.add('#${i + 1}  本次 ${formatDuration(delta)}  累计 ${formatDuration(cumulative)}');
    }
    OverlayBridge.updateLaps(lines);
  }

  Future<void> _startOverlay() async {
    final ok = await OverlayBridge.startForeground();
    if (!ok) {
      _showPermissionPrompt();
    } else {
      if (mounted) setState(() => _overlayActive = true);
      // 原生端重启后 lastLaps 已清空，强制下次 _syncLapList 重新推送全部计次
      _lastLapCount = -1;
      // 先下发配置(原生会重建悬浮窗)，再同步计时文本，避免“本次”小字被重建清掉后突兀出现
      await _pushConfig();
      _syncOverlay();
    }
  }

  Future<void> _stopOverlay() async {
    await OverlayBridge.stopForeground();
    if (mounted) setState(() => _overlayActive = false);
  }

  void _showPermissionPrompt() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('请在跳转的设置页中允许“悬浮窗”权限')),
    );
    OverlayBridge.requestOverlayPermission();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('F-Stopwatch'),
        actions: <Widget>[
          IconButton(
            tooltip: '悬浮窗设置',
            icon: const Icon(Icons.picture_in_picture_alt),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AnimatedBuilder(
              animation: _model,
              builder: (context, _) => Column(
                children: <Widget>[
                  Text(
                    formatDuration(_model.elapsed),
                    style: const TextStyle(
                      fontSize: 64,
                      fontWeight: FontWeight.w300,
                      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '本次 ${formatDuration(_model.lapDelta)} · 共 ${_model.laps.length} 次',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      FilledButton.icon(
                        onPressed: _model.toggle,
                        icon: Icon(
                            _model.isPaused ? Icons.play_arrow : Icons.pause),
                        label: Text(_model.isPaused ? '开始' : '暂停'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: _model.lap,
                        icon: const Icon(Icons.flag),
                        label: const Text('计次+1'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: _model.reset,
                        icon: const Icon(Icons.refresh),
                        label: const Text('重置'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Expanded(child: _lapList()),
                  const SizedBox(height: 12),
                  _overlayCard(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          void paint() {
            setSheetState(() {});
            setState(() {});
          }

          void refreshOverlay() {
            _styleDebounce?.cancel();
            _saveConfig();
            _pushConfig();
            _syncOverlay();
          }

          /// 连续调整的样式(颜色/大小/透明度)：界面即时更新，悬浮窗延迟 500ms 统一刷新。
          void scheduleStyleRefresh() {
            paint();
            _styleDebounce?.cancel();
            _styleDebounce = Timer(const Duration(milliseconds: 500), () {
              _styleDebounce = null;
              _saveConfig();
              _pushConfig();
              _syncOverlay();
            });
          }

          void apply() {
            paint();
            refreshOverlay();
          }

          const swatches = <Color>[
            Color(0xFFFFFFFF),
            Color(0xFFFFEB3B),
            Color(0xFF00E5FF),
            Color(0xFF76FF03),
            Color(0xFFFF5252),
          ];
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: SingleChildScrollView(
                child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('悬浮窗设置',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  const Text('显示模式', style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  SegmentedButton<int>(
                    segments: const <ButtonSegment<int>>[
                      ButtonSegment<int>(
                        value: 0,
                        icon: Icon(Icons.timer),
                        label: Text('总时间'),
                      ),
                      ButtonSegment<int>(
                        value: 1,
                        icon: Icon(Icons.looks_one),
                        label: Text('单次'),
                      ),
                    ],
                    selected: <int>{_overlayMode},
                    onSelectionChanged: (sel) {
                      _overlayMode = sel.first;
                      apply();
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _overlayMode == 1
                        ? '只显示当前次数计时，点“计次+1”进入下一轮'
                        : '大号显示总时间，下方小字显示本次时间',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  const Text('字体颜色', style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    children: swatches.map((c) {
                      final selected = _fontColor == c.toARGB32();
                      return GestureDetector(
                        onTap: () {
                          _fontColor = c.toARGB32();
                          scheduleStyleRefresh();
                        },
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.grey.shade700,
                              width: selected ? 3 : 1,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      const Text('大小', style: TextStyle(fontWeight: FontWeight.w500)),
                      Text('${_sizeScale.toStringAsFixed(2)}x',
                          style: TextStyle(color: Colors.grey.shade500)),
                    ],
                  ),
                  Slider(
                    value: _sizeScale,
                    min: 0.6,
                    max: 1.6,
                    onChanged: (v) {
                      _sizeScale = v;
                      scheduleStyleRefresh();
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      const Text('背景透明度',
                          style: TextStyle(fontWeight: FontWeight.w500)),
                      Text('${(_bgAlpha / 255 * 100).round()}%',
                          style: TextStyle(color: Colors.grey.shade500)),
                    ],
                  ),
                  Slider(
                    value: _bgAlpha / 255 * 100,
                    min: 0,
                    max: 100,
                    onChanged: (v) {
                      _bgAlpha = (v / 100 * 255).round().clamp(0, 255);
                      scheduleStyleRefresh();
                    },
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      const Text('按钮振动',
                          style: TextStyle(fontWeight: FontWeight.w500)),
                      Switch(
                        value: _vibrate,
                        onChanged: (v) {
                          _vibrate = v;
                          paint();
                          refreshOverlay();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('位置设置',
                      style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: OverlayBridge.resetPosition,
                      icon: const Icon(Icons.center_focus_strong),
                      label: const Text('恢复默认位置'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        _fontColor = 0xFFFFFFFF;
                        _sizeScale = 1.0;
                        _bgAlpha = 200;
                        _overlayMode = 0;
                        apply();
                      },
                      icon: const Icon(Icons.settings_backup_restore),
                      label: const Text('恢复默认设置'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('提示：上滑右上角锁定图标可移动悬浮窗，再点击固定',
                      style: TextStyle(
                          color: Colors.grey.shade500, fontSize: 12)),
                ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _overlayCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(_overlayPermission ? Icons.check_circle : Icons.warning,
                    color: _overlayPermission ? Colors.green : Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _overlayPermission ? '已允许悬浮窗' : '需要悬浮窗权限',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                if (!_overlayPermission) ...<Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _showPermissionPrompt,
                      icon: const Icon(Icons.settings),
                      label: const Text('去授权'),
                    ),
                  ),
                ] else ...<Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _overlayActive ? _stopOverlay : _startOverlay,
                      icon: Icon(_overlayActive ? Icons.cancel : Icons.picture_in_picture_alt),
                      label: Text(_overlayActive ? '停止悬浮窗' : '启动悬浮窗'),
                    ),
                  ),
                ],
              ],
            ),
            if (_overlayActive) ...<Widget>[
              const SizedBox(height: 8),
              Text('悬浮窗已显示总时间，可在其他应用上悬浮操作',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _lapList() {
    final laps = _model.laps;
    if (laps.isEmpty) {
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 32),
          child: Text('尚无打点记录\n点击“计次+1”记录时间点',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500, height: 1.6)),
        ),
      );
    }
    return ListView.builder(
      itemCount: laps.length,
      itemBuilder: (context, i) {
        final cumulative = laps[i];
        final delta =
            durationDiff(cumulative, i == 0 ? Duration.zero : laps[i - 1]);
        return ListTile(
          dense: true,
          leading: Text('#${i + 1}',
              style: TextStyle(color: Colors.grey.shade500)),
          title: Text('本次 ${formatDuration(delta)}',
              style: const TextStyle(
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()])),
          trailing: Text('累计 ${formatDuration(cumulative)}',
              style: TextStyle(
                  color: Colors.grey.shade500,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures()
                  ])),
        );
      },
    );
  }
}