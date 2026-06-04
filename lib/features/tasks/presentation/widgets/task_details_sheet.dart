import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../app/preferences/app_preferences.dart';
import '../../data/task_repository.dart';

/// 打开任务详情底部弹窗。
///
/// 弹窗使用“自底向上”的局部展示方式，保持用户仍然处在首页上下文中，
/// 同时提供比任务卡片更完整的信息视图。
Future<void> showTaskDetailsSheet({
  required BuildContext context,
  required Task task,
  required AppStrings strings,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => _TaskDetailsSheet(task: task, strings: strings),
  );
}

/// 任务详情底部弹窗主体。
///
/// children 映射关系：
/// - 顶部：拖拽手柄。
/// - 中部：若有 DDL，显示创建时间/DDL + 进度条。
/// - 下部：详细描述 + 重要/紧急/标签信息。
class _TaskDetailsSheet extends StatelessWidget {
  const _TaskDetailsSheet({required this.task, required this.strings});

  final Task task;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final darkMode = theme.brightness == Brightness.dark;
    final now = DateTime.now();
    final description = (task.description ?? '').trim();

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          minHeight: 320,
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        decoration: BoxDecoration(
          color: darkMode ? const Color(0xFF171D1A) : const Color(0xFFFDFBF7),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: darkMode
                      ? const Color(0xFF3A463F)
                      : const Color(0xFFD9D1C4),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    if (task.dueAt != null) ...[
                      const SizedBox(height: 14),
                      _TaskTimelineProgress(
                        createdAt: task.createdAt,
                        dueAt: task.dueAt!,
                        now: now,
                        strings: strings,
                      ),
                    ],
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text(
                        description,
                        style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                      ),
                    ],
                    if (task.isImportant ||
                        task.isUrgent ||
                        task.label != null) ...[
                      const SizedBox(height: 18),
                      _TaskMetaInfo(task: task, strings: strings),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 任务创建时间到截止时间的进度条展示。
///
/// 视觉语义：左侧是创建时间，右侧是 DDL，中间进度表示“当前时间在区间里的推进程度”。
class _TaskTimelineProgress extends StatelessWidget {
  const _TaskTimelineProgress({
    required this.createdAt,
    required this.dueAt,
    required this.now,
    required this.strings,
  });

  final DateTime createdAt;
  final DateTime dueAt;
  final DateTime now;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final darkMode = theme.brightness == Brightness.dark;

    final totalMs =
        dueAt.millisecondsSinceEpoch - createdAt.millisecondsSinceEpoch;
    final elapsedMs =
        now.millisecondsSinceEpoch - createdAt.millisecondsSinceEpoch;
    final progress = totalMs <= 0
        ? 1.0
        : (elapsedMs / totalMs).clamp(0.0, 1.0).toDouble();
    final overdue = now.isAfter(dueAt);

    final dateFormat = DateFormat(
      strings.fullDateTimePattern,
      strings.dateLocale,
    );
    final leftText = dateFormat.format(createdAt);
    final rightText = dateFormat.format(dueAt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                leftText,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: darkMode
                      ? const Color(0xFF9EB0A6)
                      : const Color(0xFF74756C),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              rightText,
              style: theme.textTheme.labelMedium?.copyWith(
                color: overdue
                    ? const Color(0xFFB04938)
                    : (darkMode
                          ? const Color(0xFFB5C9BE)
                          : const Color(0xFF4F5F58)),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 7,
            value: progress,
            backgroundColor: darkMode
                ? const Color(0xFF2A342E)
                : const Color(0xFFE6DED0),
            valueColor: AlwaysStoppedAnimation<Color>(
              overdue
                  ? const Color(0xFFB04938)
                  : (darkMode
                        ? const Color(0xFFA8D4C5)
                        : const Color(0xFF33544B)),
            ),
          ),
        ),
      ],
    );
  }
}

/// 任务补充信息块（重要/紧急/标签）。
class _TaskMetaInfo extends StatelessWidget {
  const _TaskMetaInfo({required this.task, required this.strings});

  final Task task;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (task.isImportant)
        _MetaPill(
          icon: Icons.flag_rounded,
          label: strings.important,
          tone: const Color(0xFF7D562A),
        ),
      if (task.isUrgent)
        _MetaPill(
          icon: Icons.priority_high_rounded,
          label: strings.urgent,
          tone: const Color(0xFF8A3D2C),
        ),
      if (task.label != null)
        _MetaPill(
          icon: Icons.sell_outlined,
          label: strings.taskLabelName(task.label!),
          tone: const Color(0xFF3F6B8A),
        ),
    ];
    if (chips.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }
}

/// 详情页信息胶囊。
class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.icon,
    required this.label,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: tone),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: tone,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
