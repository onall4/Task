/*
 * 专注模块状态控制器。
 *
 * 这个文件负责专注模块的核心状态机：
 * - 番茄钟模式切换（倒计时 / 正计时）
 * - 运行状态切换（空闲 / 运行 / 暂停）
 * - 秒级 tick 推进与会话记录
 * - 常用时长维护
 * - 本地持久化协同
 *
 * 页面层只负责展示和交互事件派发，真正的“状态如何变化”统一在这里维护。
 */
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart'
    show StateNotifier, StateNotifierProvider;

import 'focus_storage.dart';

/// 计时器模式。
enum FocusTimerMode { countdown, countup }

/// 计时器运行状态。
enum FocusRunState { idle, running, paused }

/// 单次专注会话记录。
///
/// 对应数据统计页中的一条原始记录。
class FocusSessionRecord {
  const FocusSessionRecord({
    required this.startAt,
    required this.endAt,
    required this.duration,
    required this.mode,
    required this.completed,
    this.taskId,
    this.taskTitleSnapshot,
  });

  final DateTime startAt;
  final DateTime endAt;
  final Duration duration;
  final FocusTimerMode mode;
  final bool completed;
  final String? taskId;
  final String? taskTitleSnapshot;
}

/// 专注页完整状态快照。
///
/// 这个对象会被 UI 层订阅，用于驱动番茄钟页和统计页展示。
class FocusState {
  const FocusState({
    required this.mode,
    required this.runState,
    required this.countdownMinutes,
    required this.commonDurations,
    required this.elapsed,
    required this.currentSessionStartedAt,
    required this.currentTaskId,
    required this.currentTaskTitle,
    required this.sessions,
    required this.completionSignal,
  });

  factory FocusState.initial() {
    return const FocusState(
      mode: FocusTimerMode.countdown,
      runState: FocusRunState.idle,
      countdownMinutes: 30,
      commonDurations: [15, 30, 45, 60],
      elapsed: Duration.zero,
      currentSessionStartedAt: null,
      currentTaskId: null,
      currentTaskTitle: null,
      sessions: [],
      completionSignal: 0,
    );
  }

  final FocusTimerMode mode;
  final FocusRunState runState;
  final int countdownMinutes;
  final List<int> commonDurations;
  final Duration elapsed;
  final DateTime? currentSessionStartedAt;
  final String? currentTaskId;
  final String? currentTaskTitle;
  final List<FocusSessionRecord> sessions;
  final int completionSignal;

  /// 当前倒计时目标时长。
  Duration get countdownTarget => Duration(minutes: countdownMinutes);

  /// 倒计时剩余时长（最小为 0）。
  Duration get remaining {
    final result = countdownTarget - elapsed;
    if (result.isNegative) {
      return Duration.zero;
    }
    return result;
  }

  /// 仅空闲态允许编辑倒计时目标。
  bool get canEditDuration => runState == FocusRunState.idle;

  /// 创建新状态副本，支持按需替换字段。
  FocusState copyWith({
    FocusTimerMode? mode,
    FocusRunState? runState,
    int? countdownMinutes,
    List<int>? commonDurations,
    Duration? elapsed,
    DateTime? currentSessionStartedAt,
    bool clearCurrentSessionStartedAt = false,
    String? currentTaskId,
    String? currentTaskTitle,
    bool clearCurrentTask = false,
    List<FocusSessionRecord>? sessions,
    int? completionSignal,
  }) {
    return FocusState(
      mode: mode ?? this.mode,
      runState: runState ?? this.runState,
      countdownMinutes: countdownMinutes ?? this.countdownMinutes,
      commonDurations: commonDurations ?? this.commonDurations,
      elapsed: elapsed ?? this.elapsed,
      currentSessionStartedAt: clearCurrentSessionStartedAt
          ? null
          : (currentSessionStartedAt ?? this.currentSessionStartedAt),
      currentTaskId: clearCurrentTask
          ? null
          : (currentTaskId ?? this.currentTaskId),
      currentTaskTitle: clearCurrentTask
          ? null
          : (currentTaskTitle ?? this.currentTaskTitle),
      sessions: sessions ?? this.sessions,
      completionSignal: completionSignal ?? this.completionSignal,
    );
  }
}

/// 专注状态持久化存储 Provider。
final focusStorageProvider = Provider<FocusStorage>((ref) {
  return const FocusStorage();
});

/// 专注状态控制器 Provider。
final focusControllerProvider =
    StateNotifierProvider<FocusController, FocusState>(
      (ref) => FocusController(ref.read(focusStorageProvider)),
    );

/// 专注状态控制器。
///
/// 对外提供“开始/暂停/重置/切换模式”等命令式接口，内部维护定时器和会话写入。
class FocusController extends StateNotifier<FocusState> {
  FocusController(this._storage) : super(FocusState.initial()) {
    unawaited(_hydrateFromStorage());
  }

  final FocusStorage _storage;
  Timer? _ticker;
  var _hydrated = false;
  var _tickPersistCounter = 0;

  @override
  void dispose() {
    _stopTicker();
    unawaited(_persistState(force: true));
    super.dispose();
  }

  /// 切换计时模式。
  ///
  /// 若当前会话已有进度，切模式前会先记录一次“中断会话”。
  void setMode(FocusTimerMode mode) {
    if (state.mode == mode) {
      return;
    }
    if (_hasSessionProgress) {
      _recordInterruptedIfNeeded();
    }
    _stopTicker();
    state = state.copyWith(
      mode: mode,
      runState: FocusRunState.idle,
      elapsed: Duration.zero,
      clearCurrentSessionStartedAt: true,
    );
    unawaited(_persistState(force: true));
  }

  /// 选择倒计时分钟数。
  void selectCountdownMinutes(int minutes) {
    if (minutes <= 0) {
      return;
    }
    state = state.copyWith(
      countdownMinutes: minutes,
      elapsed: state.mode == FocusTimerMode.countdown ? Duration.zero : null,
      runState: state.mode == FocusTimerMode.countdown
          ? FocusRunState.idle
          : state.runState,
      clearCurrentSessionStartedAt: state.mode == FocusTimerMode.countdown,
    );
    if (state.mode == FocusTimerMode.countdown) {
      _stopTicker();
    }
    unawaited(_persistState(force: true));
  }

  /// 选择或清除本次专注绑定的任务。
  void setCurrentTask({String? taskId, String? title}) {
    if (taskId == null) {
      state = state.copyWith(clearCurrentTask: true);
    } else {
      state = state.copyWith(currentTaskId: taskId, currentTaskTitle: title);
    }
    unawaited(_persistState(force: true));
  }

  /// 开始或继续计时。
  void startOrResume() {
    if (state.runState == FocusRunState.running) {
      return;
    }
    if (state.runState == FocusRunState.idle) {
      state = state.copyWith(
        runState: FocusRunState.running,
        currentSessionStartedAt: DateTime.now(),
      );
    } else {
      state = state.copyWith(runState: FocusRunState.running);
    }
    _startTicker();
    unawaited(_persistState(force: true));
  }

  /// 暂停计时。
  void pause() {
    if (state.runState != FocusRunState.running) {
      return;
    }
    _stopTicker();
    state = state.copyWith(runState: FocusRunState.paused);
    unawaited(_persistState(force: true));
  }

  /// 重置当前会话。
  void reset() {
    if (_hasSessionProgress) {
      _recordInterruptedIfNeeded();
    }
    _stopTicker();
    state = state.copyWith(
      runState: FocusRunState.idle,
      elapsed: Duration.zero,
      clearCurrentSessionStartedAt: true,
    );
    unawaited(_persistState(force: true));
  }

  /// 新增常用时长。
  ///
  /// 返回 `false` 表示越界或重复。
  bool addCommonDuration(int minutes) {
    if (minutes < 1 ||
        minutes > 180 ||
        state.commonDurations.contains(minutes)) {
      return false;
    }
    final durations = [...state.commonDurations, minutes]..sort();
    state = state.copyWith(commonDurations: durations);
    unawaited(_persistState(force: true));
    return true;
  }

  /// 更新已有常用时长。
  ///
  /// 返回 `false` 表示旧值不存在、新值越界或新值重复。
  bool updateCommonDuration({
    required int oldMinutes,
    required int newMinutes,
  }) {
    if (newMinutes < 1 || newMinutes > 180) {
      return false;
    }
    final durations = [...state.commonDurations];
    final oldIndex = durations.indexOf(oldMinutes);
    if (oldIndex < 0) {
      return false;
    }
    if (oldMinutes != newMinutes && durations.contains(newMinutes)) {
      return false;
    }
    durations[oldIndex] = newMinutes;
    durations.sort();
    state = state.copyWith(commonDurations: durations);
    if (state.countdownMinutes == oldMinutes) {
      selectCountdownMinutes(newMinutes);
    }
    unawaited(_persistState(force: true));
    return true;
  }

  /// 删除常用时长。
  void removeCommonDuration(int minutes) {
    if (!state.commonDurations.contains(minutes)) {
      return;
    }
    final durations = [...state.commonDurations]
      ..remove(minutes)
      ..sort();
    state = state.copyWith(commonDurations: durations);
    unawaited(_persistState(force: true));
  }

  /// 启动秒级 ticker。
  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  /// 停止 ticker。
  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  /// 每秒推进一次状态。
  ///
  /// 倒计时结束时自动记录“完成会话”，并触发一次 completionSignal 变化供 UI 提示。
  void _tick() {
    if (state.runState != FocusRunState.running) {
      return;
    }
    final nextElapsed = state.elapsed + const Duration(seconds: 1);
    if (state.mode == FocusTimerMode.countdown &&
        nextElapsed >= state.countdownTarget) {
      _stopTicker();
      _recordSession(completed: true, durationOverride: state.countdownTarget);
      state = state.copyWith(
        runState: FocusRunState.idle,
        elapsed: Duration.zero,
        clearCurrentSessionStartedAt: true,
        completionSignal: state.completionSignal + 1,
      );
      unawaited(_persistState(force: true));
      return;
    }
    state = state.copyWith(elapsed: nextElapsed);
    _tickPersistCounter++;
    if (_tickPersistCounter >= 15) {
      _tickPersistCounter = 0;
      unawaited(_persistState(force: false));
    }
  }

  /// 当前是否有可记录的会话进度。
  bool get _hasSessionProgress =>
      state.runState != FocusRunState.idle || state.elapsed > Duration.zero;

  /// 在“未完成结束”时记录中断会话。
  void _recordInterruptedIfNeeded() {
    if (state.elapsed <= Duration.zero) {
      return;
    }
    _recordSession(completed: false);
  }

  /// 写入一条会话记录到状态列表。
  void _recordSession({required bool completed, Duration? durationOverride}) {
    final endAt = DateTime.now();
    final duration = durationOverride ?? state.elapsed;
    final startAt = state.currentSessionStartedAt ?? endAt.subtract(duration);
    final session = FocusSessionRecord(
      startAt: startAt,
      endAt: endAt,
      duration: duration,
      mode: state.mode,
      completed: completed,
      taskId: state.currentTaskId,
      taskTitleSnapshot: state.currentTaskTitle,
    );
    state = state.copyWith(sessions: [...state.sessions, session]);
  }

  /// 从本地存储恢复状态。
  ///
  /// 恢复成功后只保留状态，不恢复 completionSignal，避免应用重启后重复弹完成提示。
  Future<void> _hydrateFromStorage() async {
    final loaded = await _storage.load();
    if (loaded != null) {
      state = loaded.copyWith(completionSignal: 0);
    }
    _hydrated = true;
  }

  /// 持久化当前状态。
  ///
  /// 运行中使用节流（由 `_tickPersistCounter` 控制频率），非运行态立即落盘。
  Future<void> _persistState({required bool force}) async {
    if (!_hydrated) {
      return;
    }
    if (!force && state.runState == FocusRunState.running) {
      // 运行中使用节流保存。
    }
    await _storage.save(state);
  }
}
