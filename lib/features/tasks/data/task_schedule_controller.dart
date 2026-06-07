/*
 * 任务调度数据层。
 *
 * 这个文件负责管理任务的截止时间：
 * - TaskScheduleMetadata — 调度元数据值对象
 * - TaskScheduleController — 以任务 ID 为键的调度状态管理器
 * - TaskScheduleStorage — 本地 JSON 文件持久化
 * - taskOccursOnDate — 判断任务是否在指定日期出现
 *
 * 调度信息与任务实体分离存储，避免在任务表中引入过多可选字段。
 */
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart'
    show StateNotifier, StateNotifierProvider;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'local_database.dart' show Task;

/// 任务调度元数据。
///
/// 保存任务的截止时间。每个任务至多有一份调度元数据，
/// 由 [TaskScheduleController] 以任务 ID 为键统一管理。
class TaskScheduleMetadata {
  const TaskScheduleMetadata({this.endAt});

  /// 从任务实体构建默认的调度元数据。
  ///
  /// 仅使用任务的 [Task.dueAt] 作为截止时间。
  factory TaskScheduleMetadata.fromTask(Task task) {
    return TaskScheduleMetadata(endAt: task.dueAt);
  }

  /// 从 JSON 字典反序列化调度元数据。
  factory TaskScheduleMetadata.fromJson(Map<String, Object?> json) {
    return TaskScheduleMetadata(
      endAt: _dateTimeFromJson(json['endAt']),
    );
  }

  /// 截止时间。
  final DateTime? endAt;

  /// 用于排序的时间锚点。
  ///
  /// 当前以截止时间为准，在日历页的任务排序中使用。
  DateTime? get sortAt => endAt;

  /// 是否包含有意义的调度信息。
  ///
  /// 当截止时间存在时返回 true，用于在持久化时清理空值条目。
  bool get hasMeaningfulSchedule => endAt != null;

  /// 复制并选择性覆盖字段。
  TaskScheduleMetadata copyWith({
    DateTime? endAt,
    bool clearEndAt = false,
  }) {
    return TaskScheduleMetadata(
      endAt: clearEndAt ? null : endAt ?? this.endAt,
    );
  }

  /// 序列化为 JSON 字典。
  Map<String, Object?> toJson() {
    return {'endAt': endAt?.toIso8601String()};
  }
}

/// 任务调度控制器 Provider。
///
/// 全局单例，管理所有任务的调度元数据映射。
final taskScheduleControllerProvider =
    StateNotifierProvider<
      TaskScheduleController,
      Map<String, TaskScheduleMetadata>
    >((ref) => TaskScheduleController(const TaskScheduleStorage()));

/// 任务调度控制器。
///
/// 以任务 ID → [TaskScheduleMetadata] 的映射管理所有任务的调度信息。
/// 在创建时自动从本地文件还原数据，并在每次变更后自动持久化。
class TaskScheduleController
    extends StateNotifier<Map<String, TaskScheduleMetadata>> {
  TaskScheduleController(this._storage) : super(const {}) {
    _hydrate();
  }

  final TaskScheduleStorage _storage;
  var _hydrated = false;

  /// 从本地存储加载已持久化的调度数据。
  Future<void> _hydrate() async {
    state = await _storage.load();
    _hydrated = true;
  }

  /// 为指定任务保存调度元数据。
  ///
  /// 如果 [schedule] 不包含有意义的调度信息（无截止时间且重复规则为 none），
  /// 则移除该任务的调度条目，避免在磁盘上积累空数据。
  Future<void> saveSchedule(
    String taskId,
    TaskScheduleMetadata schedule,
  ) async {
    final next = Map<String, TaskScheduleMetadata>.from(state);
    if (schedule.hasMeaningfulSchedule) {
      next[taskId] = schedule;
    } else {
      next.remove(taskId);
    }
    state = next;
    await _persist();
  }

  /// 批量移除指定任务的调度元数据。
  ///
  /// 通常在任务被删除时调用，用于清理相关的调度条目。
  Future<void> removeSchedules(Iterable<String> taskIds) async {
    final removing = taskIds.toSet();
    if (removing.isEmpty) {
      return;
    }
    final next = Map<String, TaskScheduleMetadata>.from(state)
      ..removeWhere((taskId, _) => removing.contains(taskId));
    state = next;
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

/// 任务调度元数据的本地文件存储。
///
/// 使用 JSON 文件读写，存放在应用文档目录下。
class TaskScheduleStorage {
  const TaskScheduleStorage();

  static const _fileName = 'tasknet_task_schedules.json';

  /// 从本地文件加载调度元数据映射。
  ///
  /// 加载后会自动过滤掉不包含有意义调度信息的条目。
  Future<Map<String, TaskScheduleMetadata>> load() async {
    try {
      final file = await _storageFile();
      if (!await file.exists()) {
        return const {};
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return const {};
      }
      final schedules = <String, TaskScheduleMetadata>{};
      for (final entry in decoded.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is String && value is Map) {
          schedules[key] = TaskScheduleMetadata.fromJson(
            Map<String, Object?>.from(value),
          );
        }
      }
      return schedules..removeWhere((_, value) => !value.hasMeaningfulSchedule);
    } catch (_) {
      return const {};
    }
  }

  /// 将调度元数据映射写入本地文件。
  Future<void> save(Map<String, TaskScheduleMetadata> schedules) async {
    final file = await _storageFile();
    final encoded = schedules.map(
      (key, value) => MapEntry(key, value.toJson()),
    );
    await file.writeAsString(jsonEncode(encoded), flush: true);
  }

  /// 获取存储文件的完整路径。
  Future<File> _storageFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File(p.join(directory.path, _fileName));
  }
}

/// 获取任务的有效调度元数据。
///
/// 优先使用控制器中存储的自定义调度信息，如果不存在则从任务本身的
/// [Task.dueAt] 构建默认元数据。
TaskScheduleMetadata effectiveTaskSchedule(
  Task task,
  Map<String, TaskScheduleMetadata> schedules,
) {
  return schedules[task.id] ?? TaskScheduleMetadata.fromTask(task);
}

/// 提取日期部分，丢弃时间信息。
///
/// 用于日期比较和日历页中的日期匹配。
DateTime taskDateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

/// 判断两个日期是否在同一天。
bool isSameTaskDate(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

/// 判断任务是否在指定日期出现。
///
/// 任务仅在其截止日期当天出现。如果任务没有截止时间，
/// 则不会在任何日期出现。
bool taskOccursOnDate(Task task, DateTime date) {
  final dueAt = task.dueAt;
  if (dueAt == null) {
    return false;
  }
  return isSameTaskDate(taskDateOnly(dueAt), taskDateOnly(date));
}

/// 从 JSON 值安全解析 [DateTime]。
DateTime? _dateTimeFromJson(Object? value) {
  return switch (value) {
    String text => DateTime.tryParse(text),
    _ => null,
  };
}
