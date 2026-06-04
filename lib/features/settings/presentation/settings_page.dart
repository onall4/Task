/*
 * 设置页文件。
 *
 * 这个文件负责承载第一版已经开放给用户调整的应用偏好：
 * - 深色模式
 * - 应用语言
 *
 * 设置项保持和首页卡片一致的柔和、克制风格，避免默认表单控件显得突兀。
 */
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/preferences/app_preferences.dart';

/// 第一版设置页。
///
/// 当前提供外观和语言两类轻量偏好，后续账号、同步、提醒等设置也会继续放在这里。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  /// 构建设置页内容。
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final darkMode = ref.watch(darkModeProvider);
    final language = ref.watch(appLanguageProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        _SettingsPanel(
          children: [
            _SettingsRow(
              title: strings.darkMode,
              trailing: Switch.adaptive(
                value: darkMode,
                onChanged: (value) {
                  ref.read(darkModeProvider.notifier).state = value;
                  unawaited(_persistPreferences(ref, darkMode: value));
                },
              ),
            ),
            const _SettingsDivider(),
            _SettingsRow(
              title: strings.languageLabel,
              trailing: _LanguageMenuButton(
                language: language,
                strings: strings,
                onSelected: (value) {
                  ref.read(appLanguageProvider.notifier).state = value;
                  unawaited(_persistPreferences(ref, language: value));
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 把当前设置写入本地文件。
  ///
  /// 调用方会先更新 UI 状态，再异步触发保存，避免文件 IO 阻塞设置切换动画。
  Future<void> _persistPreferences(
    WidgetRef ref, {
    bool? darkMode,
    AppLanguage? language,
  }) async {
    final snapshot = AppPreferencesSnapshot(
      darkMode: darkMode ?? ref.read(darkModeProvider),
      language: language ?? ref.read(appLanguageProvider),
      taskLabels: ref.read(taskLabelsProvider),
    );
    await ref.read(appPreferencesStorageProvider).save(snapshot);
  }
}

/// 设置页卡片容器。
///
/// 使用单个柔和容器承载设置项，让页面既简洁又和首页任务卡片保持同一视觉语言。
class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({required this.children});

  /// 设置卡片在深浅色之间切换时使用统一的过渡时长。

  /// 当前设置卡片中的所有子项。
  final List<Widget> children;

  @override
  /// 构建设置卡片容器。
  Widget build(BuildContext context) {
    final darkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: darkMode
            ? const Color(0xFF202822).withValues(alpha: 0.94)
            : Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: darkMode ? const Color(0xFF354239) : const Color(0xFFE8DED0),
        ),
      ),
      child: Column(children: children),
    );
  }
}

/// 设置页中的单行设置项。
///
/// 统一标题、右侧控件和触摸高度，保证深色模式与语言项看起来像同一组功能。
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.title, required this.trailing});

  /// 设置项标题。
  final String title;

  /// 设置项右侧控件。
  final Widget trailing;

  @override
  /// 构建单行设置项。
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

/// 设置项之间的分隔线。
///
/// 使用轻量缩进分隔线，避免两行设置内容粘在一起。
class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  /// 构建设置项分隔线。
  Widget build(BuildContext context) {
    final darkMode = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Divider(
        height: 1,
        thickness: 0.8,
        color: darkMode ? const Color(0xFF334039) : const Color(0xFFEDE4D8),
      ),
    );
  }
}

/// 语言选择菜单按钮。
///
/// 按钮采用胶囊外观，弹出的菜单项带有选中标记和语言说明，避免默认下拉菜单过于朴素。
class _LanguageMenuButton extends StatelessWidget {
  const _LanguageMenuButton({
    required this.language,
    required this.strings,
    required this.onSelected,
  });

  /// 当前选中的语言。
  final AppLanguage language;

  /// 当前应用文案集合。
  final AppStrings strings;

  /// 用户选中语言后的回调。
  final ValueChanged<AppLanguage> onSelected;

  @override
  /// 构建语言选择按钮和弹出菜单。
  Widget build(BuildContext context) {
    final darkMode = Theme.of(context).brightness == Brightness.dark;
    final label = language == AppLanguage.zh
        ? strings.chinese
        : strings.english;
    final foreground = darkMode
        ? const Color(0xFFEAF1EC)
        : const Color(0xFF33544B);
    final background = darkMode
        ? const Color(0xFF263128)
        : const Color(0xFFE8F1EB);

    return PopupMenuButton<AppLanguage>(
      tooltip: strings.chooseLanguageTooltip,
      onSelected: onSelected,
      color: darkMode ? const Color(0xFF202822) : const Color(0xFFFFFCF7),
      elevation: 10,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: darkMode ? const Color(0xFF354239) : const Color(0xFFE8DED0),
        ),
      ),
      itemBuilder: (context) => [
        _buildLanguageItem(
          language: AppLanguage.zh,
          selected: language == AppLanguage.zh,
          title: strings.chinese,
          subtitle: strings.chineseSubtitle,
        ),
        _buildLanguageItem(
          language: AppLanguage.en,
          selected: language == AppLanguage.en,
          title: strings.english,
          subtitle: strings.englishSubtitle,
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: darkMode ? const Color(0xFF3B4A41) : const Color(0xFFD7E7DD),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: foreground,
            ),
          ],
        ),
      ),
    );
  }

  /// 构建单个语言菜单项。
  ///
  /// 菜单项内部使用选中圆点和勾选图标，帮助用户快速判断当前语言。
  PopupMenuItem<AppLanguage> _buildLanguageItem({
    required AppLanguage language,
    required bool selected,
    required String title,
    required String subtitle,
  }) {
    return PopupMenuItem<AppLanguage>(
      value: language,
      child: _LanguageMenuItem(
        selected: selected,
        title: title,
        subtitle: subtitle,
      ),
    );
  }
}

/// 语言菜单中的单个选项。
///
/// 通过圆点、标题、副标题和勾选图标组合出更像应用原生设置项的菜单体验。
class _LanguageMenuItem extends StatelessWidget {
  const _LanguageMenuItem({
    required this.selected,
    required this.title,
    required this.subtitle,
  });

  /// 当前选项是否已被选中。
  final bool selected;

  /// 语言名称。
  final String title;

  /// 语言补充说明。
  final String subtitle;

  @override
  /// 构建语言菜单选项。
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final darkMode = theme.brightness == Brightness.dark;
    final accent = darkMode ? const Color(0xFFA8D4C5) : const Color(0xFF476C63);

    return SizedBox(
      width: 176,
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: selected ? accent : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(color: accent),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: darkMode
                        ? const Color(0xFF93A59B)
                        : const Color(0xFF72807A),
                  ),
                ),
              ],
            ),
          ),
          if (selected) Icon(Icons.check_rounded, size: 18, color: accent),
        ],
      ),
    );
  }
}
