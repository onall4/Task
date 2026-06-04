import 'package:flutter/material.dart';

import '../../../../app/preferences/app_preferences.dart';
import '../../data/task_repository.dart';

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
    this.onSelectToggle,
    this.completionStrikeProgress,
    this.completionPreviewCompleted,
  });

  static const height = 64.0;

  final Task task;
  final AppStrings strings;
  final VoidCallback onTap;
  final VoidCallback onEditTap;
  final VoidCallback onCompleteToggle;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onSelectToggle;
  final double? completionStrikeProgress;
  final bool? completionPreviewCompleted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final darkMode = theme.brightness == Brightness.dark;
    final persistedCompleted = task.status == TaskStatus.completed.value;
    final completed = completionPreviewCompleted ?? persistedCompleted;

    final cardDecoration = BoxDecoration(
      color: darkMode
          ? const Color(0xFF202822).withValues(alpha: completed ? 0.72 : 0.96)
          : Colors.white.withValues(alpha: completed ? 0.78 : 0.92),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: isSelected
            ? (darkMode ? const Color(0xFFA8D4C5) : const Color(0xFF33544B))
            : (darkMode ? const Color(0xFF354239) : const Color(0xFFE8DED0)),
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
                  darkMode: darkMode,
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

class _TaskCardSelectionBox extends StatelessWidget {
  const _TaskCardSelectionBox({
    required this.completed,
    required this.isSelected,
    required this.isSelectionMode,
    required this.darkMode,
    required this.onTap,
  });

  final bool completed;
  final bool isSelected;
  final bool isSelectionMode;
  final bool darkMode;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final selectedTone = darkMode
        ? const Color(0xFFA8D4C5)
        : const Color(0xFF33544B);
    final idleTone = darkMode
        ? const Color(0xFF4A5B51)
        : const Color(0xFFDCCFBD);
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
            : null,
      ),
    );
  }
}

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
