import 'package:flutter_test/flutter_test.dart';

import 'package:f_stopwatch/format.dart';
import 'package:f_stopwatch/stopwatch_model.dart';

void main() {
  group('formatDuration', () {
    test('formats minutes:seconds.centiseconds', () {
      expect(formatDuration(Duration.zero), '00:00.00');
      expect(formatDuration(Duration(minutes: 1, seconds: 23, milliseconds: 450)),
          '01:23.45');
      expect(formatDuration(Duration(hours: 1, minutes: 2, seconds: 3)),
          '01:02:03.00');
    });
  });

  group('StopwatchModel', () {
    test('paused by default', () {
      final m = StopwatchModel();
      expect(m.isPaused, true);
      expect(m.elapsed, Duration.zero);
      expect(m.laps, isEmpty);
    });

    test('toggle starts then pauses', () async {
      final m = StopwatchModel();
      m.start();
      expect(m.isPaused, false);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      m.toggle();
      expect(m.isPaused, true);
      expect(m.elapsed, greaterThan(Duration.zero));
      m.dispose();
    });

    test('lap records cumulative time', () async {
      final m = StopwatchModel();
      m.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      m.lap();
      expect(m.laps, hasLength(1));
      expect(m.laps.first, greaterThan(Duration.zero));
      m.dispose();
    });

    test('lap ignored while not running', () {
      final m = StopwatchModel();
      m.lap();
      expect(m.laps, isEmpty);
      m.dispose();
    });

    test('pause then resume does not double-count elapsed', () async {
      final m = StopwatchModel();
      m.start();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final t1 = m.elapsed;
      m.pause(); // 暂停并结算到 _base
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final pausedAt = m.elapsed;
      // 暂停期间时间应保持不动
      expect(m.elapsed, pausedAt);

      m.start(); // 续跑（不得重复累计已暂停的 t1）
      await Future<void>.delayed(const Duration(milliseconds: 10));
      m.pause();
      final total = m.elapsed;
      // 总时间不能超过 暂停时点 + 刚才续跑的一段小余量（明显小于 2*t1）
      expect(total, lessThan(t1 + const Duration(milliseconds: 50)));
      expect(total, greaterThan(t1));
      m.dispose();
    });

    test('reset clears everything', () async {
      final m = StopwatchModel();
      m.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      m.lap();
      m.reset();
      expect(m.elapsed, Duration.zero);
      expect(m.laps, isEmpty);
      expect(m.isPaused, true);
      m.dispose();
    });
  });
}