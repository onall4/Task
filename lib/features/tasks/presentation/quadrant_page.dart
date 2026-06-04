import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/preferences/app_preferences.dart';
import '../data/task_repository.dart';
import 'widgets/task_details_sheet.dart';

class QuadrantPage extends ConsumerStatefulWidget {
  const QuadrantPage({super.key});

  @override
  ConsumerState<QuadrantPage> createState() => _QuadrantPageState();
}

class _QuadrantPageState extends ConsumerState<QuadrantPage> {
  static const _sectionGap = 10.0;
  static const _completeAnimationDuration = Duration(milliseconds: 420);

  final _completingTaskIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(taskListProvider);
    final strings = ref.watch(appStringsProvider);

    return tasksAsync.when(
      data: (tasks) {
        final activeTasks =
            tasks
                .where((task) => task.status == TaskStatus.active.value)
                .toList()
              ..sort(_compareQuadrantTasks);
        _syncCompletingTaskIds(activeTasks.map((task) => task.id).toSet());
        final sections = [
          _QuadrantSectionData(
            importanceLabel: _importanceLabel(strings, isImportant: true),
            urgencyLabel: _urgencyLabel(strings, isUrgent: true),
            icon: Icons.priority_high_rounded,
            tone: const Color(0xFFD84A3A),
            tasks: _filterTasks(activeTasks, isImportant: true, isUrgent: true),
          ),
          _QuadrantSectionData(
            importanceLabel: _importanceLabel(strings, isImportant: true),
            urgencyLabel: _urgencyLabel(strings, isUrgent: false),
            icon: Icons.flag_rounded,
            tone: const Color(0xFF2F6FE4),
            tasks: _filterTasks(
              activeTasks,
              isImportant: true,
              isUrgent: false,
            ),
          ),
          _QuadrantSectionData(
            importanceLabel: _importanceLabel(strings, isImportant: false),
            urgencyLabel: _urgencyLabel(strings, isUrgent: true),
            icon: Icons.bolt_rounded,
            tone: const Color(0xFFE68622),
            tasks: _filterTasks(
              activeTasks,
              isImportant: false,
              isUrgent: true,
            ),
          ),
          _QuadrantSectionData(
            importanceLabel: _importanceLabel(strings, isImportant: false),
            urgencyLabel: _urgencyLabel(strings, isUrgent: false),
            icon: Icons.low_priority_rounded,
            tone: const Color(0xFF2F9E68),
            tasks: _filterTasks(
              activeTasks,
              isImportant: false,
              isUrgent: false,
            ),
          ),
        ];

        return LayoutBuilder(
          builder: (context, constraints) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: _QuadrantSection(
                            data: sections[1],
                            strings: strings,
                            completingTaskIds: _completingTaskIds,
                            onCompleteTask: _completeTask,
                          ),
                        ),
                        const SizedBox(width: _sectionGap),
                        Expanded(
                          child: _QuadrantSection(
                            data: sections[0],
                            strings: strings,
                            completingTaskIds: _completingTaskIds,
                            onCompleteTask: _completeTask,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: _sectionGap),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: _QuadrantSection(
                            data: sections[2],
                            strings: strings,
                            completingTaskIds: _completingTaskIds,
                            onCompleteTask: _completeTask,
                          ),
                        ),
                        const SizedBox(width: _sectionGap),
                        Expanded(
                          child: _QuadrantSection(
                            data: sections[3],
                            strings: strings,
                            completingTaskIds: _completingTaskIds,
                            onCompleteTask: _completeTask,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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

class _QuadrantSection extends StatelessWidget {
  const _QuadrantSection({
    required this.data,
    required this.strings,
    required this.completingTaskIds,
    required this.onCompleteTask,
  });

  final _QuadrantSectionData data;
  final AppStrings strings;
  final Set<String> completingTaskIds;
  final ValueChanged<Task> onCompleteTask;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final darkMode = theme.brightness == Brightness.dark;
    final backgroundColor = darkMode
        ? Color.alphaBlend(
            data.tone.withValues(alpha: 0.16),
            const Color(0xFF1D241F),
          )
        : Color.alphaBlend(
            data.tone.withValues(alpha: 0.08),
            Colors.white.withValues(alpha: 0.92),
          );
    final borderColor = darkMode
        ? data.tone.withValues(alpha: 0.46)
        : data.tone.withValues(alpha: 0.32);
    final toneColor = darkMode
        ? Color.lerp(data.tone, Colors.white, 0.18)!
        : data.tone;

    Widget buildTaskRow(Task task, bool isLast) {
      final completing = completingTaskIds.contains(task.id);
      return _CompletingTaskItem(
        key: ValueKey('quadrant-task-${task.id}'),
        completing: completing,
        duration: _QuadrantPageState._completeAnimationDuration,
        child: Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : 6),
          child: _QuadrantTaskRow(
            task: task,
            completing: completing,
            onComplete: () => onCompleteTask(task),
            onTap: () {
              showTaskDetailsSheet(
                context: context,
                task: task,
                strings: strings,
              );
            },
          ),
        ),
      );
    }

    Widget buildTaskList() {
      if (data.tasks.isEmpty) {
        return Expanded(
          child: _QuadrantEmptyState(text: strings.quadrantEmpty),
        );
      }

      return Expanded(
        child: ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: data.tasks.length,
          itemBuilder: (context, index) {
            return buildTaskRow(
              data.tasks[index],
              index == data.tasks.length - 1,
            );
          },
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _QuadrantHeader(data: data, toneColor: toneColor),
            const SizedBox(height: 10),
            buildTaskList(),
          ],
        ),
      ),
    );
  }
}

class _QuadrantTaskRow extends StatelessWidget {
  const _QuadrantTaskRow({
    required this.task,
    required this.completing,
    required this.onComplete,
    required this.onTap,
  });

  final Task task;
  final bool completing;
  final VoidCallback onComplete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 36,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Row(
            children: [
              Checkbox(
                value: completing,
                onChanged: completing ? null : (_) => onComplete(),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.1,
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

class _CompletingTaskItem extends StatelessWidget {
  const _CompletingTaskItem({
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
        final collapseProgress = ((progress - 0.42) / 0.58).clamp(0.0, 1.0);
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

class _QuadrantHeader extends StatelessWidget {
  const _QuadrantHeader({required this.data, required this.toneColor});

  final _QuadrantSectionData data;
  final Color toneColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final countText = '${data.tasks.length}';

    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: toneColor,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: toneColor.withValues(alpha: 0.24),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(data.icon, size: 19, color: Colors.white),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.importanceLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: toneColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                data.urgencyLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: toneColor.withValues(alpha: 0.82),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          constraints: const BoxConstraints(minWidth: 28),
          height: 28,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: toneColor.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            countText,
            style: theme.textTheme.labelLarge?.copyWith(
              color: toneColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _QuadrantEmptyState extends StatelessWidget {
  const _QuadrantEmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
      ),
    );
  }
}

class _QuadrantSectionData {
  const _QuadrantSectionData({
    required this.importanceLabel,
    required this.urgencyLabel,
    required this.icon,
    required this.tone,
    required this.tasks,
  });

  final String importanceLabel;
  final String urgencyLabel;
  final IconData icon;
  final Color tone;
  final List<Task> tasks;
}

String _importanceLabel(AppStrings strings, {required bool isImportant}) {
  if (isImportant) {
    return strings.important;
  }
  return strings.isChinese ? '不重要' : 'Not important';
}

String _urgencyLabel(AppStrings strings, {required bool isUrgent}) {
  if (isUrgent) {
    return strings.urgent;
  }
  return strings.isChinese ? '不紧急' : 'Not urgent';
}

List<Task> _filterTasks(
  List<Task> tasks, {
  required bool isImportant,
  required bool isUrgent,
}) {
  return tasks
      .where(
        (task) => task.isImportant == isImportant && task.isUrgent == isUrgent,
      )
      .toList(growable: false);
}

int _compareQuadrantTasks(Task left, Task right) {
  final leftDueAt = left.dueAt;
  final rightDueAt = right.dueAt;
  if (leftDueAt != null && rightDueAt != null) {
    final dueComparison = leftDueAt.compareTo(rightDueAt);
    if (dueComparison != 0) {
      return dueComparison;
    }
  } else if (leftDueAt != null) {
    return -1;
  } else if (rightDueAt != null) {
    return 1;
  }

  final orderComparison = left.sortOrder.compareTo(right.sortOrder);
  if (orderComparison != 0) {
    return orderComparison;
  }
  return right.updatedAt.compareTo(left.updatedAt);
}
