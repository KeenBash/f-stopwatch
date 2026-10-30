import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'timer_data.dart';

/// 一条历史记录：一次计时会话 + 结束时间（点击“重置”时归档）。
class HistoryRecord {
  const HistoryRecord({
    required this.id,
    required this.endAt,
    required this.data,
  });

  final String id;

  /// 归档时刻（结束时间）。
  final DateTime endAt;

  /// 会话数据，与运行中快照共用 [TimerData] 格式。
  final TimerData data;

  Duration get total => data.elapsed;

  List<Duration> get laps => data.laps;

  /// 开始时间；旧数据缺少该字段时按结束时间倒推。
  DateTime get startAt => data.startedAt ?? endAt.subtract(total);

  Duration lapAt(int index) => data.lapAt(index);

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'e': endAt.millisecondsSinceEpoch,
        ...data.toJson(),
      };

  factory HistoryRecord.fromJson(Map<String, dynamic> m) => HistoryRecord(
        id: m['id'] as String,
        endAt: DateTime.fromMillisecondsSinceEpoch((m['e'] as num).toInt()),
        data: TimerData.fromJson(m),
      );
}

/// 历史记录本地存储（SharedPreferences 中的 JSON 数组，新记录在前）。
class HistoryStore {
  HistoryStore._();

  static const String _key = 'history_v1';

  static Future<List<HistoryRecord>> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null) return <HistoryRecord>[];
      final list = <HistoryRecord>[];
      for (final item in jsonDecode(raw) as List<dynamic>) {
        try {
          list.add(HistoryRecord.fromJson(item as Map<String, dynamic>));
        } catch (_) {
          // 跳过无法解析的旧格式记录，不影响其它记录
        }
      }
      return list;
    } catch (_) {
      return <HistoryRecord>[];
    }
  }

  static Future<void> _save(List<HistoryRecord> records) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _key, jsonEncode(records.map((r) => r.toJson()).toList()));
  }

  /// 追加一条记录（置于最前）。
  static Future<List<HistoryRecord>> add(HistoryRecord record) async {
    final records = await load();
    records.insert(0, record);
    await _save(records);
    return records;
  }

  /// 按 id 批量删除。
  static Future<List<HistoryRecord>> removeAll(Iterable<String> ids) async {
    final set = ids.toSet();
    final records = (await load())..removeWhere((r) => set.contains(r.id));
    await _save(records);
    return records;
  }
}
