/*
 * 专注模块本地存储层。
 *
 * 这个文件负责把 [FocusState] 与 JSON 文件互相转换：
 * - `save`：把内存状态持久化到本地文件。
 * - `load`：从本地文件恢复到内存状态。
 * - 规范化：过滤异常值，确保恢复后的状态稳定可用。
 */
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'focus_controller.dart';

/// 专注状态本地存储服务。
class FocusStorage {
  const FocusStorage();

  /// 专注状态文件名。
  static const _fileName = 'tasknet_focus_state.json';

  /// 读取并反序列化专注状态。
  ///
  /// 文件不存在或解析失败时返回 `null`，由上层使用默认初始状态。
  Future<FocusState?> load() async {
    try {
      final file = await _storageFile();
      if (!await file.exists()) {
        return null;
      }
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! Map) {
        return null;
      }
      return _stateFromJson(Map<String, Object?>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  /// 序列化并写入专注状态。
  Future<void> save(FocusState state) async {
    final file = await _storageFile();
    await file.writeAsString(jsonEncode(_stateToJson(state)), flush: true);
  }

  /// 获取专注状态文件路径。
  Future<File> _storageFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File(p.join(directory.path, _fileName));
  }
}

/// 把运行时状态转换为可落盘的 JSON 对象。
Map<String, Object?> _stateToJson(FocusState state) {
  return {
    'mode': state.mode.name,
    'runState': state.runState.name,
    'countdownMinutes': state.countdownMinutes,
    'commonDurations': state.commonDurations,
    'elapsedSeconds': state.elapsed.inSeconds,
    'currentSessionStartedAt': state.currentSessionStartedAt?.toIso8601String(),
    'currentTaskId': state.currentTaskId,
    'currentTaskTitle': state.currentTaskTitle,
    'sessions': state.sessions.map(_sessionToJson).toList(growable: false),
  };
}

/// 从 JSON 对象恢复运行时状态。
///
/// 这里会对关键字段做边界校验与兜底，防止老版本或异常数据导致崩溃。
FocusState _stateFromJson(Map<String, Object?> json) {
  final modeName = json['mode'];
  final runStateName = json['runState'];
  final rawDurations = json['commonDurations'];
  final rawSessions = json['sessions'];
  final rawCountdown = json['countdownMinutes'];
  final rawElapsedSeconds = json['elapsedSeconds'];
  final rawStartedAt = json['currentSessionStartedAt'];
  final rawCurrentTaskId = json['currentTaskId'];
  final rawCurrentTaskTitle = json['currentTaskTitle'];

  final mode = FocusTimerMode.values.firstWhere(
    (item) => item.name == modeName,
    orElse: () => FocusTimerMode.countdown,
  );
  final runState = FocusRunState.values.firstWhere(
    (item) => item.name == runStateName,
    orElse: () => FocusRunState.idle,
  );
  final countdownMinutes = switch (rawCountdown) {
    int value when value >= 1 && value <= 180 => value,
    _ => 30,
  };
  final elapsedSeconds = switch (rawElapsedSeconds) {
    int value when value >= 0 => value,
    _ => 0,
  };
  final commonDurations = _normalizeDurations(rawDurations);
  final sessions = _normalizeSessions(rawSessions);
  final currentSessionStartedAt = switch (rawStartedAt) {
    String value => DateTime.tryParse(value),
    _ => null,
  };

  return FocusState(
    mode: mode,
    runState: runState == FocusRunState.running
        ? FocusRunState.paused
        : runState,
    countdownMinutes: countdownMinutes,
    commonDurations: commonDurations,
    elapsed: Duration(seconds: elapsedSeconds),
    currentSessionStartedAt: currentSessionStartedAt,
    currentTaskId: rawCurrentTaskId is String && rawCurrentTaskId.isNotEmpty
        ? rawCurrentTaskId
        : null,
    currentTaskTitle:
        rawCurrentTaskTitle is String && rawCurrentTaskTitle.isNotEmpty
        ? rawCurrentTaskTitle
        : null,
    sessions: sessions,
    completionSignal: 0,
  );
}

/// 把单条会话记录序列化为 JSON。
Map<String, Object?> _sessionToJson(FocusSessionRecord item) {
  return {
    'startAt': item.startAt.toIso8601String(),
    'endAt': item.endAt.toIso8601String(),
    'durationSeconds': item.duration.inSeconds,
    'mode': item.mode.name,
    'completed': item.completed,
    'taskId': item.taskId,
    'taskTitleSnapshot': item.taskTitleSnapshot,
  };
}

/// 反序列化单条会话记录。
///
/// 字段缺失或值非法时返回 `null`，由上层过滤。
FocusSessionRecord? _sessionFromJson(Object? raw) {
  if (raw is! Map<Object?, Object?>) {
    return null;
  }
  final startAtRaw = raw['startAt'];
  final endAtRaw = raw['endAt'];
  final durationRaw = raw['durationSeconds'];
  final modeRaw = raw['mode'];
  final completedRaw = raw['completed'];
  final taskIdRaw = raw['taskId'];
  final taskTitleRaw = raw['taskTitleSnapshot'];

  if (startAtRaw is! String ||
      endAtRaw is! String ||
      durationRaw is! int ||
      durationRaw <= 0) {
    return null;
  }
  final startAt = DateTime.tryParse(startAtRaw);
  final endAt = DateTime.tryParse(endAtRaw);
  if (startAt == null || endAt == null) {
    return null;
  }
  final mode = FocusTimerMode.values.firstWhere(
    (item) => item.name == modeRaw,
    orElse: () => FocusTimerMode.countdown,
  );
  return FocusSessionRecord(
    startAt: startAt,
    endAt: endAt,
    duration: Duration(seconds: durationRaw),
    mode: mode,
    completed: completedRaw == true,
    taskId: taskIdRaw is String && taskIdRaw.isNotEmpty ? taskIdRaw : null,
    taskTitleSnapshot:
        taskTitleRaw is String && taskTitleRaw.isNotEmpty ? taskTitleRaw : null,
  );
}

/// 规范化常用时长列表（去重、排序、限制范围）。
List<int> _normalizeDurations(Object? raw) {
  final source = switch (raw) {
    List<Object?> value => value,
    _ => <Object?>[15, 30, 45, 60],
  };
  final values = <int>{};
  for (final item in source) {
    if (item is int && item >= 1 && item <= 180) {
      values.add(item);
    }
  }
  final normalized = values.toList()..sort();
  if (normalized.isEmpty) {
    return const [15, 30, 45, 60];
  }
  return normalized;
}

/// 规范化会话历史列表（过滤非法记录、限制最大条数）。
List<FocusSessionRecord> _normalizeSessions(Object? raw) {
  final source = switch (raw) {
    List<Object?> value => value,
    _ => const <Object?>[],
  };
  final sessions = <FocusSessionRecord>[];
  for (final item in source) {
    final parsed = _sessionFromJson(item);
    if (parsed != null) {
      sessions.add(parsed);
    }
  }
  if (sessions.length > 5000) {
    return sessions.sublist(sessions.length - 5000);
  }
  return sessions;
}
