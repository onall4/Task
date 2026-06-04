import 'package:flutter/material.dart';

/// 通用底部滚轮选择器容器。
///
/// 负责统一：拖拽手柄、顶部操作栏、列标签区、中心高亮区背景和滚轮内容区，
/// 让不同业务场景都能复用同一套视觉与交互结构。
class TaskNetWheelSheetFrame extends StatelessWidget {
  const TaskNetWheelSheetFrame({
    super.key,
    required this.title,
    required this.cancelText,
    required this.confirmText,
    required this.onCancel,
    required this.onConfirm,
    required this.child,
    this.labels = const [],
    this.wheelHeight = 216,
    this.footer,
  });

  final String title;
  final String cancelText;
  final String confirmText;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final Widget child;
  final List<String> labels;
  final double wheelHeight;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final darkMode = theme.brightness == Brightness.dark;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: darkMode ? const Color(0xFF171D1A) : const Color(0xFFFDFBF7),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 顶部拖拽手柄：提示“这是一个可下拉关闭的底部弹窗”。
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: darkMode
                    ? const Color(0xFF3A463F)
                    : const Color(0xFFD9D1C4),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            // 操作栏：左取消、中标题、右确认，对应弹窗最核心的行为入口。
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Row(
                children: [
                  TextButton(onPressed: onCancel, child: Text(cancelText)),
                  const Spacer(),
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  TextButton(onPressed: onConfirm, child: Text(confirmText)),
                ],
              ),
            ),
            // 多列滚轮时的列标题行（例如 年/月/日/时/分）。
            if (labels.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
                child: Row(
                  children: [
                    for (final label in labels) TaskNetWheelLabel(text: label),
                  ],
                ),
              ),
            // 滚轮区域：包含中心高亮带和实际滚轮内容。
            SizedBox(
              height: wheelHeight,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 中心高亮带：标识当前真正被选中的那一行。
                  Positioned(
                    left: 16,
                    right: 16,
                    child: Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: darkMode
                            ? const Color(0xFF263128)
                            : const Color(0xFFEFE9DE),
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  // 业务方传入的滚轮主体（单列或多列）。
                  child,
                ],
              ),
            ),
            ...(footer == null ? const <Widget>[] : <Widget>[footer!]),
            const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }
}

/// 滚轮顶部列标签。
///
/// 对应每一列滚轮顶部的字段名（如“年”“月”“日”）。
class TaskNetWheelLabel extends StatelessWidget {
  const TaskNetWheelLabel({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        // 每个标签在横向平均分配宽度，与下方列宽一一对应。
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF9EB0A6)
                : const Color(0xFF7D776D),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// 单列滚轮。
///
/// 对应任意一个“独立可滚动列”（例如小时列、分钟列、标签列）。
class TaskNetWheelColumn extends StatelessWidget {
  const TaskNetWheelColumn({
    super.key,
    required this.controller,
    required this.itemCount,
    required this.displayBuilder,
    required this.onSelectedItemChanged,
  });

  final FixedExtentScrollController controller;
  final int itemCount;
  final String Function(int index) displayBuilder;
  final ValueChanged<int> onSelectedItemChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Expanded(
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: 42,
        diameterRatio: 1.55,
        physics: const FixedExtentScrollPhysics(),
        overAndUnderCenterOpacity: 0.45,
        squeeze: 1,
        onSelectedItemChanged: onSelectedItemChanged,
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: itemCount,
          // 列内每个 item 都通过外部 displayBuilder 生成文本，确保组件通用。
          builder: (context, index) => Center(
            child: Text(
              displayBuilder(index),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
