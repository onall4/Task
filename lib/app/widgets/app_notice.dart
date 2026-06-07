/*
 * 应用通知组件。
 *
 * 这个文件提供统一的应用内轻提示，用于向用户展示临时消息。
 * 样式与当前主题一致，支持自动消失。
 */
import 'package:flutter/material.dart';

/// 统一的应用内轻提示样式。
///
/// 对应 app 里底部浮动提示条（轻量通知），用于替换默认 Snackbar 的生硬观感。
class TaskNetNotice {
  const TaskNetNotice._();

  /// 展示一条信息型提示。
  ///
  /// `content` 的 children 对应关系：
  /// - 左侧 `Icon`：提示类型图标（当前为信息）。
  /// - 右侧 `Expanded(Text)`：提示文案，自动换行避免裁切。
  static void showInfo(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.of(context);
    final theme = Theme.of(context);
    final darkMode = theme.brightness == Brightness.dark;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          elevation: 0,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          padding: EdgeInsets.zero,
          backgroundColor: Colors.transparent,
          duration: const Duration(milliseconds: 1650),
          content: Container(
            decoration: BoxDecoration(
              color: darkMode
                  ? const Color(0xFF202822).withValues(alpha: 0.96)
                  : Colors.white.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: darkMode
                    ? const Color(0xFF354239)
                    : const Color(0xFFE8DED0),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // 左侧提示图标。
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: darkMode
                      ? const Color(0xFFA8D4C5)
                      : const Color(0xFF476C63),
                ),
                const SizedBox(width: 8),
                Expanded(
                  // 右侧文本内容，撑满剩余宽度。
                  child: Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: darkMode
                          ? const Color(0xFFEAF1EC)
                          : const Color(0xFF2B3733),
                      fontWeight: FontWeight.w600,
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
