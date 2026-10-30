import 'package:flutter/material.dart';

import '../../format.dart';
import '../../history_store.dart';

/// 历史记录页：查看每次重置归档的计时，支持日期筛选、单条/批量删除与计次详情。
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<HistoryRecord> _records = <HistoryRecord>[];
  bool _loading = true;
  bool _selectionMode = false;
  final Set<String> _selected = <String>{};
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final records = await HistoryStore.load();
    if (!mounted) return;
    setState(() {
      _records = records;
      _loading = false;
    });
  }

  List<HistoryRecord> get _filtered {
    if (_startDate == null && _endDate == null) return _records;
    final from = _startDate == null
        ? null
        : DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
    final to = _endDate == null
        ? null
        : DateTime(_endDate!.year, _endDate!.month, _endDate!.day)
            .add(const Duration(days: 1));
    return _records.where((r) {
      if (from != null && r.endAt.isBefore(from)) return false;
      if (to != null && !r.endAt.isBefore(to)) return false;
      return true;
    }).toList();
  }

  /// 选择开始/结束日期（日历点选，无需手动输入）。选择后自动修正起止顺序。
  Future<void> _pickDate({required bool isStart}) async {
    final base = isStart ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: base ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: isStart ? '选择开始日期' : '选择结束日期',
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) _endDate = picked;
      } else {
        _endDate = picked;
        if (_startDate != null && _startDate!.isAfter(picked)) {
          _startDate = picked;
        }
      }
    });
  }

  void _toggleSelection() {
    setState(() {
      _selectionMode = !_selectionMode;
      _selected.clear();
    });
  }

  void _toggleOne(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  void _toggleAll() {
    final ids = _filtered.map((r) => r.id).toSet();
    setState(() {
      if (_selected.length == ids.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(ids);
      }
    });
  }

  Future<bool?> _confirmDelete(int count) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除记录'),
        content: Text(count == 1 ? '确认删除这条计时记录？' : '确认删除选中的 $count 条记录？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteIds(Set<String> ids) async {
    if (ids.isEmpty) return;
    final ok = await _confirmDelete(ids.length);
    if (ok != true) return;
    final records = await HistoryStore.removeAll(ids);
    if (!mounted) return;
    setState(() {
      _records = records;
      _selected.clear();
      _selectionMode = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectionMode ? '已选 ${_selected.length} 条' : '历史记录'),
        actions: _selectionMode
            ? <Widget>[
                IconButton(
                  tooltip: '全选',
                  onPressed: filtered.isEmpty ? null : _toggleAll,
                  icon: const Icon(Icons.select_all),
                ),
                IconButton(
                  tooltip: '删除',
                  onPressed: _selected.isEmpty
                      ? null
                      : () => _deleteIds(_selected.toSet()),
                  icon: const Icon(Icons.delete_outline),
                ),
                TextButton(onPressed: _toggleSelection, child: const Text('取消')),
              ]
            : <Widget>[
                IconButton(
                  tooltip: '批量选择',
                  onPressed: _records.isEmpty ? null : _toggleSelection,
                  icon: const Icon(Icons.checklist),
                ),
              ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? _empty()
              : Column(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _pickDate(isStart: true),
                              icon: const Icon(Icons.event, size: 18),
                              label: Text(_startDate == null
                                  ? '开始日期'
                                  : _date(_startDate!)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _pickDate(isStart: false),
                              icon: const Icon(Icons.event, size: 18),
                              label: Text(_endDate == null
                                  ? '结束日期'
                                  : _date(_endDate!)),
                            ),
                          ),
                          if (_startDate != null || _endDate != null)
                            IconButton(
                              tooltip: '清除筛选',
                              onPressed: () => setState(() {
                                _startDate = null;
                                _endDate = null;
                              }),
                              icon: const Icon(Icons.close),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('共 ${filtered.length} 条',
                            style: TextStyle(color: Colors.grey.shade500)),
                      ),
                    ),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text('该时间段内没有记录',
                                  style:
                                      TextStyle(color: Colors.grey.shade500)),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.only(bottom: 12),
                              itemCount: filtered.length,
                              itemBuilder: (context, i) =>
                                  _recordTile(filtered[i]),
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.history, size: 56, color: Colors.grey.shade600),
          const SizedBox(height: 12),
          Text('暂无历史记录',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 16)),
          const SizedBox(height: 6),
          Text('点击主页“重置”后会自动归档一次计时',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _recordTile(HistoryRecord r) {
    final selected = _selected.contains(r.id);
    final sameDay = r.startAt.year == r.endAt.year &&
        r.startAt.month == r.endAt.month &&
        r.startAt.day == r.endAt.day;
    final endText =
        sameDay ? _time(r.endAt) : '${_date(r.endAt)} ${_time(r.endAt)}';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: _selectionMode
            ? Checkbox(
                value: selected,
                onChanged: (_) => _toggleOne(r.id),
              )
            : const Icon(Icons.timer_outlined),
        title: Text('${_date(r.startAt)} ${_time(r.startAt)}'),
        subtitle: Text(
          '结束 $endText · ${r.laps.length} 次计次',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
        ),
        trailing: Text(
          formatDuration(r.total),
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        onTap: () {
          if (_selectionMode) {
            _toggleOne(r.id);
          } else {
            _openDetail(r);
          }
        },
        onLongPress: () => _deleteIds(<String>{r.id}),
      ),
    );
  }

  Future<void> _openDetail(HistoryRecord record) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.8,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('计时详情',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                _kv('开始时间', '${_date(record.startAt)} ${_time(record.startAt)}'),
                _kv('结束时间', '${_date(record.endAt)} ${_time(record.endAt)}'),
                _kv('总时长', formatDuration(record.total)),
                _kv('计次', '${record.laps.length} 次'),
                const Divider(height: 24),
                if (record.laps.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('本次没有计次记录',
                        style: TextStyle(color: Colors.grey.shade500)),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: record.laps.length,
                      itemBuilder: (context, i) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Text('#${i + 1}',
                            style: TextStyle(color: Colors.grey.shade500)),
                        title: Text('本次 ${formatDuration(record.lapAt(i))}',
                            style: const TextStyle(
                                fontFeatures: <FontFeature>[
                                  FontFeature.tabularFigures()
                                ])),
                        trailing: Text('累计 ${formatDuration(record.laps[i])}',
                            style: TextStyle(
                                color: Colors.grey.shade500,
                                fontFeatures: const <FontFeature>[
                                  FontFeature.tabularFigures()
                                ])),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await _confirmDelete(1);
                      if (ok != true) return;
                      if (!ctx.mounted) return;
                      Navigator.of(ctx).pop();
                      final records =
                          await HistoryStore.removeAll(<String>[record.id]);
                      if (!mounted) return;
                      setState(() => _records = records);
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('删除此记录'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 84,
            child: Text(label,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

String _two(int v) => v.toString().padLeft(2, '0');

String _date(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

String _time(DateTime d) =>
    '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';
