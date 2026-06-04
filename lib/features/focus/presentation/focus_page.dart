/*
 * 专注页（Focus）主界面。
 *
 * 这个文件负责专注模块完整前端呈现，包含两大子页面：
 * 1. 番茄钟页：模式切换、圆盘计时器、开始/暂停/重置、纯专注入口、常用时长管理。
 * 2. 数据统计页：指标卡、趋势线、热力图、时段分布等统计可视化。
 *
 * 组件组织原则：
 * - 页面结构组件（FocusPage / _PomodoroTab / _StatisticsTab）负责布局与交互。
 * - 图形组件（Painter / Chart / Heatmap）负责专注可视化绘制。
 * - 纯专注页负责沉浸显示与横屏状态控制。
 */
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:intl/intl.dart';

import '../../../app/preferences/app_preferences.dart';
import '../../../app/widgets/app_notice.dart';
import '../../../app/widgets/wheel_picker.dart';
import '../../tasks/data/task_repository.dart';
import '../data/focus_controller.dart';

/// 专注页子页面索引。
///
/// `0` 为番茄钟，`1` 为数据统计。顶部信息栏和页面滑动通过它保持同步。
final focusSubPageIndexProvider = StateProvider<int>((ref) => 0);

/// 专注模块主页面容器。
///
/// 它本身不直接渲染内容，而是承载两个横向可滑动子页。
class FocusPage extends ConsumerStatefulWidget {
  const FocusPage({super.key});

  @override
  ConsumerState<FocusPage> createState() => _FocusPageState();
}

/// 专注页面状态。
///
/// 管理 PageView 控制器，并同步顶部 tab 和横向滑动状态。
class _FocusPageState extends ConsumerState<FocusPage> {
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      initialPage: ref.read(focusSubPageIndexProvider),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(focusSubPageIndexProvider, (previous, next) {
      if (!_pageController.hasClients ||
          _pageController.page?.round() == next) {
        return;
      }
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
    ref.listen<int>(
      focusControllerProvider.select((state) => state.completionSignal),
      (previous, next) {
        if ((previous ?? 0) == next) {
          return;
        }
        final strings = ref.read(appStringsProvider);
        TaskNetNotice.showInfo(context, strings.focusCompleted);
      },
    );

    return PageView(
      controller: _pageController,
      onPageChanged: (index) {
        ref.read(focusSubPageIndexProvider.notifier).state = index;
      },
      // children[0]：番茄钟；children[1]：数据统计。
      children: const [_PomodoroTab(), _StatisticsTab()],
    );
  }
}

/// 番茄钟子页面。
///
/// 主要由三块 children 组成：
/// - 模式切换器（倒计时/正计时）。
/// - 中央圆盘计时器。
/// - 底部动作按钮行（开始/暂停、重置、纯专注）。
class _PomodoroTab extends ConsumerWidget {
  const _PomodoroTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final state = ref.watch(focusControllerProvider);
    final controller = ref.read(focusControllerProvider.notifier);
    final tasks = ref.watch(taskListProvider).maybeWhen(
          data: (items) => items,
          orElse: () => const <Task>[],
        );
    final activeTasks = tasks
        .where((task) => task.status == TaskStatus.active.value)
        .toList(growable: false);
    final selectedTask = _taskById(tasks, state.currentTaskId);
    final selectedTaskTitle =
        selectedTask?.title ?? state.currentTaskTitle ?? strings.noFocusTask;
    final timerDisplay = _formatTimer(
      state.mode == FocusTimerMode.countdown ? state.remaining : state.elapsed,
      showHourAlways: state.mode == FocusTimerMode.countup,
    );
    final primaryLabel = switch (state.runState) {
      FocusRunState.idle => strings.start,
      FocusRunState.running => strings.pause,
      FocusRunState.paused => strings.resume,
    };
    final primaryIcon = switch (state.runState) {
      FocusRunState.idle => Icons.play_arrow_rounded,
      FocusRunState.running => Icons.pause_rounded,
      FocusRunState.paused => Icons.play_arrow_rounded,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isLandscape = constraints.maxWidth > constraints.maxHeight;
          final maxDialWidth = isLandscape
              ? constraints.maxWidth * 0.42
              : constraints.maxWidth * 0.86;
          final maxDialHeight = isLandscape
              ? constraints.maxHeight * 0.56
              : constraints.maxHeight * 0.58;
          final dialSize = min(
            320.0,
            min(maxDialWidth, maxDialHeight),
          ).clamp(180.0, 320.0).toDouble();

          final modeSwitcher = SegmentedButton<FocusTimerMode>(
            segments: [
              ButtonSegment<FocusTimerMode>(
                value: FocusTimerMode.countdown,
                label: Text(strings.countdownMode),
              ),
              ButtonSegment<FocusTimerMode>(
                value: FocusTimerMode.countup,
                label: Text(strings.countupMode),
              ),
            ],
            selected: {state.mode},
            onSelectionChanged: (selection) {
              final selectedMode = selection.first;
              controller.setMode(selectedMode);
            },
          );
          final taskSelector = _FocusTaskSelector(
            label: strings.currentFocusTask,
            title: selectedTaskTitle,
            isBound: state.currentTaskId != null,
            onTap: () => _showFocusTaskPicker(
              context: context,
              ref: ref,
              tasks: activeTasks,
              strings: strings,
              selectedTaskId: state.currentTaskId,
            ),
          );
          final dial = Center(
            child: _PomodoroDial(
              timerDisplay: timerDisplay,
              mode: state.mode,
              runState: state.runState,
              progress: _dialProgress(state),
              subtitle: state.mode == FocusTimerMode.countdown
                  ? strings.durationPickerTitle
                  : strings.countupMode,
              dialSize: dialSize,
              onTap:
                  state.mode == FocusTimerMode.countdown &&
                      state.canEditDuration
                  ? () => _showDurationPicker(context: context, ref: ref)
                  : null,
            ),
          );
          final actions = Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _FocusActionIconButton(
                tooltip: primaryLabel,
                icon: primaryIcon,
                filled: true,
                onPressed: () {
                  if (state.runState == FocusRunState.running) {
                    controller.pause();
                  } else {
                    controller.startOrResume();
                  }
                },
              ),
              const SizedBox(width: 18),
              _FocusActionIconButton(
                tooltip: strings.reset,
                icon: Icons.replay_rounded,
                filled: false,
                onPressed: controller.reset,
              ),
              const SizedBox(width: 18),
              _FocusActionIconButton(
                tooltip: strings.pureFocusMode,
                icon: Icons.fullscreen_rounded,
                filled: false,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const _PureFocusPage(),
                    ),
                  );
                },
              ),
            ],
          );

          if (isLandscape) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 1) 顶部模式切换：倒计时 / 正计时。
                    modeSwitcher,
                    const SizedBox(height: 10),
                    taskSelector,
                    const SizedBox(height: 12),
                    // 2) 中央圆盘：显示当前计时与进度。
                    dial,
                    const SizedBox(height: 14),
                    // 3) 底部操作按钮：开始/暂停、重置、纯专注。
                    actions,
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            );
          }

          return Column(
            children: [
              // 竖屏布局同样保持“模式 -> 圆盘 -> 操作”的阅读顺序。
              modeSwitcher,
              const SizedBox(height: 10),
              taskSelector,
              const SizedBox(height: 14),
              Expanded(child: dial),
              const SizedBox(height: 16),
              actions,
            ],
          );
        },
      ),
    );
  }

  Future<void> _showDurationPicker({
    required BuildContext context,
    required WidgetRef ref,
  }) async {
    final strings = ref.read(appStringsProvider);
    final controller = ref.read(focusControllerProvider.notifier);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Consumer(
          builder: (context, bottomRef, _) {
            final durations = bottomRef.watch(
              focusControllerProvider.select((state) => state.commonDurations),
            );
            final selectedMinutes = bottomRef.watch(
              focusControllerProvider.select((state) => state.countdownMinutes),
            );
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          strings.commonDurations,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        tooltip: strings.addDuration,
                        onPressed: () async {
                          final created = await _showDurationEditorDialog(
                            context: context,
                            strings: strings,
                            existingDurations: durations,
                            title: strings.addDuration,
                          );
                          if (created == null) {
                            return;
                          }
                          final success = controller.addCommonDuration(created);
                          if (!success && context.mounted) {
                            TaskNetNotice.showInfo(
                              context,
                              strings.durationAlreadyExists,
                            );
                          }
                        },
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final duration in durations)
                        GestureDetector(
                          onLongPress: () async {
                            final action = await _showDurationActionsSheet(
                              context: context,
                              strings: strings,
                              duration: duration,
                            );
                            if (!context.mounted) {
                              return;
                            }
                            if (action == _DurationAction.edit) {
                              final updated = await _showDurationEditorDialog(
                                context: context,
                                strings: strings,
                                existingDurations: durations
                                    .where((item) => item != duration)
                                    .toList(growable: false),
                                title: strings.editDuration,
                                initialMinutes: duration,
                              );
                              if (updated != null) {
                                final success = controller.updateCommonDuration(
                                  oldMinutes: duration,
                                  newMinutes: updated,
                                );
                                if (!success && context.mounted) {
                                  TaskNetNotice.showInfo(
                                    context,
                                    strings.durationAlreadyExists,
                                  );
                                }
                              }
                              return;
                            }
                            if (action == _DurationAction.delete) {
                              controller.removeCommonDuration(duration);
                            }
                          },
                          child: ChoiceChip(
                            label: Text(_formatDurationOption(duration)),
                            selected: duration == selectedMinutes,
                            onSelected: (_) {
                              controller.selectCountdownMinutes(duration);
                              Navigator.of(context).pop();
                            },
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// 数据统计子页面。
///
/// ListView children 由多个统计卡片构成：
/// - 基础指标卡
/// - 效率概览卡
/// - 14 天曲线图卡
/// - 12 周热力图卡
/// - 时段分布卡
class _FocusTaskSelector extends StatelessWidget {
  const _FocusTaskSelector({
    required this.label,
    required this.title,
    required this.isBound,
    required this.onTap,
  });

  final String label;
  final String title;
  final bool isBound;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final darkMode = theme.brightness == Brightness.dark;
    final borderColor = darkMode
        ? const Color(0xFF385047)
        : const Color(0xFFD8CDBF);
    final iconColor = darkMode
        ? const Color(0xFFA8D4C5)
        : const Color(0xFF33544B);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
          decoration: BoxDecoration(
            color: darkMode
                ? const Color(0xFF202822).withValues(alpha: 0.88)
                : Colors.white.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Icon(
                isBound ? Icons.link_rounded : Icons.link_off_rounded,
                size: 20,
                color: iconColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: theme.textTheme.labelSmall),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.keyboard_arrow_down_rounded, color: iconColor),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showFocusTaskPicker({
  required BuildContext context,
  required WidgetRef ref,
  required List<Task> tasks,
  required AppStrings strings,
  required String? selectedTaskId,
}) async {
  final controller = ref.read(focusControllerProvider.notifier);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 18),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(
                strings.chooseFocusTask,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.link_off_rounded),
              title: Text(strings.noFocusTask),
              selected: selectedTaskId == null,
              onTap: () {
                controller.setCurrentTask();
                Navigator.of(context).pop();
              },
            ),
            for (final task in tasks)
              ListTile(
                leading: Icon(
                  task.id == selectedTaskId
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                ),
                title: Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: task.label == null
                    ? null
                    : Text(strings.taskLabelName(task.label!)),
                selected: task.id == selectedTaskId,
                onTap: () {
                  controller.setCurrentTask(taskId: task.id, title: task.title);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      );
    },
  );
}

Task? _taskById(List<Task> tasks, String? taskId) {
  if (taskId == null) {
    return null;
  }
  for (final task in tasks) {
    if (task.id == taskId) {
      return task;
    }
  }
  return null;
}

class _StatisticsTab extends ConsumerWidget {
  const _StatisticsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final sessions = ref.watch(
      focusControllerProvider.select((state) => state.sessions),
    );
    final stats = _FocusStatsData.fromSessions(sessions);
    final tasks = ref.watch(taskListProvider).maybeWhen(
          data: (items) => items,
          orElse: () => const <Task>[],
        );
    final taskStats = _TaskStatsData.fromTasks(tasks, sessions);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _TaskStatsCard(strings: strings, stats: taskStats),
        const SizedBox(height: 12),
        // 无数据时显示空状态卡片。
        if (sessions.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Text(strings.noStatsYet),
            ),
          )
        else ...[
          // 卡片 1：基础累计指标（今日、总时长、会话数等）。
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _SimpleMetricTile(
                    title: strings.todayFocusTime,
                    value: _formatDurationHhMm(stats.todayFocus),
                  ),
                  _SimpleMetricTile(
                    title: strings.totalFocusTime,
                    value: _formatDurationHhMm(stats.totalFocus),
                  ),
                  _SimpleMetricTile(
                    title: strings.completedSessions,
                    value: '${stats.completedSessions}',
                  ),
                  _SimpleMetricTile(
                    title: strings.interruptedSessions,
                    value: '${stats.interruptedSessions}',
                  ),
                  _SimpleMetricTile(
                    title: strings.longestSession,
                    value: _formatDurationHhMm(stats.longestSession),
                  ),
                  _SimpleMetricTile(
                    title: strings.countdownSessions,
                    value: '${stats.countdownSessions}',
                  ),
                  _SimpleMetricTile(
                    title: strings.countupSessions,
                    value: '${stats.countupSessions}',
                  ),
                  _SimpleMetricTile(
                    title: strings.recent7Days,
                    value: _formatDurationHhMm(stats.recent7DaysTotal),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 卡片 2：效率概览（平均时长、完成率、连续天数等）。
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.focusOverview,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _SimpleMetricTile(
                        title: strings.averageSession,
                        value: _formatDurationHhMm(stats.averageSession),
                      ),
                      _SimpleMetricTile(
                        title: strings.completionRate,
                        value:
                            '${(stats.completionRate * 100).toStringAsFixed(0)}%',
                      ),
                      _SimpleMetricTile(
                        title: strings.activeDays,
                        value: '${stats.activeDaysIn7Days}/7',
                      ),
                      _SimpleMetricTile(
                        title: strings.currentStreak,
                        value: '${stats.currentStreakDays}',
                      ),
                      _SimpleMetricTile(
                        title: strings.thisWeekSessions,
                        value: '${stats.sessionsThisWeek}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 卡片 3：14 天趋势折线图。
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.focusCurve14Days,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 164,
                    child: _FocusLineChart(
                      items: stats.recent14Days,
                      accentColor: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 卡片 4：12 周热力图。
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.focusHeatmap12Weeks,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _FocusHeatmap(
                    items: stats.recent84Days,
                    maxValue: stats.maxHeatmapDuration,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 卡片 5：时段分布与最活跃时段。
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.timeDistribution,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...stats.distributions.entries.map((entry) {
                    final value = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _TrendRow(
                        label: _periodLabel(strings, entry.key),
                        value: value,
                        maxValue: stats.maxDistributionValue,
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  Text(
                    '${strings.mostActivePeriod}: ${_periodLabel(strings, stats.mostActivePeriod)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 番茄钟中央圆盘组件。
///
/// Stack children 对应关系：
/// - children[0]：外圈刻度。
/// - children[1]：进度弧与进度点。
/// - children[2]：中心圆盘文本（时间/副标题/运行状态）。
class _PomodoroDial extends StatelessWidget {
  const _PomodoroDial({
    required this.timerDisplay,
    required this.mode,
    required this.runState,
    required this.progress,
    required this.subtitle,
    required this.dialSize,
    this.onTap,
  });

  final String timerDisplay;
  final FocusTimerMode mode;
  final FocusRunState runState;
  final double progress;
  final String subtitle;
  final double dialSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final darkMode = Theme.of(context).brightness == Brightness.dark;
    final ringColor = darkMode
        ? const Color(0xFFA8D4C5)
        : const Color(0xFF476C63);
    final coreColor = darkMode
        ? const Color(0xFF1A221D)
        : const Color(0xFFFFFCF7);

    return Center(
      child: SizedBox.square(
        dimension: dialSize,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 外圈刻度盘，营造钟表结构感。
              CustomPaint(
                size: Size.square(dialSize),
                painter: _DialTicksPainter(
                  tickColor: darkMode
                      ? const Color(0xFF365548)
                      : const Color(0xFFDACEBE),
                ),
              ),
              // 进度圈层：依据计时进度做补间动画。
              TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                tween: Tween<double>(
                  begin: 0,
                  end: progress.clamp(0.0, 1.0).toDouble(),
                ),
                builder: (context, animatedProgress, child) {
                  return CustomPaint(
                    size: Size.square(dialSize * 0.84),
                    painter: _DialFacePainter(
                      progress: animatedProgress,
                      ringColor: ringColor,
                      trackColor: darkMode
                          ? const Color(0xFF2A3A33)
                          : const Color(0xFFE6DCCD),
                      isRunning: runState == FocusRunState.running,
                    ),
                  );
                },
              ),
              // 中心实心圆与文本信息层。
              Container(
                width: dialSize * 0.653,
                height: dialSize * 0.653,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: coreColor,
                  border: Border.all(
                    color: darkMode
                        ? const Color(0xFF2C3933)
                        : const Color(0xFFE7DCCB),
                    width: 1.2,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      timerDisplay,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.3,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      switch (runState) {
                        FocusRunState.idle =>
                          mode == FocusTimerMode.countdown
                              ? 'READY'
                              : 'TRACKING',
                        FocusRunState.running => 'RUNNING',
                        FocusRunState.paused => 'PAUSED',
                      },
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 番茄钟底部圆形图标按钮。
class _FocusActionIconButton extends StatelessWidget {
  const _FocusActionIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    required this.filled,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final darkMode = theme.brightness == Brightness.dark;
    final borderColor = darkMode
        ? const Color(0xFF385047)
        : const Color(0xFFD8CDBF);
    final filledColor = darkMode
        ? const Color(0xFFA8D4C5)
        : const Color(0xFF33544B);
    final iconColor = filled
        ? (darkMode ? const Color(0xFF15201B) : Colors.white)
        : (darkMode ? const Color(0xFFDDE7E1) : const Color(0xFF33544B));

    return Tooltip(
      message: tooltip,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? filledColor : Colors.transparent,
          border: Border.all(color: borderColor),
        ),
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, color: iconColor, size: 30),
        ),
      ),
    );
  }
}

/// 纯专注沉浸页（黑底大字时间）。
///
/// 在计时进行中可进入本页，点击任意区域切换右上角退出按钮显隐。
class _PureFocusPage extends ConsumerStatefulWidget {
  const _PureFocusPage();

  @override
  ConsumerState<_PureFocusPage> createState() => _PureFocusPageState();
}

/// 纯专注页状态。
///
/// 负责：
/// - 进入时设置横屏与系统 UI 模式。
/// - 退出时恢复方向策略。
/// - 4 秒无操作自动隐藏退出按钮。
class _PureFocusPageState extends ConsumerState<_PureFocusPage> {
  Timer? _autoHideTimer;
  var _showExitButton = true;

  @override
  void initState() {
    super.initState();
    unawaited(_enterPureFocusMode());
    _restartAutoHideTimer();
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    unawaited(_exitPureFocusMode());
    super.dispose();
  }

  Future<void> _enterPureFocusMode() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _exitPureFocusMode() async {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _restartAutoHideTimer() {
    _autoHideTimer?.cancel();
    _autoHideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) {
        return;
      }
      setState(() => _showExitButton = false);
    });
  }

  void _toggleExitButton() {
    setState(() => _showExitButton = !_showExitButton);
    if (_showExitButton) {
      _restartAutoHideTimer();
    } else {
      _autoHideTimer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final state = ref.watch(focusControllerProvider);
    final timerDisplay = _formatTimer(
      state.mode == FocusTimerMode.countdown ? state.remaining : state.elapsed,
      showHourAlways: true,
    );
    final mediaPadding = MediaQuery.paddingOf(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleExitButton,
          child: Stack(
            children: [
              // 中央超大时间文本层（始终可见）。
              Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SizedBox(
                      width: constraints.maxWidth * 0.92,
                      height: constraints.maxHeight * 0.78,
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: Text(
                          timerDisplay,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 320,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              // 右上角退出按钮层（可自动隐藏）。
              Positioned(
                top: mediaPadding.top + 8,
                right: 8,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: _showExitButton ? 1 : 0,
                  child: IgnorePointer(
                    ignoring: !_showExitButton,
                    child: IconButton.filledTonal(
                      onPressed: () => Navigator.of(context).pop(),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.16),
                        foregroundColor: Colors.white,
                      ),
                      tooltip: strings.exitPureFocus,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                ),
              ),
              if (state.currentTaskTitle != null &&
                  state.currentTaskTitle!.isNotEmpty)
                Positioned(
                  left: mediaPadding.left + 24,
                  bottom: mediaPadding.bottom + 20,
                  right: mediaPadding.right + 24,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    opacity: _showExitButton ? 1 : 0,
                    child: Text(
                      state.currentTaskTitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 圆盘进度层绘制器（轨道、进度弧、进度端点）。
class _DialFacePainter extends CustomPainter {
  const _DialFacePainter({
    required this.progress,
    required this.ringColor,
    required this.trackColor,
    required this.isRunning,
  });

  final double progress;
  final Color ringColor;
  final Color trackColor;
  final bool isRunning;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = 16.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth
      ..color = trackColor;
    canvas.drawCircle(center, radius, trackPaint);

    final activePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth
      ..color = ringColor.withValues(alpha: isRunning ? 1 : 0.8);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5708,
      6.2831 * progress,
      false,
      activePaint,
    );

    if (progress > 0) {
      final angle = -1.5708 + 6.2831 * progress;
      final indicator = Offset(
        center.dx + radius * cos(angle),
        center.dy + radius * sin(angle),
      );
      final indicatorPaint = Paint()..color = ringColor;
      canvas.drawCircle(indicator, 7, indicatorPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DialFacePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.ringColor != ringColor ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.isRunning != isRunning;
  }
}

/// 圆盘刻度绘制器（60 个刻度，每 5 格一个长刻度）。
class _DialTicksPainter extends CustomPainter {
  const _DialTicksPainter({required this.tickColor});

  final Color tickColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;
    for (var i = 0; i < 60; i++) {
      final angle = -1.5708 + (6.2831 / 60) * i;
      final longTick = i % 5 == 0;
      final tickLength = longTick ? 11.0 : 6.0;
      final start = Offset(
        center.dx + (outerRadius - tickLength) * cos(angle),
        center.dy + (outerRadius - tickLength) * sin(angle),
      );
      final end = Offset(
        center.dx + outerRadius * cos(angle),
        center.dy + outerRadius * sin(angle),
      );
      final tickPaint = Paint()
        ..color = tickColor.withValues(alpha: longTick ? 0.95 : 0.6)
        ..strokeWidth = longTick ? 2 : 1.2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(start, end, tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DialTicksPainter oldDelegate) {
    return oldDelegate.tickColor != tickColor;
  }
}

/// 14 天趋势图容器组件。
class _FocusLineChart extends StatelessWidget {
  const _FocusLineChart({required this.items, required this.accentColor});

  final List<_DailyFocusDuration> items;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final maxValue = items.fold<Duration>(
      Duration.zero,
      (max, item) => item.duration > max ? item.duration : max,
    );
    return CustomPaint(
      painter: _FocusLineChartPainter(
        items: items,
        maxValue: maxValue,
        accentColor: accentColor,
        gridColor: Theme.of(context).dividerColor.withValues(alpha: 0.45),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // 左侧起始日期标签。
            Text(
              DateFormat('MM/dd').format(items.first.day),
              style: Theme.of(context).textTheme.labelSmall,
            ),
            // 右侧结束日期标签。
            Text(
              DateFormat('MM/dd').format(items.last.day),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// 趋势图绘制器（网格、面积填充、折线、采样点）。
class _FocusLineChartPainter extends CustomPainter {
  const _FocusLineChartPainter({
    required this.items,
    required this.maxValue,
    required this.accentColor,
    required this.gridColor,
  });

  final List<_DailyFocusDuration> items;
  final Duration maxValue;
  final Color accentColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (items.length < 2) {
      return;
    }
    final left = 4.0;
    final right = size.width - 4.0;
    final top = 8.0;
    final bottom = size.height - 24.0;
    final usableHeight = bottom - top;
    final span = items.length - 1;
    final maxSeconds = max(maxValue.inSeconds, 1);

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = top + (usableHeight / 3) * i;
      canvas.drawLine(Offset(left, y), Offset(right, y), gridPaint);
    }

    final points = <Offset>[];
    for (var i = 0; i < items.length; i++) {
      final x = left + (right - left) * (i / span);
      final yRatio = items[i].duration.inSeconds / maxSeconds;
      final y = bottom - usableHeight * yRatio;
      points.add(Offset(x, y));
    }

    final fillPath = Path()..moveTo(points.first.dx, bottom);
    for (final point in points) {
      fillPath.lineTo(point.dx, point.dy);
    }
    fillPath
      ..lineTo(points.last.dx, bottom)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accentColor.withValues(alpha: 0.24),
            accentColor.withValues(alpha: 0.03),
          ],
        ).createShader(Rect.fromLTRB(left, top, right, bottom)),
    );

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      linePath.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = accentColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final pointPaint = Paint()..color = accentColor;
    for (var i = 0; i < points.length; i += 2) {
      canvas.drawCircle(points[i], 2.6, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _FocusLineChartPainter oldDelegate) {
    return oldDelegate.items != items ||
        oldDelegate.maxValue != maxValue ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.gridColor != gridColor;
  }
}

/// 12 周热力图组件。
///
/// children 对应关系：
/// - 第一行：可横向滚动的热力方格矩阵。
/// - 第二行：左/右日期范围标记。
class _FocusHeatmap extends StatelessWidget {
  const _FocusHeatmap({required this.items, required this.maxValue});

  final List<_DailyFocusDuration> items;
  final Duration maxValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final darkMode = theme.brightness == Brightness.dark;
    final columns = 12;
    final rows = 7;
    final start = max(0, items.length - columns * rows);
    final visible = items.sublist(start);
    final cells = List<List<_DailyFocusDuration>>.generate(columns, (column) {
      final from = column * rows;
      final to = min(from + rows, visible.length);
      return visible.sublist(from, to);
    });

    Color levelColor(Duration value) {
      if (value <= Duration.zero) {
        return darkMode ? const Color(0xFF233029) : const Color(0xFFECE2D3);
      }
      final ratio = maxValue.inSeconds == 0
          ? 0.0
          : value.inSeconds / maxValue.inSeconds;
      final alpha = 0.22 + ratio.clamp(0.0, 1.0).toDouble() * 0.78;
      final base = darkMode ? const Color(0xFFA8D4C5) : const Color(0xFF476C63);
      return base.withValues(alpha: alpha);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 热力图主体区域。
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final column in cells) ...[
                Column(
                  children: [
                    for (final day in column)
                      Container(
                        width: 12,
                        height: 12,
                        margin: const EdgeInsets.all(2.2),
                        decoration: BoxDecoration(
                          color: levelColor(day.duration),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 2),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        // 时间范围标注区域。
        Row(
          children: [
            Text(
              items.isNotEmpty
                  ? DateFormat('MM/dd').format(items.first.day)
                  : '--/--',
              style: theme.textTheme.labelSmall,
            ),
            const Spacer(),
            Text(
              items.isNotEmpty
                  ? DateFormat('MM/dd').format(items.last.day)
                  : '--/--',
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ],
    );
  }
}

/// “已存在时长”提示的脉冲抖动组件。
class _DuplicateHintPulse extends StatelessWidget {
  const _DuplicateHintPulse({required this.pulse, required this.text});

  final int pulse;
  final String text;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(pulse),
      duration: const Duration(milliseconds: 360),
      tween: Tween<double>(begin: pulse == 0 ? 0 : 1, end: 0),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final offsetX = sin(value * pi * 6) * value * 8;
        return Transform.translate(
          offset: Offset(offsetX, 0),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: pulse == 0 ? 0 : 1,
            child: child,
          ),
        );
      },
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.error,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 统计指标小卡片（标题 + 数值）。
class _SimpleMetricTile extends StatelessWidget {
  const _SimpleMetricTile({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final darkMode = Theme.of(context).brightness == Brightness.dark;
    final background = darkMode
        ? const Color(0xFF263128)
        : const Color(0xFFF0EADF);

    return Container(
      constraints: const BoxConstraints(minWidth: 132),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

/// 时段分布行（标签 + 进度条 + 数值）。
class _TaskStatsCard extends StatelessWidget {
  const _TaskStatsCard({required this.strings, required this.stats});

  final AppStrings strings;
  final _TaskStatsData stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.taskStats,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _SimpleMetricTile(
                  title: strings.totalTasks,
                  value: '${stats.totalTasks}',
                ),
                _SimpleMetricTile(
                  title: strings.completedOnly,
                  value: '${stats.completedTasks}',
                ),
                _SimpleMetricTile(
                  title: strings.activeOnly,
                  value: '${stats.activeTasks}',
                ),
                _SimpleMetricTile(
                  title: strings.taskCompletionRate,
                  value:
                      '${(stats.completionRate * 100).toStringAsFixed(0)}%',
                ),
                _SimpleMetricTile(
                  title: strings.linkedFocusSessions,
                  value: '${stats.linkedFocusSessions}',
                ),
                _SimpleMetricTile(
                  title: strings.topFocusTask,
                  value: stats.topFocusTaskTitle ?? strings.noFocusTask,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              strings.categoryDistribution,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            if (stats.labelCounts.isEmpty)
              Text(strings.noLabel, style: theme.textTheme.bodyMedium)
            else
              ...stats.labelCounts.entries.map((entry) {
                final label = entry.key == null
                    ? strings.noLabel
                    : strings.taskLabelName(entry.key!);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _CountTrendRow(
                    label: label,
                    value: entry.value,
                    maxValue: stats.maxLabelCount,
                  ),
                );
              }),
            const SizedBox(height: 8),
            Text(
              strings.priorityDistribution,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            ...stats.priorityCounts.entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _CountTrendRow(
                  label: strings.priorityName(entry.key),
                  value: entry.value,
                  maxValue: stats.maxPriorityCount,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _CountTrendRow extends StatelessWidget {
  const _CountTrendRow({
    required this.label,
    required this.value,
    required this.maxValue,
  });

  final String label;
  final int value;
  final int maxValue;

  @override
  Widget build(BuildContext context) {
    final darkMode = Theme.of(context).brightness == Brightness.dark;
    final barColor = darkMode
        ? const Color(0xFFA8D4C5)
        : const Color(0xFF476C63);
    final baseColor = darkMode
        ? const Color(0xFF2A3A33)
        : const Color(0xFFE8DED0);
    final ratio = maxValue == 0 ? 0.0 : value / maxValue;

    return Row(
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 9,
              value: ratio.clamp(0.0, 1.0).toDouble(),
              color: barColor,
              backgroundColor: baseColor,
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 36,
          child: Text(
            '$value',
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _TrendRow extends StatelessWidget {
  const _TrendRow({
    required this.label,
    required this.value,
    required this.maxValue,
  });

  final String label;
  final Duration value;
  final Duration maxValue;

  @override
  Widget build(BuildContext context) {
    final darkMode = Theme.of(context).brightness == Brightness.dark;
    final barColor = darkMode
        ? const Color(0xFFA8D4C5)
        : const Color(0xFF476C63);
    final baseColor = darkMode
        ? const Color(0xFF2A3A33)
        : const Color(0xFFE8DED0);
    final ratio = maxValue.inSeconds == 0
        ? 0.0
        : value.inSeconds / maxValue.inSeconds;

    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 9,
              value: ratio.clamp(0.0, 1.0).toDouble(),
              color: barColor,
              backgroundColor: baseColor,
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 60,
          child: Text(
            _formatDurationHhMm(value),
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// 统计数据聚合结果对象。
///
/// 把原始会话列表整理成 UI 直接可消费的统计字段。
class _TaskStatsData {
  const _TaskStatsData({
    required this.totalTasks,
    required this.completedTasks,
    required this.activeTasks,
    required this.completionRate,
    required this.labelCounts,
    required this.priorityCounts,
    required this.linkedFocusSessions,
    required this.topFocusTaskTitle,
  });

  factory _TaskStatsData.fromTasks(
    List<Task> tasks,
    List<FocusSessionRecord> sessions,
  ) {
    final labelCounts = <String?, int>{};
    final priorityCounts = <int, int>{1: 0, 2: 0, 3: 0};
    var completed = 0;
    var active = 0;
    for (final task in tasks) {
      if (task.status == TaskStatus.completed.value) {
        completed++;
      } else {
        active++;
      }
      final label = task.label?.trim();
      final labelKey = label == null || label.isEmpty ? null : label;
      labelCounts[labelKey] = (labelCounts[labelKey] ?? 0) + 1;
      final priority = switch (task.priority) {
        1 => 1,
        2 => 2,
        _ => 3,
      };
      priorityCounts[priority] = (priorityCounts[priority] ?? 0) + 1;
    }

    final titleByTaskId = <String, String>{
      for (final task in tasks) task.id: task.title,
    };
    final focusByTaskId = <String, Duration>{};
    final snapshotByTaskId = <String, String>{};
    var linkedSessions = 0;
    for (final session in sessions) {
      final taskId = session.taskId;
      if (taskId == null || taskId.isEmpty) {
        continue;
      }
      linkedSessions++;
      focusByTaskId[taskId] =
          (focusByTaskId[taskId] ?? Duration.zero) + session.duration;
      final snapshot = session.taskTitleSnapshot;
      if (snapshot != null && snapshot.isNotEmpty) {
        snapshotByTaskId[taskId] = snapshot;
      }
    }
    String? topFocusTaskTitle;
    Duration topFocusDuration = Duration.zero;
    for (final entry in focusByTaskId.entries) {
      if (entry.value > topFocusDuration) {
        topFocusDuration = entry.value;
        topFocusTaskTitle =
            titleByTaskId[entry.key] ?? snapshotByTaskId[entry.key];
      }
    }

    final total = tasks.length;
    return _TaskStatsData(
      totalTasks: total,
      completedTasks: completed,
      activeTasks: active,
      completionRate: total == 0 ? 0 : completed / total,
      labelCounts: labelCounts,
      priorityCounts: priorityCounts,
      linkedFocusSessions: linkedSessions,
      topFocusTaskTitle: topFocusTaskTitle,
    );
  }

  final int totalTasks;
  final int completedTasks;
  final int activeTasks;
  final double completionRate;
  final Map<String?, int> labelCounts;
  final Map<int, int> priorityCounts;
  final int linkedFocusSessions;
  final String? topFocusTaskTitle;

  int get maxLabelCount => labelCounts.values.fold(
        0,
        (max, item) => item > max ? item : max,
      );

  int get maxPriorityCount => priorityCounts.values.fold(
        0,
        (max, item) => item > max ? item : max,
      );
}

class _FocusStatsData {
  const _FocusStatsData({
    required this.todayFocus,
    required this.totalFocus,
    required this.completedSessions,
    required this.interruptedSessions,
    required this.longestSession,
    required this.countdownSessions,
    required this.countupSessions,
    required this.recent7Days,
    required this.recent14Days,
    required this.recent84Days,
    required this.distributions,
    required this.mostActivePeriod,
    required this.averageSession,
    required this.completionRate,
    required this.activeDaysIn7Days,
    required this.currentStreakDays,
    required this.sessionsThisWeek,
  });

  factory _FocusStatsData.fromSessions(List<FocusSessionRecord> sessions) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final cutoff = today.subtract(const Duration(days: 6));
    final cutoff14 = today.subtract(const Duration(days: 13));
    final cutoff84 = today.subtract(const Duration(days: 83));
    final recent7DaysMap = <DateTime, Duration>{};
    final recent14DaysMap = <DateTime, Duration>{};
    final recent84DaysMap = <DateTime, Duration>{};
    for (var i = 0; i < 7; i++) {
      final day = cutoff.add(Duration(days: i));
      recent7DaysMap[day] = Duration.zero;
    }
    for (var i = 0; i < 14; i++) {
      final day = cutoff14.add(Duration(days: i));
      recent14DaysMap[day] = Duration.zero;
    }
    for (var i = 0; i < 84; i++) {
      final day = cutoff84.add(Duration(days: i));
      recent84DaysMap[day] = Duration.zero;
    }

    final distributions = <_DayPeriod, Duration>{
      _DayPeriod.morning: Duration.zero,
      _DayPeriod.afternoon: Duration.zero,
      _DayPeriod.evening: Duration.zero,
      _DayPeriod.night: Duration.zero,
    };

    Duration todayFocus = Duration.zero;
    Duration totalFocus = Duration.zero;
    Duration longest = Duration.zero;
    var completed = 0;
    var interrupted = 0;
    var countdown = 0;
    var countup = 0;
    final allDayTotals = <DateTime, Duration>{};
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    var sessionsThisWeek = 0;

    for (final session in sessions) {
      totalFocus += session.duration;
      if (session.duration > longest) {
        longest = session.duration;
      }
      if (session.completed) {
        completed++;
      } else {
        interrupted++;
      }
      if (session.mode == FocusTimerMode.countdown) {
        countdown++;
      } else {
        countup++;
      }

      final sessionDay = DateTime(
        session.endAt.year,
        session.endAt.month,
        session.endAt.day,
      );
      allDayTotals[sessionDay] =
          (allDayTotals[sessionDay] ?? Duration.zero) + session.duration;
      if (sessionDay == today) {
        todayFocus += session.duration;
      }
      if (!sessionDay.isBefore(weekStart)) {
        sessionsThisWeek++;
      }
      if (recent7DaysMap.containsKey(sessionDay)) {
        recent7DaysMap[sessionDay] =
            (recent7DaysMap[sessionDay] ?? Duration.zero) + session.duration;
      }
      if (recent14DaysMap.containsKey(sessionDay)) {
        recent14DaysMap[sessionDay] =
            (recent14DaysMap[sessionDay] ?? Duration.zero) + session.duration;
      }
      if (recent84DaysMap.containsKey(sessionDay)) {
        recent84DaysMap[sessionDay] =
            (recent84DaysMap[sessionDay] ?? Duration.zero) + session.duration;
      }

      final period = _dayPeriodFromHour(session.endAt.hour);
      distributions[period] =
          (distributions[period] ?? Duration.zero) + session.duration;
    }

    var mostActive = _DayPeriod.morning;
    for (final entry in distributions.entries) {
      if (entry.value > (distributions[mostActive] ?? Duration.zero)) {
        mostActive = entry.key;
      }
    }

    final recent7Days = recent7DaysMap.entries
        .map((entry) => _DailyFocusDuration(entry.key, entry.value))
        .toList(growable: false);
    final recent14Days = recent14DaysMap.entries
        .map((entry) => _DailyFocusDuration(entry.key, entry.value))
        .toList(growable: false);
    final recent84Days = recent84DaysMap.entries
        .map((entry) => _DailyFocusDuration(entry.key, entry.value))
        .toList(growable: false);
    final activeDaysIn7Days = recent7Days
        .where((item) => item.duration > Duration.zero)
        .length;
    final totalSessions = completed + interrupted;
    final averageSession = totalSessions == 0
        ? Duration.zero
        : Duration(seconds: totalFocus.inSeconds ~/ totalSessions);
    final completionRate = totalSessions == 0 ? 0.0 : completed / totalSessions;
    var currentStreakDays = 0;
    var streakCursor = today;
    while ((allDayTotals[streakCursor] ?? Duration.zero) > Duration.zero) {
      currentStreakDays++;
      streakCursor = streakCursor.subtract(const Duration(days: 1));
    }

    return _FocusStatsData(
      todayFocus: todayFocus,
      totalFocus: totalFocus,
      completedSessions: completed,
      interruptedSessions: interrupted,
      longestSession: longest,
      countdownSessions: countdown,
      countupSessions: countup,
      recent7Days: recent7Days,
      recent14Days: recent14Days,
      recent84Days: recent84Days,
      distributions: distributions,
      mostActivePeriod: mostActive,
      averageSession: averageSession,
      completionRate: completionRate,
      activeDaysIn7Days: activeDaysIn7Days,
      currentStreakDays: currentStreakDays,
      sessionsThisWeek: sessionsThisWeek,
    );
  }

  final Duration todayFocus;
  final Duration totalFocus;
  final int completedSessions;
  final int interruptedSessions;
  final Duration longestSession;
  final int countdownSessions;
  final int countupSessions;
  final List<_DailyFocusDuration> recent7Days;
  final List<_DailyFocusDuration> recent14Days;
  final List<_DailyFocusDuration> recent84Days;
  final Map<_DayPeriod, Duration> distributions;
  final _DayPeriod mostActivePeriod;
  final Duration averageSession;
  final double completionRate;
  final int activeDaysIn7Days;
  final int currentStreakDays;
  final int sessionsThisWeek;

  Duration get recent7DaysTotal =>
      recent7Days.fold(Duration.zero, (sum, item) => sum + item.duration);

  Duration get maxHeatmapDuration => recent84Days.fold(
    Duration.zero,
    (max, item) => item.duration > max ? item.duration : max,
  );

  Duration get maxDistributionValue => distributions.values.fold(
    Duration.zero,
    (max, item) => item > max ? item : max,
  );
}

class _DailyFocusDuration {
  const _DailyFocusDuration(this.day, this.duration);

  final DateTime day;
  final Duration duration;
}

/// 一天中的统计时段分桶。
enum _DayPeriod { morning, afternoon, evening, night }

/// 常用时长条目的长按动作。
enum _DurationAction { edit, delete }

/// 按小时映射到时段分桶。
_DayPeriod _dayPeriodFromHour(int hour) {
  if (hour >= 5 && hour < 11) {
    return _DayPeriod.morning;
  }
  if (hour >= 11 && hour < 17) {
    return _DayPeriod.afternoon;
  }
  if (hour >= 17 && hour < 22) {
    return _DayPeriod.evening;
  }
  return _DayPeriod.night;
}

/// 根据当前语言返回时段文案。
String _periodLabel(AppStrings strings, _DayPeriod period) {
  return switch (period) {
    _DayPeriod.morning => strings.periodMorning,
    _DayPeriod.afternoon => strings.periodAfternoon,
    _DayPeriod.evening => strings.periodEvening,
    _DayPeriod.night => strings.periodNight,
  };
}

/// 计算番茄钟圆盘进度（0~1）。
double _dialProgress(FocusState state) {
  if (state.mode == FocusTimerMode.countdown) {
    final targetSeconds = state.countdownTarget.inSeconds;
    if (targetSeconds <= 0) {
      return 0;
    }
    return (state.elapsed.inSeconds / targetSeconds)
        .clamp(0.0, 1.0)
        .toDouble();
  }
  return ((state.elapsed.inSeconds % 3600) / 3600)
      .clamp(0.0, 1.0)
      .toDouble();
}

/// 把计时时长格式化为 `mm:ss` 或 `hh:mm:ss`。
String _formatTimer(Duration duration, {bool showHourAlways = false}) {
  final totalSeconds = duration.inSeconds.clamp(0, 24 * 3600 * 99);
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (showHourAlways || hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

/// 把任意时长统一格式化为 `hh:mm`。
String _formatDurationHhMm(Duration duration) {
  final totalMinutes = duration.inMinutes;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
}

/// 把分钟数（int）格式化为 `hh:mm`。
String _formatDurationOption(int minutes) {
  final hours = minutes ~/ 60;
  final remain = minutes % 60;
  return '${hours.toString().padLeft(2, '0')}:${remain.toString().padLeft(2, '0')}';
}

/// 根据小时返回可选分钟列表。
///
/// - 0 小时：不允许 00 分（避免无效 00:00）。
/// - 最大小时（3 小时）：仅允许 00 分。
List<int> _minuteOptionsForHour(int hour) {
  if (hour == _maxSelectableDurationHours) {
    return const [0];
  }
  if (hour == 0) {
    return List<int>.generate(_minutesPerHour - 1, (index) => index + 1);
  }
  return List<int>.generate(_minutesPerHour, (index) => index);
}

/// 长按常用时长后弹出的操作菜单（编辑 / 删除）。
Future<_DurationAction?> _showDurationActionsSheet({
  required BuildContext context,
  required AppStrings strings,
  required int duration,
}) {
  return showModalBottomSheet<_DurationAction>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: Text(
                '${strings.editDuration} (${_formatDurationOption(duration)})',
              ),
              onTap: () => Navigator.of(context).pop(_DurationAction.edit),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: Text(
                '${strings.deleteDuration} (${_formatDurationOption(duration)})',
              ),
              onTap: () => Navigator.of(context).pop(_DurationAction.delete),
            ),
          ],
        ),
      );
    },
  );
}

/// 新增/编辑常用时长弹窗。
///
/// 使用双列滚轮（时、分）选择，避免文本输入带来的非法值。
Future<int?> _showDurationEditorDialog({
  required BuildContext context,
  required AppStrings strings,
  required List<int> existingDurations,
  required String title,
  int? initialMinutes,
}) async {
  var selectedHour =
      ((initialMinutes ?? _defaultCountdownMinutes) ~/ _minutesPerHour).clamp(
        0,
        _maxSelectableDurationHours,
      );
  var selectedMinute =
      (initialMinutes ?? _defaultCountdownMinutes) % _minutesPerHour;
  if (selectedHour == _maxSelectableDurationHours) {
    selectedMinute = 0;
  } else if (selectedHour == 0 && selectedMinute == 0) {
    selectedMinute = 1;
  }
  var duplicatePulse = 0;
  var minuteScrollTarget = selectedMinute;
  final hourController = FixedExtentScrollController(initialItem: selectedHour);
  final minuteController = FixedExtentScrollController(
    initialItem: selectedMinute,
  );
  int? result;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          final minuteOptions = _minuteOptionsForHour(selectedHour);
          if (!minuteOptions.contains(selectedMinute)) {
            selectedMinute = minuteOptions.first;
            minuteScrollTarget = 0;
          }
          final minuteIndex = minuteOptions.indexOf(selectedMinute);
          if (minuteScrollTarget != minuteIndex) {
            minuteScrollTarget = minuteIndex;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!minuteController.hasClients) {
                return;
              }
              minuteController.jumpToItem(minuteScrollTarget);
            });
          }
          return TaskNetWheelSheetFrame(
            title: title,
            cancelText: strings.cancel,
            confirmText: strings.save,
            onCancel: () => Navigator.of(context).pop(),
            onConfirm: () {
              final totalMinutes = selectedHour * 60 + selectedMinute;
              if (existingDurations.contains(totalMinutes)) {
                setModalState(() => duplicatePulse++);
                TaskNetNotice.showInfo(
                  sheetContext,
                  strings.durationAlreadyExists,
                );
                return;
              }
              result = totalMinutes;
              Navigator.of(context).pop();
            },
            labels: [strings.hour, strings.minute],
            footer: Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 2),
              child: _DuplicateHintPulse(
                pulse: duplicatePulse,
                text: strings.durationAlreadyExists,
              ),
            ),
            child: Row(
              children: [
                TaskNetWheelColumn(
                  controller: hourController,
                  itemCount: _maxSelectableDurationHours + 1,
                  displayBuilder: (index) => index.toString().padLeft(2, '0'),
                  onSelectedItemChanged: (index) {
                    setModalState(() {
                      selectedHour = index;
                      final nextOptions = _minuteOptionsForHour(selectedHour);
                      if (!nextOptions.contains(selectedMinute)) {
                        selectedMinute = nextOptions.first;
                      }
                      minuteScrollTarget = nextOptions.indexOf(selectedMinute);
                    });
                  },
                ),
                TaskNetWheelColumn(
                  controller: minuteController,
                  itemCount: minuteOptions.length,
                  displayBuilder: (index) =>
                      minuteOptions[index].toString().padLeft(2, '0'),
                  onSelectedItemChanged: (index) =>
                      selectedMinute = minuteOptions[index],
                ),
              ],
            ),
          );
        },
      );
    },
  );

  hourController.dispose();
  minuteController.dispose();
  return result;
}

/// 每小时分钟数常量。
const _minutesPerHour = 60;

/// 倒计时可选的最大小时数（3 小时）。
const _maxSelectableDurationHours = 3;

/// 倒计时默认分钟数（30 分钟）。
const _defaultCountdownMinutes = 30;
