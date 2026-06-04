import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart'
    show StateNotifier, StateNotifierProvider;

final calendarControllerProvider =
    StateNotifierProvider<CalendarController, CalendarState>((ref) {
      final controller = CalendarController();
      ref.onDispose(controller.dispose);
      return controller;
    });

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

class CalendarVisibleMonthRange {
  const CalendarVisibleMonthRange({
    required this.startMonth,
    required this.endMonth,
  });

  final DateTime startMonth;
  final DateTime endMonth;
}

class CalendarState {
  const CalendarState({
    required this.selectedDate,
    required this.todayDate,
    required this.visibleWeekStart,
    required this.isExpanded,
    required this.currentMonthForExpanded,
    required this.hasUserNavigatedWeek,
  });

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

  final DateTime selectedDate;
  final DateTime todayDate;
  final DateTime visibleWeekStart;
  final bool isExpanded;
  final DateTime currentMonthForExpanded;
  final bool hasUserNavigatedWeek;

  List<DateTime> get visibleWeekDates => List<DateTime>.generate(
    7,
    (index) => visibleWeekStart.add(Duration(days: index)),
    growable: false,
  );

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

class CalendarController extends StateNotifier<CalendarState> {
  CalendarController() : super(CalendarState.initial(DateTime.now())) {
    _scheduleDayBoundaryTick();
  }

  Timer? _dayBoundaryTimer;

  @override
  void dispose() {
    _dayBoundaryTimer?.cancel();
    super.dispose();
  }

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

  void toggleExpanded() {
    setExpanded(!state.isExpanded);
  }

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

  void _scheduleDayBoundaryTick() {
    _dayBoundaryTimer?.cancel();
    final now = DateTime.now();
    final nextDay = DateTime(now.year, now.month, now.day + 1);
    final wait = nextDay.difference(now) + const Duration(seconds: 1);
    _dayBoundaryTimer = Timer(wait, _handleDayBoundaryReached);
  }

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

DateTime _dateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

DateTime _startOfWeek(DateTime value) {
  final date = _dateOnly(value);
  final delta = (date.weekday - DateTime.monday) % 7;
  return date.subtract(Duration(days: delta));
}

bool _isSameDate(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}
