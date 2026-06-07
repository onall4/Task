/*
 * 习惯追踪数据层。
 *
 * 这个文件负责管理日历页中的习惯打卡功能：
 * - HabitEntry — 习惯条目数据模型
 * - HabitController — 习惯的创建、打卡切换和删除
 * - HabitStorage — 本地 JSON 文件持久化
 *
 * 每条习惯记录标题、创建时间和已打卡日期集合，支持按天切换打卡状态。
 */
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart'
    show StateNotifier, StateNotifierProvider;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 习惯控制器 Provider。
///
/// 全局单例，管理所有习惯条目列表。
final habitControllerProvider =
    StateNotifierProvider<HabitController, List<HabitEntry>>(
      (ref) => HabitController(const HabitStorage()),
    );

/// 习惯条目。
///
/// 表示一个可追踪的日常习惯，记录标题、描述、创建时间以及
/// 已打卡的日期集合。
class HabitEntry {
  const HabitEntry({
    required this.id,
    required this.title,
    this.description = '',
    required this.createdAt,
    this.checkedDateKeys = const {},
  });

  /// 从 JSON 字典反序列化习惯条目。
  ///
  /// 对缺失或格式不正确的字段采用安全的默认值。
  factory HabitEntry.fromJson(Map<String, Object?> json) {
    final checked = switch (json['checkedDateKeys']) {
      List<Object?> values => values.whereType<String>().toSet(),
      _ => <String>{},
    };
    final rawId = json['id'];
    final rawTitle = json['title'];
    final rawDescription = json['description'];
    final rawCreatedAt = json['createdAt'];
    return HabitEntry(
      id: rawId is String ? rawId : '',
      title: rawTitle is String ? rawTitle : '',
      description: rawDescription is String ? rawDescription : '',
      createdAt: DateTime.tryParse(rawCreatedAt is String ? rawCreatedAt : '') ??
          DateTime.now(),
      checkedDateKeys: checked,
    );
  }

  /// 唯一标识，基于创建时间戳生成。
  final String id;

  /// 习惯名称。
  final String title;

  /// 习惯的附加描述。
  final String description;

  /// 创建时间。
  final DateTime createdAt;

  /// 已打卡日期的 ISO 键集合。
  ///
  /// 每个键由 [habitDateKey] 生成，格式为 yyyy-MM-dd。
  final Set<String> checkedDateKeys;

  /// 判断指定日期是否已打卡。
  bool isCheckedOn(DateTime date) {
    return checkedDateKeys.contains(habitDateKey(date));
  }

  /// 复制并选择性覆盖字段。
  HabitEntry copyWith({
    String? title,
    String? description,
    Set<String>? checkedDateKeys,
  }) {
    return HabitEntry(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      createdAt: createdAt,
      checkedDateKeys: checkedDateKeys ?? this.checkedDateKeys,
    );
  }

  /// 序列化为 JSON 字典。
  Map<String, Object?> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
      'checkedDateKeys': checkedDateKeys.toList()..sort(),
    };
  }
}

/// 习惯数据控制器。
///
/// 管理所有习惯条目，支持创建、打卡切换和删除。
/// 在创建时自动从本地文件还原数据，并在每次变更后自动持久化。
class HabitController extends StateNotifier<List<HabitEntry>> {
  HabitController(this._storage) : super(const []) {
    _hydrate();
  }

  final HabitStorage _storage;
  var _hydrated = false;

  /// 从本地存储加载已持久化的习惯数据。
  Future<void> _hydrate() async {
    state = await _storage.load();
    _hydrated = true;
  }

  /// 创建新习惯。
  ///
  /// 习惯 ID 基于当前时间戳的微秒级精度生成，避免冲突。
  Future<void> createHabit({
    required String title,
    String description = '',
  }) async {
    final now = DateTime.now();
    final habit = HabitEntry(
      id: '${now.microsecondsSinceEpoch}',
      title: title.trim(),
      description: description.trim(),
      createdAt: now,
    );
    state = [...state, habit];
    await _persist();
  }

  /// 切换指定日期上的打卡状态。
  ///
  /// 如果该日期已打卡则取消，否则添加打卡记录。
  Future<void> toggleCheck(String habitId, DateTime date) async {
    final key = habitDateKey(date);
    state = [
      for (final habit in state)
        if (habit.id == habitId)
          habit.copyWith(
            checkedDateKeys: _toggledDateKeys(habit.checkedDateKeys, key),
          )
        else
          habit,
    ];
    await _persist();
  }

  /// 删除指定习惯。
  Future<void> deleteHabit(String habitId) async {
    state = state.where((habit) => habit.id != habitId).toList(growable: false);
    await _persist();
  }

  /// 将当前状态写入本地存储。
  ///
  /// 在水合完成之前不会执行写入，避免在初始化阶段覆盖已持久化的数据。
  Future<void> _persist() async {
    if (!_hydrated) {
      return;
    }
    await _storage.save(state);
  }
}

/// 习惯数据的本地文件存储。
///
/// 使用 JSON 文件读写，存放在应用文档目录下。
class HabitStorage {
  const HabitStorage();

  static const _fileName = 'tasknet_habits.json';

  /// 从本地文件加载习惯列表。
  ///
  /// 加载后自动过滤掉 ID 或标题为空的条目。
  Future<List<HabitEntry>> load() async {
    try {
      final file = await _storageFile();
      if (!await file.exists()) {
        return const [];
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List<Object?>) {
        return const [];
      }
      final habits = <HabitEntry>[];
      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }
        final habit = HabitEntry.fromJson(Map<String, Object?>.from(item));
        if (habit.id.isNotEmpty && habit.title.isNotEmpty) {
          habits.add(habit);
        }
      }
      return habits;
    } catch (_) {
      return const [];
    }
  }

  /// 将习惯列表写入本地文件。
  Future<void> save(List<HabitEntry> habits) async {
    final file = await _storageFile();
    final encoded = habits.map((habit) => habit.toJson()).toList();
    await file.writeAsString(jsonEncode(encoded), flush: true);
  }

  /// 获取存储文件的完整路径。
  Future<File> _storageFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File(p.join(directory.path, _fileName));
  }
}

/// 生成用于打卡记录的日期键。
///
/// 格式为 yyyy-MM-dd 的 ISO 日期字符串，统一以 UTC 零时区表示。
String habitDateKey(DateTime date) {
  final normalized = DateTime(date.year, date.month, date.day);
  return normalized.toIso8601String();
}

/// 在打卡集合中添加或移除指定键。
///
/// 如果键已存在则移除（取消打卡），否则添加（打卡）。
Set<String> _toggledDateKeys(Set<String> source, String key) {
  final next = {...source};
  if (!next.add(key)) {
    next.remove(key);
  }
  return next;
}
