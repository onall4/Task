/*
 * 日历状态控制器。
 *
 * 这个文件负责管理日历页的核心交互状态：
 * - 日期选择与周导航
 * - 月网格的展开与收起
 * - 每天午夜的自动日期推进
 * - 可见月份范围的计算
 *
 * 状态由 CalendarController 统一管理，通过 Riverpod Provider 提供给日历页 UI。
 */
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart'
    show StateNotifier, StateNotifierProvider;

/// 日历状态控制器 Provider。
///
/// 全局单例，在 Provider 销毁时自动释放定时器资源。
final calendarControllerProvider =
    StateNotifierProvider<CalendarController, CalendarState>((ref) {
      final controller = CalendarController();
      ref.onDispose(controller.dispose);
      return controller;
    });

/// 日历可见月份范围 Provider。
///
/// 根据当前可见周的首尾日期推导出月份范围，用于日历页标题栏的月份展示。
final calendarVisibleMonthRangeProvider = Provider<CalendarVisibleMonthRange>((
  ref,
) {
  final state = ref.watch(calendarControllerProvider);
  final first = state.visibleWeekDates.first;
  final last = state.visibleWeekDates.last;
  return CalendarVisibleMonthRange(
    startMonth: DateTime(first.year, first.month),
    endMonth: DateTime(last.year, last.month),
  );
});

/// 日历可见月份范围。
///
/// 当可见周跨越两个月时，标题栏会同时显示两个月份。
class CalendarVisibleMonthRange {
  const CalendarVisibleMonthRange({
    required this.startMonth,
    required this.endMonth,
  });

  /// 当前视图的起始月份。
  final DateTime startMonth;

  /// 当前视图的结束月份。
  final DateTime endMonth;
}

/// 日历状态。
///
/// 包含用户当前选中的日期、今天日期、可见周的起始日期、
/// 展开/收起状态以及用户是否手动导航等信息。
class CalendarState {
  const CalendarState({
    required this.selectedDate,
    required this.todayDate,
    required this.visibleWeekStart,
    required this.isExpanded,
    required this.currentMonthForExpanded,
    required this.hasUserNavigatedWeek,
  });

  /// 创建以当前时间为基准的初始日历状态。
  factory CalendarState.initial(DateTime now) {
    final today = _dateOnly(now);
    final weekStart = _startOfWeek(today);
    return CalendarState(
      selectedDate: today,
      todayDate: today,
      visibleWeekStart: weekStart,
      isExpanded: false,
      currentMonthForExpanded: DateTime(today.year, today.month),
      hasUserNavigatedWeek: false,
    );
  }

  /// 用户当前选中的日期。
  final DateTime selectedDate;

  /// 今天的日期，午夜更新。
  final DateTime todayDate;

  /// 当前可见周的起始日期（周一）。
  final DateTime visibleWeekStart;

  /// 月网格是否处于展开状态。
  final bool isExpanded;

  /// 展开模式下当前显示的月份。
  final DateTime currentMonthForExpanded;

  /// 用户是否曾手动导航离开本周。
  ///
  /// 当此值为 false 时，跨天后自动跟随到今天的日期和星期。
  final bool hasUserNavigatedWeek;

  /// 当前可见周中每天的 [DateTime] 列表（7 天，从周一开始）。
  List<DateTime> get visibleWeekDates => List<DateTime>.generate(
    7,
    (index) => visibleWeekStart.add(Duration(days: index)),
    growable: false,
  );

  /// 复制并选择性覆盖字段。
  CalendarState copyWith({
    DateTime? selectedDate,
    DateTime? todayDate,
    DateTime? visibleWeekStart,
    bool? isExpanded,
    DateTime? currentMonthForExpanded,
    bool? hasUserNavigatedWeek,
  }) {
    return CalendarState(
      selectedDate: selectedDate ?? this.selectedDate,
      todayDate: todayDate ?? this.todayDate,
      visibleWeekStart: visibleWeekStart ?? this.visibleWeekStart,
      isExpanded: isExpanded ?? this.isExpanded,
      currentMonthForExpanded:
          currentMonthForExpanded ?? this.currentMonthForExpanded,
      hasUserNavigatedWeek: hasUserNavigatedWeek ?? this.hasUserNavigatedWeek,
    );
  }
}

/// 日历状态控制器。
///
/// 管理日历的日期选择、周导航、展开/收起和自动跨天更新。
/// 每天午夜自动刷新 [CalendarState.todayDate]，并根据用户是否已手动
/// 导航决定是否同步更新选中日期和可见周。
class CalendarController extends StateNotifier<CalendarState> {
  CalendarController() : super(CalendarState.initial(DateTime.now())) {
    _scheduleDayBoundaryTick();
  }

  /// 用于计算下一个午夜触发时间的定时器。
  Timer? _dayBoundaryTimer;

  @override
  void dispose() {
    _dayBoundaryTimer?.cancel();
    super.dispose();
  }

  /// 选中指定日期。
  ///
  /// 同时将可见周锚定到所选日期所在的周一，并更新展开月份。
  /// 如果选择来自展开网格中的点击，则自动收起日历。
  void selectDate(DateTime date, {bool fromExpanded = false}) {
    final selected = _dateOnly(date);
    final weekStart = _startOfWeek(selected);
    final inTodayWeek = _isSameDate(weekStart, _startOfWeek(state.todayDate));
    state = state.copyWith(
      selectedDate: selected,
      visibleWeekStart: weekStart,
      currentMonthForExpanded: DateTime(selected.year, selected.month),
      hasUserNavigatedWeek: !inTodayWeek,
      isExpanded: fromExpanded ? false : state.isExpanded,
    );
  }

  /// 设置可见周的起始日期。
  ///
  /// 当 [fromUser] 为 true 时（用户手动滑动），
  /// 如果新周不是本周则标记 [hasUserNavigatedWeek]。
  void setVisibleWeekStart(DateTime weekStart, {required bool fromUser}) {
    final normalizedWeekStart = _startOfWeek(weekStart);
    if (_isSameDate(normalizedWeekStart, state.visibleWeekStart)) {
      return;
    }
    final inTodayWeek = _isSameDate(
      normalizedWeekStart,
      _startOfWeek(state.todayDate),
    );
    state = state.copyWith(
      visibleWeekStart: normalizedWeekStart,
      currentMonthForExpanded: DateTime(
        normalizedWeekStart.year,
        normalizedWeekStart.month,
      ),
      hasUserNavigatedWeek: fromUser
          ? !inTodayWeek
          : state.hasUserNavigatedWeek,
    );
  }

  /// 切换月网格的展开/收起状态。
  void toggleExpanded() {
    setExpanded(!state.isExpanded);
  }

  /// 设置月网格的展开状态。
  void setExpanded(bool expanded) {
    if (expanded == state.isExpanded) {
      return;
    }
    state = state.copyWith(
      isExpanded: expanded,
      currentMonthForExpanded: DateTime(
        state.selectedDate.year,
        state.selectedDate.month,
      ),
    );
  }

  /// 跳转到今天所在周。
  ///
  /// 同时更新今天日期和选中日期，并清除手动导航标记。
  void jumpToToday() {
    final today = _dateOnly(DateTime.now());
    final weekStart = _startOfWeek(today);
    state = state.copyWith(
      todayDate: today,
      selectedDate: today,
      visibleWeekStart: weekStart,
      currentMonthForExpanded: DateTime(today.year, today.month),
      hasUserNavigatedWeek: false,
    );
  }

  /// 安排下一次午夜触发任务。
  ///
  /// 计算从当前时间到次日零点的毫秒数，并设置一次性定时器。
  void _scheduleDayBoundaryTick() {
    _dayBoundaryTimer?.cancel();
    final now = DateTime.now();
    final nextDay = DateTime(now.year, now.month, now.day + 1);
    final wait = nextDay.difference(now) + const Duration(seconds: 1);
    _dayBoundaryTimer = Timer(wait, _handleDayBoundaryReached);
  }

  /// 处理午夜到达事件。
  ///
  /// 更新 todayDate；如果用户未曾手动导航，则自动跳转到今天的日期和星期。
  void _handleDayBoundaryReached() {
    final today = _dateOnly(DateTime.now());
    if (_isSameDate(today, state.todayDate)) {
      _scheduleDayBoundaryTick();
      return;
    }
    if (state.hasUserNavigatedWeek) {
      state = state.copyWith(todayDate: today);
    } else {
      final weekStart = _startOfWeek(today);
      state = state.copyWith(
        todayDate: today,
        selectedDate: today,
        visibleWeekStart: weekStart,
        currentMonthForExpanded: DateTime(today.year, today.month),
      );
    }
    _scheduleDayBoundaryTick();
  }
}

/// 提取日期部分，丢弃时间信息。
DateTime _dateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

/// 计算指定日期所在周的周一日期。
///
/// 使用周一作为一周起始（ISO 标准）。
DateTime _startOfWeek(DateTime value) {
  final date = _dateOnly(value);
  final delta = (date.weekday - DateTime.monday) % 7;
  return date.subtract(Duration(days: delta));
}

/// 判断两个日期是否在同一天。
bool _isSameDate(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}
