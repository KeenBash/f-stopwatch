import 'package:flutter/material.dart';

import '../../format.dart';
import '../../stopwatch_model.dart';

/// Web 端根应用（调试用，功能与主端一致，不绑定热键）。
class WebStopwatchApp extends StatelessWidget {
  const WebStopwatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'F-Stopwatch',
      debugShowCheckedModeBanner: false,
      home: _WebHome(),
    );
  }
}

class _WebHome extends StatefulWidget {
  const _WebHome();

  @override
  State<_WebHome> createState() => _WebHomeState();
}

class _WebHomeState extends State<_WebHome> {
  final StopwatchModel _model = StopwatchModel();

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: <Widget>[
                Text('F-Stopwatch  ·  Web 调试端',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Expanded(
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
                        Text('本次 ${formatDuration(_model.lapDelta)}',
                            style: TextStyle(color: theme.colorScheme.outline)),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            FilledButton.icon(
                              onPressed: _model.toggle,
                              icon: Icon(_model.isPaused
                                  ? Icons.play_arrow
                                  : Icons.pause),
                              label: Text(_model.isPaused ? '开始' : '暂停'),
                              style: FilledButton.styleFrom(
                                  minimumSize: const Size(120, 48),
                                  textStyle: const TextStyle(fontSize: 18)),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              onPressed: _model.lap,
                              icon: const Icon(Icons.flag),
                              label: const Text('计次+1'),
                              style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(120, 48)),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton(
                              onPressed: _model.reset,
                              child: const Text('重置'),
                              style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(72, 48)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Expanded(child: _lapList(theme)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _lapList(ThemeData theme) {
    final laps = _model.laps;
    if (laps.isEmpty) {
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 32),
          child: Text('尚无打点记录\n点击“计次+1”记录时间点',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.outline, height: 1.6)),
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
          leading: Text('#${i + 1}', style: TextStyle(color: theme.colorScheme.outline)),
          title: Text('本次 ${formatDuration(delta)}',
              style: const TextStyle(
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()])),
          trailing: Text('累计 ${formatDuration(cumulative)}',
              style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFeatures: const <FontFeature>[FontFeature.tabularFigures()])),
        );
      },
    );
  }
}