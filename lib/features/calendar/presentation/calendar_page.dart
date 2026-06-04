import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;

import '../../../app/preferences/app_preferences.dart';
import '../../tasks/data/task_repository.dart';
import '../../tasks/presentation/task_editor_page.dart';
import '../../tasks/presentation/widgets/task_card.dart';
import '../../tasks/presentation/widgets/task_details_sheet.dart';
import '../data/calendar_controller.dart';
import '../data/habit_controller.dart';

final calendarSubPageIndexProvider = StateProvider<int>((ref) => 0);

class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  static const double _calendarRowHeight = 52;
  static const double _expandVelocityThreshold = 420;
  static const double _expandDistanceRatioThreshold = 0.35;
  static const int _centerPage = 20000;
  static const Duration _pageAnimationDuration = Duration(milliseconds: 260);

  late final DateTime _baseWeekStart;
  late final PageController _pageController;
  late final PageController _subPageController;

  var _syncingFromState = false;
  double _dragPixels = 0;
  DateTime? _expandAnchorWeekStart;

  @override
  void initState() {
    super.initState();
    _baseWeekStart = ref.read(calendarControllerProvider).visibleWeekStart;
    _pageController = PageController(initialPage: _centerPage);
    _subPageController = PageController(
      initialPage: ref.read(calendarSubPageIndexProvider),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _subPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = ref.watch(appStringsProvider);
    final state = ref.watch(calendarControllerProvider);
    final anchorWeekStart = _expandAnchorWeekStart ?? state.visibleWeekStart;

    final month = DateTime(anchorWeekStart.year, anchorWeekStart.month, 1);
    final headerMonthKeys = _headerMonthKeys(state.visibleWeekStart);
    final monthMatrix = _buildMonthMatrix(month);
    final rowCount = monthMatrix.length;
    final weekRowIndex = _weekRowIndex(
      month,
      anchorWeekStart,
    ).clamp(0, rowCount - 1);

    ref.listen<DateTime>(
      calendarControllerProvider.select((value) => value.visibleWeekStart),
      (previous, next) {
        if (!_pageController.hasClients) {
          return;
        }
        final diffDays = next.difference(_baseWeekStart).inDays;
        final targetPage = _centerPage + (diffDays ~/ 7);
        final currentPage = _pageController.page?.round();
        if (currentPage == targetPage) {
          return;
        }
        _syncingFromState = true;
        _pageController
            .animateToPage(
              targetPage,
              duration: _pageAnimationDuration,
              curve: Curves.easeOutCubic,
            )
            .whenComplete(() => _syncingFromState = false);
      },
    );
    ref.listen<int>(calendarSubPageIndexProvider, (previous, next) {
      if (!_subPageController.hasClients ||
          _subPageController.page?.round() == next) {
        return;
      }
      _subPageController.animateToPage(
        next,
        duration: _pageAnimationDuration,
        curve: Curves.easeOutCubic,
      );
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDraggingExpand = _dragPixels != 0;
        final showExpandedGrid = state.isExpanded || isDraggingExpand;
        final showWeekPager = !showExpandedGrid;
        if (showWeekPager) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_pageController.hasClients) {
              return;
            }
            final diffDays = state.visibleWeekStart
                .difference(_baseWeekStart)
                .inDays;
            final targetPage = _centerPage + (diffDays ~/ 7);
            final currentPage = _pageController.page?.round();
            if (currentPage == targetPage) {
              return;
            }
            _syncingFromState = true;
            _pageController.jumpToPage(targetPage);
            _syncingFromState = false;
          });
        }
        final maxCalendarHeight = math.max(
          _calendarRowHeight,
          constraints.maxHeight - 140,
        );
        final expandedHeight = math.min(
          rowCount * _calendarRowHeight,
          maxCalendarHeight,
        );
        final collapsedHeight = _calendarRowHeight;
        final dragMin = state.isExpanded
            ? -(expandedHeight - collapsedHeight)
            : 0.0;
        final dragMax = state.isExpanded
            ? 0.0
            : (expandedHeight - collapsedHeight);
        final effectiveDrag = _dragPixels.clamp(dragMin, dragMax).toDouble();
        final baseHeight = state.isExpanded ? expandedHeight : collapsedHeight;
        final viewportHeight = (baseHeight + effectiveDrag).clamp(
          collapsedHeight,
          expandedHeight,
        ).toDouble();
        final expandProgress =
            ((viewportHeight - collapsedHeight) /
                    (expandedHeight - collapsedHeight).clamp(
                      1,
                      double.infinity,
                    ))
                .clamp(0.0, 1.0)
                .toDouble();
        final collapsedOffset = weekRowIndex * _calendarRowHeight;
        final topOffset = collapsedOffset * (1 - expandProgress);

        return Column(
          children: [
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _WeekdayHeaderRow(labels: strings.calendarWeekdayLabels),
                  const SizedBox(height: 8),
                  Stack(
                    children: [
                      Offstage(
                        offstage: !showExpandedGrid,
                        child: IgnorePointer(
                          ignoring: !showExpandedGrid,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Container(
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface.withValues(
                                  alpha: 0.55,
                                ),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: ClipRect(
                                child: SizedBox(
                                  height: viewportHeight,
                                  child: Transform.translate(
                                    offset: Offset(0, -topOffset),
                                    child: SizedBox(
                                      height: expandedHeight,
                                      child: _MonthGrid(
                                        monthMatrix: monthMatrix,
                                        selectedDate: state.selectedDate,
                                        todayDate: state.todayDate,
                                        highlightedMonthKeys: headerMonthKeys,
                                        onTapDate: (date) {
                                          ref
                                              .read(
                                                calendarControllerProvider
                                                    .notifier,
                                              )
                                              .selectDate(
                                                date,
                                                fromExpanded: true,
                                              );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Offstage(
                        offstage: !showWeekPager,
                        child: IgnorePointer(
                          ignoring: !showWeekPager,
                          child: SizedBox(
                            height: _calendarRowHeight,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface.withValues(
                                  alpha: 0.55,
                                ),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: PageView.builder(
                                  controller: _pageController,
                                  onPageChanged: (page) {
                                    if (_syncingFromState) {
                                      return;
                                    }
                                    final weekStart = _baseWeekStart.add(
                                      Duration(days: (page - _centerPage) * 7),
                                    );
                                    ref
                                        .read(
                                          calendarControllerProvider.notifier,
                                        )
                                        .setVisibleWeekStart(
                                          weekStart,
                                          fromUser: true,
                                        );
                                  },
                                  itemBuilder: (context, index) {
                                    final weekStart = _baseWeekStart.add(
                                      Duration(days: (index - _centerPage) * 7),
                                    );
                                    return _WeekRowOverlay(
                                      weekStart: weekStart,
                                      selectedDate: state.selectedDate,
                                      todayDate: state.todayDate,
                                      highlightedMonthKeys: headerMonthKeys,
                                      onTapDate: (date) {
                                        ref
                                            .read(
                                              calendarControllerProvider
                                                  .notifier,
                                            )
                                            .selectDate(date);
                                      },
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _ExpandHandle(
                    onVerticalDragStart: (_) {
                      _dragPixels = 0;
                      _expandAnchorWeekStart = state.visibleWeekStart;
                    },
                    onVerticalDragUpdate: (details) {
                      setState(() {
                        _dragPixels = (_dragPixels + details.delta.dy).clamp(
                          dragMin,
                          dragMax,
                        );
                      });
                    },
                    onVerticalDragEnd: (details) {
                      final velocity = details.primaryVelocity ?? 0;
                      final maxDistance = expandedHeight - collapsedHeight;
                      final draggedDistance = _dragPixels.abs();
                      final overDistanceThreshold =
                          draggedDistance >
                          maxDistance * _expandDistanceRatioThreshold;
                      final shouldExpand = state.isExpanded
                          ? !(velocity < -_expandVelocityThreshold ||
                                (overDistanceThreshold && _dragPixels < 0))
                          : (velocity > _expandVelocityThreshold ||
                                (overDistanceThreshold && _dragPixels > 0));
                      ref
                          .read(calendarControllerProvider.notifier)
                          .setExpanded(shouldExpand);
                      setState(() {
                        _dragPixels = 0;
                        _expandAnchorWeekStart = null;
                      });
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _subPageController,
                onPageChanged: (index) {
                  ref.read(calendarSubPageIndexProvider.notifier).state = index;
                },
                children: [
                  _CalendarTodoTab(selectedDate: state.selectedDate),
                  _CalendarHabitTab(selectedDate: state.selectedDate),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CalendarTodoTab extends ConsumerStatefulWidget {
  const _CalendarTodoTab({required this.selectedDate});

  final DateTime selectedDate;

  @override
  ConsumerState<_CalendarTodoTab> createState() => _CalendarTodoTabState();
}

class _CalendarTodoTabState extends ConsumerState<_CalendarTodoTab> {
  static const _completeAnimationDuration = Duration(milliseconds: 420);

  final _completingTaskIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(taskListProvider);
    final schedules = ref.watch(taskScheduleControllerProvider);
    final strings = ref.watch(appStringsProvider);

    return tasksAsync.when(
      data: (tasks) {
        final activeTaskIds = tasks
            .where((task) => task.status == TaskStatus.active.value)
            .map((task) => task.id)
            .toSet();
        final dayTasks =
            tasks
                .where(
                  (task) =>
                      task.status == TaskStatus.active.value &&
                      taskOccursOnDate(
                        task,
                        effectiveTaskSchedule(task, schedules),
                        widget.selectedDate,
                      ),
                )
                .toList()
              ..sort((left, right) => _compareCalendarTasks(
                    left,
                    right,
                    schedules,
                  ));
        _syncCompletingTaskIds(activeTaskIds);
        final weekCount = _taskCountInRange(
          tasks,
          schedules,
          _startOfWeek(widget.selectedDate),
          _startOfWeek(widget.selectedDate).add(const Duration(days: 6)),
        );
        final monthStart = DateTime(
          widget.selectedDate.year,
          widget.selectedDate.month,
        );
        final monthEnd = DateTime(
          widget.selectedDate.year,
          widget.selectedDate.month + 1,
          0,
        );
        final monthCount = _taskCountInRange(
          tasks,
          schedules,
          monthStart,
          monthEnd,
        );

        if (dayTasks.isEmpty) {
          return Column(
            children: [
              _CalendarTaskSummary(
                strings: strings,
                weekCount: weekCount,
                monthCount: monthCount,
              ),
              Expanded(
                child: _CalendarEmptyState(
                  icon: Icons.event_available_rounded,
                  title: strings.calendarNoTodoTitle,
                  body: strings.calendarNoTodoBody,
                ),
              ),
            ],
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          itemCount: dayTasks.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _CalendarTaskSummary(
                strings: strings,
                weekCount: weekCount,
                monthCount: monthCount,
              );
            }
            final task = dayTasks[index - 1];
            final isLast = index == dayTasks.length;
            final completing = _completingTaskIds.contains(task.id);
            return _CalendarCompletingTaskItem(
              key: ValueKey('calendar-task-${task.id}'),
              completing: completing,
              duration: _completeAnimationDuration,
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 6),
                child: TaskCard(
                  task: task,
                  strings: strings,
                  completionPreviewCompleted: completing ? true : null,
                  completionStrikeProgress: completing ? 1.0 : null,
                  onTap: () {
                    showTaskDetailsSheet(
                      context: context,
                      task: task,
                      strings: strings,
                    );
                  },
                  onEditTap: () {
                    Navigator.of(context).push(
                      buildTaskEditorRoute(
                        taskId: task.id,
                        initialValue: TaskEditorValue.fromTask(
                          task,
                          schedule: effectiveTaskSchedule(task, schedules),
                        ),
                      ),
                    );
                  },
                  onCompleteToggle: () => _completeTask(task),
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(strings.taskLoadFailed(error)),
        ),
      ),
    );
  }

  Future<void> _completeTask(Task task) async {
    if (_completingTaskIds.contains(task.id)) {
      return;
    }
    setState(() {
      _completingTaskIds.add(task.id);
    });

    await Future<void>.delayed(_completeAnimationDuration);
    if (!mounted) {
      return;
    }

    try {
      await ref.read(taskRepositoryProvider).completeTask(task);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _completingTaskIds.remove(task.id);
      });
    }
  }

  void _syncCompletingTaskIds(Set<String> activeTaskIds) {
    final finishedTaskIds = _completingTaskIds
        .where((taskId) => !activeTaskIds.contains(taskId))
        .toList(growable: false);
    if (finishedTaskIds.isEmpty) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _completingTaskIds.removeAll(finishedTaskIds);
      });
    });
  }
}

class _CalendarCompletingTaskItem extends StatelessWidget {
  const _CalendarCompletingTaskItem({
    super.key,
    required this.completing,
    required this.duration,
    required this.child,
  });

  final bool completing;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: duration,
      curve: Curves.easeInOutCubic,
      tween: Tween<double>(end: completing ? 1 : 0),
      builder: (context, progress, child) {
        final opacity = (1 - (progress / 0.58)).clamp(0.0, 1.0).toDouble();
        final collapseProgress = ((progress - 0.42) / 0.58)
            .clamp(0.0, 1.0)
            .toDouble();
        final heightFactor = (1 - collapseProgress).clamp(0.0, 1.0).toDouble();

        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: heightFactor,
            child: Opacity(opacity: opacity, child: child),
          ),
        );
      },
      child: child,
    );
  }
}

class _CalendarHabitTab extends ConsumerWidget {
  const _CalendarHabitTab({required this.selectedDate});

  final DateTime selectedDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final habits = ref.watch(habitControllerProvider);

    if (habits.isEmpty) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: _CalendarAddHabitButton(strings: strings, onTap: () {
              _showHabitEditor(context, ref, strings);
            }),
          ),
          Expanded(
            child: _CalendarEmptyState(
              icon: Icons.check_circle_outline_rounded,
              title: strings.habitsEmptyTitle,
              body: strings.habitsEmptyBody,
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      itemCount: habits.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _CalendarAddHabitButton(
            strings: strings,
            onTap: () => _showHabitEditor(context, ref, strings),
          );
        }
        final habit = habits[index - 1];
        return Padding(
          padding: EdgeInsets.only(bottom: index == habits.length ? 0 : 6),
          child: _HabitCard(
            habit: habit,
            checked: habit.isCheckedOn(selectedDate),
            strings: strings,
            onToggle: () {
              ref
                  .read(habitControllerProvider.notifier)
                  .toggleCheck(habit.id, selectedDate);
            },
          ),
        );
      },
    );
  }
}

class _CalendarAddHabitButton extends StatelessWidget {
  const _CalendarAddHabitButton({required this.strings, required this.onTap});

  final AppStrings strings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.add_rounded),
        label: Text(strings.addHabit),
      ),
    );
  }
}

class _HabitCard extends StatelessWidget {
  const _HabitCard({
    required this.habit,
    required this.checked,
    required this.strings,
    required this.onToggle,
  });

  final HabitEntry habit;
  final bool checked;
  final AppStrings strings;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final darkMode = theme.brightness == Brightness.dark;
    final selectedTone = darkMode
        ? const Color(0xFFA8D4C5)
        : const Color(0xFF33544B);
    return SizedBox(
      height: TaskCard.height,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onToggle,
          child: Ink(
            padding: const EdgeInsets.fromLTRB(12, 0, 14, 0),
            decoration: BoxDecoration(
              color: darkMode
                  ? const Color(0xFF202822).withValues(alpha: 0.96)
                  : Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: darkMode
                    ? const Color(0xFF354239)
                    : const Color(0xFFE8DED0),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  checked
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: checked ? selectedTone : theme.iconTheme.color,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    habit.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  checked ? strings.checkedIn : strings.notCheckedIn,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: checked ? selectedTone : theme.hintColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarEmptyState extends StatelessWidget {
  const _CalendarEmptyState({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final darkMode = theme.brightness == Brightness.dark;
    final iconColor = darkMode
        ? const Color(0xFFA8D4C5)
        : const Color(0xFF4E6C61);

    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 22, 32, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: iconColor),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarTaskSummary extends StatelessWidget {
  const _CalendarTaskSummary({
    required this.strings,
    required this.weekCount,
    required this.monthCount,
  });

  final AppStrings strings;
  final int weekCount;
  final int monthCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: _SummaryPill(
              label: strings.weekSummary,
              value: strings.itemCount(weekCount),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _SummaryPill(
              label: strings.monthSummary,
              value: strings.itemCount(monthCount),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Text(label, style: theme.textTheme.labelLarge),
          const Spacer(),
          Text(
            value,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showHabitEditor(
  BuildContext context,
  WidgetRef ref,
  AppStrings strings,
) async {
  final controller = TextEditingController();
  String? errorText;
  final created = await showDialog<String>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(strings.addHabit),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 30,
              decoration: InputDecoration(
                labelText: strings.habitTitle,
                errorText: errorText,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(strings.cancel),
              ),
              FilledButton(
                onPressed: () {
                  final value = controller.text.trim();
                  if (value.isEmpty) {
                    setDialogState(() => errorText = strings.habitRequired);
                    return;
                  }
                  Navigator.of(context).pop(value);
                },
                child: Text(strings.save),
              ),
            ],
          );
        },
      );
    },
  );
  controller.dispose();
  if (created == null) {
    return;
  }
  await ref.read(habitControllerProvider.notifier).createHabit(title: created);
}

class _WeekdayHeaderRow extends StatelessWidget {
  const _WeekdayHeaderRow({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700);
    return Row(
      children: [
        for (final label in labels)
          Expanded(
            child: Center(child: Text(label, style: style)),
          ),
      ],
    );
  }
}

class _WeekRowOverlay extends StatelessWidget {
  const _WeekRowOverlay({
    required this.weekStart,
    required this.selectedDate,
    required this.todayDate,
    required this.highlightedMonthKeys,
    required this.onTapDate,
  });

  final DateTime weekStart;
  final DateTime selectedDate;
  final DateTime todayDate;
  final Set<int> highlightedMonthKeys;
  final ValueChanged<DateTime> onTapDate;

  @override
  Widget build(BuildContext context) {
    final dates = List<DateTime>.generate(
      7,
      (index) => weekStart.add(Duration(days: index)),
      growable: false,
    );
    return Row(
      children: [
        for (final date in dates)
          Expanded(
            child: _DateCell(
              date: date,
              inHighlightedMonths: highlightedMonthKeys.contains(
                _monthKey(date),
              ),
              isSelected: _isSameDate(date, selectedDate),
              isToday: _isSameDate(date, todayDate),
              onTap: () => onTapDate(date),
            ),
          ),
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.monthMatrix,
    required this.selectedDate,
    required this.todayDate,
    required this.highlightedMonthKeys,
    required this.onTapDate,
  });

  final List<List<DateTime>> monthMatrix;
  final DateTime selectedDate;
  final DateTime todayDate;
  final Set<int> highlightedMonthKeys;
  final ValueChanged<DateTime> onTapDate;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        for (var rowIndex = 0; rowIndex < monthMatrix.length; rowIndex++)
          Positioned(
            top: rowIndex * _CalendarPageState._calendarRowHeight,
            left: 0,
            right: 0,
            height: _CalendarPageState._calendarRowHeight,
            child: Row(
              children: [
                for (final date in monthMatrix[rowIndex])
                  Expanded(
                    child: _DateCell(
                      date: date,
                      inHighlightedMonths: highlightedMonthKeys.contains(
                        _monthKey(date),
                      ),
                      isSelected: _isSameDate(date, selectedDate),
                      isToday: _isSameDate(date, todayDate),
                      onTap: () => onTapDate(date),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DateCell extends StatelessWidget {
  const _DateCell({
    required this.date,
    required this.inHighlightedMonths,
    required this.isSelected,
    required this.isToday,
    required this.onTap,
  });

  final DateTime date;
  final bool inHighlightedMonths;
  final bool isSelected;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final darkMode = theme.brightness == Brightness.dark;
    final selectedBackground = darkMode
        ? const Color(0xFFA8D4C5)
        : const Color(0xFF33544B);
    final selectedText = darkMode ? const Color(0xFF10231E) : Colors.white;
    final todayBackground = darkMode
        ? const Color(0xFF2D4A40)
        : const Color(0xFFDCEBE5);
    final todayText = darkMode
        ? const Color(0xFFCFE9DE)
        : const Color(0xFF2D4C43);
    final defaultText = theme.textTheme.titleMedium?.color;
    final outOfMonthText = (defaultText ?? Colors.black).withValues(
      alpha: 0.42,
    );

    final decoration = isSelected
        ? BoxDecoration(color: selectedBackground, shape: BoxShape.circle)
        : isToday
        ? BoxDecoration(color: todayBackground, shape: BoxShape.circle)
        : const BoxDecoration(shape: BoxShape.circle);
    final textColor = isSelected
        ? selectedText
        : isToday
        ? todayText
        : (inHighlightedMonths ? defaultText : outOfMonthText);

    return Center(
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: 40,
          height: 40,
          decoration: decoration,
          alignment: Alignment.center,
          child: Text(
            '${date.day}',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpandHandle extends StatelessWidget {
  const _ExpandHandle({
    required this.onVerticalDragStart,
    required this.onVerticalDragUpdate,
    required this.onVerticalDragEnd,
  });

  final GestureDragStartCallback onVerticalDragStart;
  final GestureDragUpdateCallback onVerticalDragUpdate;
  final GestureDragEndCallback onVerticalDragEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: onVerticalDragStart,
      onVerticalDragUpdate: onVerticalDragUpdate,
      onVerticalDragEnd: onVerticalDragEnd,
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
          width: 42,
          height: 4,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.all(Radius.circular(999)),
            ),
          ),
        ),
      ),
    );
  }
}

List<List<DateTime>> _buildMonthMatrix(DateTime month) {
  final firstDay = DateTime(month.year, month.month, 1);
  final lastDay = DateTime(month.year, month.month + 1, 0);
  final gridStart = _startOfWeek(firstDay);
  final gridEnd = _startOfWeek(lastDay).add(const Duration(days: 6));
  final dayCount = gridEnd.difference(gridStart).inDays + 1;
  final allDates = List<DateTime>.generate(
    dayCount,
    (index) => gridStart.add(Duration(days: index)),
    growable: false,
  );
  final rows = <List<DateTime>>[];
  for (var i = 0; i < allDates.length; i += 7) {
    rows.add(allDates.sublist(i, i + 7));
  }
  return rows;
}

int _weekRowIndex(DateTime month, DateTime visibleWeekStart) {
  final monthFirst = DateTime(month.year, month.month, 1);
  final gridStart = _startOfWeek(monthFirst);
  return math.max(0, visibleWeekStart.difference(gridStart).inDays ~/ 7);
}

DateTime _startOfWeek(DateTime value) {
  final date = DateTime(value.year, value.month, value.day);
  final delta = (date.weekday - DateTime.monday) % 7;
  return date.subtract(Duration(days: delta));
}

bool _isSameDate(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

int _compareCalendarTasks(
  Task left,
  Task right,
  Map<String, TaskScheduleMetadata> schedules,
) {
  final leftSchedule = effectiveTaskSchedule(left, schedules);
  final rightSchedule = effectiveTaskSchedule(right, schedules);
  final leftDueAt = leftSchedule.sortAt ?? left.dueAt;
  final rightDueAt = rightSchedule.sortAt ?? right.dueAt;
  if (leftDueAt != null && rightDueAt != null) {
    final dueComparison = leftDueAt.compareTo(rightDueAt);
    if (dueComparison != 0) {
      return dueComparison;
    }
  }
  final orderComparison = left.sortOrder.compareTo(right.sortOrder);
  if (orderComparison != 0) {
    return orderComparison;
  }
  return right.updatedAt.compareTo(left.updatedAt);
}

int _taskCountInRange(
  List<Task> tasks,
  Map<String, TaskScheduleMetadata> schedules,
  DateTime start,
  DateTime end,
) {
  var count = 0;
  var cursor = DateTime(start.year, start.month, start.day);
  final endDate = DateTime(end.year, end.month, end.day);
  while (!cursor.isAfter(endDate)) {
    count += tasks.where((task) {
      if (task.status != TaskStatus.active.value) {
        return false;
      }
      return taskOccursOnDate(
        task,
        effectiveTaskSchedule(task, schedules),
        cursor,
      );
    }).length;
    cursor = cursor.add(const Duration(days: 1));
  }
  return count;
}

Set<int> _headerMonthKeys(DateTime visibleWeekStart) {
  final first = visibleWeekStart;
  final last = visibleWeekStart.add(const Duration(days: 6));
  return {_monthKey(first), _monthKey(last)};
}

int _monthKey(DateTime value) {
  return value.year * 100 + value.month;
}
