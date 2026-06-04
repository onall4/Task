import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart'
    show StateNotifier, StateNotifierProvider;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'local_database.dart' show Task;

enum TaskRepeatRule { none, daily, weekly, monthly }

class TaskScheduleMetadata {
  const TaskScheduleMetadata({
    this.scheduledDate,
    this.startAt,
    this.endAt,
    this.repeatRule = TaskRepeatRule.none,
  });

  factory TaskScheduleMetadata.fromTask(Task task) {
    final dueAt = task.dueAt;
    return TaskScheduleMetadata(
      scheduledDate: dueAt == null ? null : taskDateOnly(dueAt),
      endAt: dueAt,
    );
  }

  factory TaskScheduleMetadata.fromJson(Map<String, Object?> json) {
    return TaskScheduleMetadata(
      scheduledDate: _dateTimeFromJson(json['scheduledDate']),
      startAt: _dateTimeFromJson(json['startAt']),
      endAt: _dateTimeFromJson(json['endAt']),
      repeatRule: TaskRepeatRule.values.firstWhere(
        (rule) => rule.name == json['repeatRule'],
        orElse: () => TaskRepeatRule.none,
      ),
    );
  }

  final DateTime? scheduledDate;
  final DateTime? startAt;
  final DateTime? endAt;
  final TaskRepeatRule repeatRule;

  DateTime? get sortAt => startAt ?? endAt ?? scheduledDate;

  bool get hasMeaningfulSchedule {
    return scheduledDate != null ||
        startAt != null ||
        endAt != null ||
        repeatRule != TaskRepeatRule.none;
  }

  TaskScheduleMetadata copyWith({
    DateTime? scheduledDate,
    bool clearScheduledDate = false,
    DateTime? startAt,
    bool clearStartAt = false,
    DateTime? endAt,
    bool clearEndAt = false,
    TaskRepeatRule? repeatRule,
  }) {
    return TaskScheduleMetadata(
      scheduledDate: clearScheduledDate
          ? null
          : scheduledDate ?? this.scheduledDate,
      startAt: clearStartAt ? null : startAt ?? this.startAt,
      endAt: clearEndAt ? null : endAt ?? this.endAt,
      repeatRule: repeatRule ?? this.repeatRule,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'scheduledDate': scheduledDate?.toIso8601String(),
      'startAt': startAt?.toIso8601String(),
      'endAt': endAt?.toIso8601String(),
      'repeatRule': repeatRule.name,
    };
  }
}

final taskScheduleControllerProvider =
    StateNotifierProvider<
      TaskScheduleController,
      Map<String, TaskScheduleMetadata>
    >((ref) => TaskScheduleController(const TaskScheduleStorage()));

class TaskScheduleController
    extends StateNotifier<Map<String, TaskScheduleMetadata>> {
  TaskScheduleController(this._storage) : super(const {}) {
    _hydrate();
  }

  final TaskScheduleStorage _storage;
  var _hydrated = false;

  Future<void> _hydrate() async {
    state = await _storage.load();
    _hydrated = true;
  }

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

  Future<void> _persist() async {
    if (!_hydrated) {
      return;
    }
    await _storage.save(state);
  }
}

class TaskScheduleStorage {
  const TaskScheduleStorage();

  static const _fileName = 'tasknet_task_schedules.json';

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

  Future<void> save(Map<String, TaskScheduleMetadata> schedules) async {
    final file = await _storageFile();
    final encoded = schedules.map(
      (key, value) => MapEntry(key, value.toJson()),
    );
    await file.writeAsString(jsonEncode(encoded), flush: true);
  }

  Future<File> _storageFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File(p.join(directory.path, _fileName));
  }
}

TaskScheduleMetadata effectiveTaskSchedule(
  Task task,
  Map<String, TaskScheduleMetadata> schedules,
) {
  return schedules[task.id] ?? TaskScheduleMetadata.fromTask(task);
}

DateTime taskDateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

bool isSameTaskDate(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

bool taskOccursOnDate(
  Task task,
  TaskScheduleMetadata schedule,
  DateTime date,
) {
  final scheduledDate = schedule.scheduledDate ?? task.dueAt;
  if (scheduledDate == null) {
    return false;
  }

  final dateOnly = taskDateOnly(date);
  final baseDate = taskDateOnly(scheduledDate);
  if (dateOnly.isBefore(baseDate)) {
    return false;
  }

  return switch (schedule.repeatRule) {
    TaskRepeatRule.none => isSameTaskDate(baseDate, dateOnly),
    TaskRepeatRule.daily => true,
    TaskRepeatRule.weekly => baseDate.weekday == dateOnly.weekday,
    TaskRepeatRule.monthly => baseDate.day == dateOnly.day,
  };
}

DateTime? _dateTimeFromJson(Object? value) {
  return switch (value) {
    String text => DateTime.tryParse(text),
    _ => null,
  };
}
