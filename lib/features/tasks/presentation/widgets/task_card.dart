/*
 * 任务卡片组件。
 *
 * 这个文件负责实现首页、日历页和已完成区域共用的任务卡片：
 * - TaskCard — 固定高度 64px 的任务条目，包含勾选框、标题和编辑按钮
 * - 已过期的未完成任务显示琥珀色边框和时钟图标作为警告样式
 * - 完成状态切换时显示从左到右的删除线动画
 *
 * 卡片本身不包含拖拽或滑动逻辑，由外部列表组件提供。
 */
import 'package:flutter/material.dart';

import '../../../../app/preferences/app_preferences.dart';
import '../../data/task_repository.dart';

/// 任务卡片组件。
///
/// 首页、日历页和已完成区域共用的卡片组件，高度固定为 64px。
/// 支持显示选中状态、完成划线和已过期的琥珀色警告样式。
class TaskCard extends StatelessWidget {
  const TaskCard({
    super.key,
    required this.task,
    required this.strings,
    required this.onTap,
    required this.onEditTap,
    required this.onCompleteToggle,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.isOverdue = false,
    this.onSelectToggle,
    this.completionStrikeProgress,
    this.completionPreviewCompleted,
  });

  static const height = 64.0;

  /// 任务实体数据。
  final Task task;

  /// 本地化字符串。
  final AppStrings strings;

  /// 卡片点击回调。
  final VoidCallback onTap;

  /// 编辑按钮点击回调。
  final VoidCallback onEditTap;

  /// 完成状态切换回调。
  final VoidCallback onCompleteToggle;

  /// 是否处于多选模式。
  final bool isSelectionMode;

  /// 是否在当前多选中被选中。
  final bool isSelected;

  /// 是否为已过期任务（截止时间已过但未完成）。
  final bool isOverdue;

  /// 多选切换回调。
  final VoidCallback? onSelectToggle;

  /// 完成划线动画进度（0 到 1）。
  final double? completionStrikeProgress;

  /// 完成状态动画的预览目标。
  final bool? completionPreviewCompleted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final darkMode = theme.brightness == Brightness.dark;
    final persistedCompleted = task.status == TaskStatus.completed.value;
    final completed = completionPreviewCompleted ?? persistedCompleted;

    final overdueAmber = darkMode
        ? const Color(0xFF8B7332)
        : const Color(0xFFC8A44C);
    final cardBorderColor = isSelected
        ? (darkMode ? const Color(0xFFA8D4C5) : const Color(0xFF33544B))
        : (isOverdue && !completed
            ? overdueAmber
            : (darkMode ? const Color(0xFF354239) : const Color(0xFFE8DED0)));
    final cardDecoration = BoxDecoration(
      color: darkMode
          ? const Color(0xFF202822).withValues(alpha: completed ? 0.72 : 0.96)
          : Colors.white.withValues(alpha: completed ? 0.78 : 0.92),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: cardBorderColor,
        width: isSelected ? 1.4 : 1,
      ),
    );

    return SizedBox(
      height: height,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
            decoration: cardDecoration,
            child: Row(
              children: [
                _TaskCardSelectionBox(
                  completed: completed,
                  isSelected: isSelected,
                  isSelectionMode: isSelectionMode,
                  isOverdue: isOverdue,
                  darkMode: darkMode,
                  overdueAmber: overdueAmber,
                  onTap: isSelectionMode ? onSelectToggle : onCompleteToggle,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TaskCardTitleRow(
                    title: task.title,
                    completed: completed,
                    darkMode: darkMode,
                    editTooltip: strings.editTaskTitle,
                    onEditTap: onEditTap,
                    completionStrikeProgress: completionStrikeProgress,
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

/// 任务卡片左侧的勾选框或选中圆圈。
///
/// 在多选模式下显示为圆形选中框，普通模式下显示为圆角方形的完成勾选框。
/// 已过期但未完成的任务显示琥珀色时钟图标。
class _TaskCardSelectionBox extends StatelessWidget {
  const _TaskCardSelectionBox({
    required this.completed,
    required this.isSelected,
    required this.isSelectionMode,
    required this.isOverdue,
    required this.darkMode,
    required this.overdueAmber,
    required this.onTap,
  });

  final bool completed;
  final bool isSelected;
  final bool isSelectionMode;
  final bool isOverdue;
  final bool darkMode;
  final Color overdueAmber;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final selectedTone = darkMode
        ? const Color(0xFFA8D4C5)
        : const Color(0xFF33544B);
    final idleTone = isOverdue && !completed
        ? overdueAmber
        : (darkMode ? const Color(0xFF4A5B51) : const Color(0xFFDCCFBD));
    final isChecked = isSelectionMode ? isSelected : completed;
    final checkboxRadius = isSelectionMode ? 999.0 : 5.0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: isChecked
              ? selectedTone
              : (darkMode ? const Color(0xFF1A211D) : const Color(0xFFF4EEE4)),
          borderRadius: BorderRadius.circular(checkboxRadius),
          border: Border.all(color: isChecked ? selectedTone : idleTone),
        ),
        child: isChecked
            ? Icon(
                Icons.check_rounded,
                size: 15,
                color: darkMode ? const Color(0xFF15201B) : Colors.white,
              )
            : (isOverdue && !isSelectionMode
                ? Icon(
                    Icons.schedule_rounded,
                    size: 14,
                    color: overdueAmber,
                  )
                : null),
      ),
    );
  }
}

/// 任务卡片标题行。
///
/// 包含任务标题文本和编辑按钮。已完成的任务标题会变灰并显示删除线动画。
class _TaskCardTitleRow extends StatelessWidget {
  const _TaskCardTitleRow({
    required this.title,
    required this.completed,
    required this.darkMode,
    required this.editTooltip,
    required this.onEditTap,
    this.completionStrikeProgress,
  });

  final String title;
  final bool completed;
  final bool darkMode;
  final String editTooltip;
  final VoidCallback onEditTap;

  /// 完成划线动画进度（null 表示不显示动画）。
  final double? completionStrikeProgress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w800,
      height: 1.1,
      color: completed
          ? (darkMode ? const Color(0xFF83948A) : const Color(0xFF78837D))
          : (darkMode ? const Color(0xFFEAF1EC) : const Color(0xFF24302C)),
    );
    final strikeProgress = completionStrikeProgress ?? (completed ? 1.0 : 0.0);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: strikeProgress <= 0
              ? Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle,
                )
              : _AnimatedStrikeText(
                  title: title,
                  style: textStyle,
                  progress: strikeProgress.clamp(0, 1).toDouble(),
                  color: darkMode
                      ? const Color(0xFFA8D4C5)
                      : const Color(0xFF33544B),
                ),
        ),
        const SizedBox(width: 6),
        _TaskCardEditButton(
          darkMode: darkMode,
          tooltip: editTooltip,
          onTap: onEditTap,
        ),
      ],
    );
  }
}

/// 带动画的删除线文本。
///
/// 通过 [CustomPainter] 从左到右绘制一条横穿文字的删除线，
/// 进度由 [progress] 控制，用于完成状态切换的过渡动画。
class _AnimatedStrikeText extends StatelessWidget {
  const _AnimatedStrikeText({
    required this.title,
    required this.style,
    required this.progress,
    required this.color,
  });

  final String title;
  final TextStyle? style;
  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: title, style: style),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: constraints.maxWidth);
        final strikeWidth = painter.width
            .clamp(0.0, constraints.maxWidth)
            .toDouble();

        return Stack(
          alignment: Alignment.centerLeft,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
            Positioned(
              left: 0,
              width: strikeWidth * progress,
              top: 0,
              bottom: 0,
              child: CustomPaint(painter: _StrikeLinePainter(color: color)),
            ),
          ],
        );
      },
    );
  }
}

/// 绘制删除线的画笔。
///
/// 在给定区域中间偏下位置绘制一条圆角线条，线宽 2px。
class _StrikeLinePainter extends CustomPainter {
  const _StrikeLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) {
      return;
    }

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final y = size.height * 0.52;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
  }

  @override
  bool shouldRepaint(covariant _StrikeLinePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

/// 任务卡片右侧的编辑按钮。
///
/// 圆形背景上显示铅笔图标，点击后打开任务编辑页。
class _TaskCardEditButton extends StatelessWidget {
  const _TaskCardEditButton({
    required this.darkMode,
    required this.tooltip,
    required this.onTap,
  });

  final bool darkMode;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: darkMode
                ? const Color(0xFF2A352E).withValues(alpha: 0.9)
                : const Color(0xFFF2ECE2),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.edit_outlined,
            size: 18,
            color: darkMode ? const Color(0xFFA8D4C5) : const Color(0xFF496157),
          ),
        ),
      ),
    );
  }
}
