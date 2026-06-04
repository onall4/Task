/*
 * TaskNet 根导航壳。
 *
 * 这个文件负责承载第一版应用的整体页面框架：
 * - 顶部信息栏
 * - 底部导航栏
 * - 首页与设置页切换
 *
 * 它是第一版产品结构的骨架文件，后续新增页面也会从这里继续扩展。
 */
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;

import '../../../app/preferences/app_preferences.dart';
import '../../calendar/data/calendar_controller.dart';
import '../../calendar/presentation/calendar_page.dart';
import '../../focus/presentation/focus_page.dart';
import '../../settings/presentation/settings_page.dart';
import '../../tasks/data/task_repository.dart';
import '../../tasks/presentation/home_page.dart';
import '../../tasks/presentation/quadrant_page.dart';
import '../../tasks/presentation/task_editor_page.dart';

/// 当前底部导航选中页索引。
///
/// 第一版只有首页和设置页，使用简单整数状态就足够表达页面切换。
final navigationIndexProvider = StateProvider<int>((ref) => 0);

/// 应用根页面容器。
///
/// 负责拼装顶部信息栏、底部导航栏和页面内容区。
class TaskNetShell extends ConsumerWidget {
  const TaskNetShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selectedIndex = ref.watch(navigationIndexProvider);
    final isSelectionMode = ref.watch(taskSelectionModeProvider);
    final selectedIds = ref.watch(selectedTaskIdsProvider);
    final selectedLabel = ref.watch(selectedTaskLabelProvider);
    final calendarSubPageIndex = ref.watch(calendarSubPageIndexProvider);
    final focusSubPageIndex = ref.watch(focusSubPageIndexProvider);
    final calendarMonthRange = ref.watch(calendarVisibleMonthRangeProvider);
    final ownedLabels = ref.watch(taskLabelsProvider);
    final strings = ref.watch(appStringsProvider);
    final pages = const [
      HomePage(),
      QuadrantPage(),
      CalendarPage(),
      FocusPage(),
      SettingsPage(),
    ];
    final brightness = theme.brightness;
    final shellBackgroundColor = theme.scaffoldBackgroundColor;
    final hasSelection = selectedIds.isNotEmpty;
    final isHomeSelectionMode = selectedIndex == 0 && isSelectionMode;
    final homeTitle = selectedLabel == null
        ? strings.inbox
        : strings.taskLabelName(selectedLabel);
    final calendarMonthLabel = strings.formatCalendarMonthRange(
      calendarMonthRange.startMonth,
      calendarMonthRange.endMonth,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
        statusBarBrightness: brightness == Brightness.dark
            ? Brightness.dark
            : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
      child: PopScope<void>(
        canPop: !isHomeSelectionMode,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) {
            return;
          }
          final currentIndex = ref.read(navigationIndexProvider);
          final inSelectionMode = ref.read(taskSelectionModeProvider);
          if (currentIndex == 0 && inSelectionMode) {
            _exitSelectionMode(ref);
            return;
          }
          SystemNavigator.pop();
        },
        child: Scaffold(
          drawer: _TaskSidebar(
            selectedLabel: selectedLabel,
            ownedLabels: ownedLabels,
            onSelectInbox: () {
              ref.read(selectedTaskLabelProvider.notifier).state = null;
            },
            onSelectLabel: (labelId) {
              ref.read(selectedTaskLabelProvider.notifier).state = labelId;
            },
            onLabelsChanged: (labels) async {
              ref.read(taskLabelsProvider.notifier).state = labels;
              final snapshot = AppPreferencesSnapshot(
                darkMode: ref.read(darkModeProvider),
                language: ref.read(appLanguageProvider),
                taskLabels: labels,
              );
              await ref.read(appPreferencesStorageProvider).save(snapshot);
            },
            onDeleteLabels: (labels) async {
              await ref.read(taskRepositoryProvider).clearLabels(labels);
              final currentLabel = ref.read(selectedTaskLabelProvider);
              if (currentLabel != null && labels.contains(currentLabel)) {
                ref.read(selectedTaskLabelProvider.notifier).state = null;
              }
            },
          ),
          backgroundColor: shellBackgroundColor,
          body: Column(
            children: [
              _SystemTopBand(
                color: shellBackgroundColor,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: selectedIndex == 0
                      ? Builder(
                          builder: (shellContext) => _PageInfoBar(
                            key: const ValueKey('home-info-bar'),
                            page: _ShellPage.home,
                            isSelectionMode: isHomeSelectionMode,
                            selectedCount: selectedIds.length,
                            onExitSelection: isSelectionMode
                                ? () => _exitSelectionMode(ref)
                                : null,
                            onDeleteSelected: hasSelection
                                ? () => _confirmAndDeleteSelected(context, ref)
                                : null,
                            onPrimaryAction: () => Navigator.of(
                              context,
                            ).push(buildTaskEditorRoute()),
                            onOpenSidebar: () =>
                                Scaffold.of(shellContext).openDrawer(),
                            homeTitle: homeTitle,
                          ),
                        )
                      : selectedIndex == 1
                      ? const _PageInfoBar(
                          key: ValueKey('quadrant-info-bar'),
                          page: _ShellPage.quadrant,
                        )
                      : selectedIndex == 2
                      ? _PageInfoBar(
                          key: const ValueKey('calendar-info-bar'),
                          page: _ShellPage.calendar,
                          calendarMonthLabel: calendarMonthLabel,
                          calendarSubPageIndex: calendarSubPageIndex,
                          onCalendarSubPageSelected: (index) {
                            final notifier = ref.read(
                              calendarSubPageIndexProvider.notifier,
                            );
                            notifier.state = index;
                          },
                        )
                      : selectedIndex == 3
                      ? _PageInfoBar(
                          key: const ValueKey('focus-info-bar'),
                          page: _ShellPage.focus,
                          focusSubPageIndex: focusSubPageIndex,
                          onFocusSubPageSelected: (index) {
                            ref.read(focusSubPageIndexProvider.notifier).state =
                                index;
                          },
                        )
                      : const _PageInfoBar(
                          key: ValueKey('settings-info-bar'),
                          page: _ShellPage.settings,
                        ),
                ),
              ),
              Expanded(
                child: _ShellBackground(
                  color: shellBackgroundColor,
                  child: IndexedStack(index: selectedIndex, children: pages),
                ),
              ),
            ],
          ),
          bottomNavigationBar: _ShellBottomNavigationBar(
            selectedIndex: selectedIndex,
            homeLabel: strings.home,
            quadrantLabel: strings.quadrants,
            calendarLabel: strings.calendar,
            focusLabel: strings.focus,
            settingsLabel: strings.settings,
            onDestinationSelected: (index) {
              if (index != 0) {
                _exitSelectionMode(ref);
              }
              ref.read(navigationIndexProvider.notifier).state = index;
            },
          ),
        ),
      ),
    );
  }

  Future<void> _confirmAndDeleteSelected(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final selectedIds = ref.read(selectedTaskIdsProvider);
    if (selectedIds.isEmpty) {
      return;
    }

    final strings = ref.read(appStringsProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.deleteSelectedTasksTitle),
        content: Text(strings.deleteSelectedTasksMessage(selectedIds.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.delete),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    await ref.read(taskRepositoryProvider).deleteTasks(selectedIds);
    await ref.read(taskScheduleControllerProvider.notifier).removeSchedules(
          selectedIds,
        );
    _exitSelectionMode(ref);
  }

  /// 退出首页多选模式并清空选中集合。
  void _exitSelectionMode(WidgetRef ref) {
    ref.read(taskSelectionModeProvider.notifier).state = false;
    ref.read(selectedTaskIdsProvider.notifier).state = <String>{};
  }
}

/// 顶部系统状态栏和应用信息栏的统一背景带。
///
/// 这个组件把手机状态栏安全区和应用顶部信息栏放在同一个背景色里，避免两段颜色断开。
class _SystemTopBand extends StatelessWidget {
  const _SystemTopBand({required this.color, required this.child});

  /// 状态栏和顶部信息栏共同使用的颜色。
  final Color color;

  /// 顶部信息栏内容。
  final Widget child;

  @override
  /// 构建带安全区的顶部背景。
  Widget build(BuildContext context) {
    return ColoredBox(
      color: color,
      child: SafeArea(bottom: false, child: child),
    );
  }
}

/// 应用内容区背景。
///
/// 主题切换时使用同一个动画容器过渡整块内容背景，让页面颜色和导航栏变化节奏一致。
class _ShellBackground extends StatelessWidget {
  const _ShellBackground({required this.color, required this.child});

  /// 内容区背景色。
  final Color color;

  /// 当前页面内容。
  final Widget child;

  @override
  /// 构建带动画的内容背景。
  Widget build(BuildContext context) {
    return ColoredBox(color: color, child: child);
  }
}

/// 应用壳当前可展示的页面。
///
/// 顶部信息栏通过这个枚举选择本地化页面标题，避免在父组件里手写重复判断。
enum _ShellPage { home, quadrant, calendar, focus, settings }

/// 页面顶部信息栏。
///
/// 这个栏位只展示当前页面的基础名称，保持和底部导航栏一样的横向满屏结构。
class _PageInfoBar extends ConsumerWidget {
  const _PageInfoBar({
    super.key,
    required this.page,
    this.isSelectionMode = false,
    this.selectedCount = 0,
    this.onExitSelection,
    this.onDeleteSelected,
    this.onPrimaryAction,
    this.onOpenSidebar,
    this.homeTitle,
    this.calendarMonthLabel,
    this.calendarSubPageIndex,
    this.onCalendarSubPageSelected,
    this.focusSubPageIndex,
    this.onFocusSubPageSelected,
  });

  /// 当前页面类型。
  final _ShellPage page;

  /// 当前是否处于多选模式。
  final bool isSelectionMode;

  /// 当前已选中的任务数量。
  final int selectedCount;

  /// 退出多选模式。
  final VoidCallback? onExitSelection;

  /// 删除所有选中项。
  final VoidCallback? onDeleteSelected;

  /// 顶部右侧主操作，仅首页展示。
  final VoidCallback? onPrimaryAction;

  /// 打开侧边栏。
  final VoidCallback? onOpenSidebar;

  /// 首页当前标题（收集箱或当前标签名）。
  final String? homeTitle;

  /// 日历页当前月份标题。
  final String? calendarMonthLabel;

  /// 日历页当前子页面索引。
  final int? calendarSubPageIndex;

  /// 顶部点击切换日历子页面。
  final ValueChanged<int>? onCalendarSubPageSelected;

  /// 专注页当前子页面索引。
  final int? focusSubPageIndex;

  /// 顶部点击切换专注子页面。
  final ValueChanged<int>? onFocusSubPageSelected;

  @override
  /// 构建横跨屏幕宽度的轻量信息栏。
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final strings = ref.watch(appStringsProvider);
    final title = switch (page) {
      _ShellPage.home => strings.home,
      _ShellPage.quadrant => strings.quadrants,
      _ShellPage.calendar => strings.calendar,
      _ShellPage.focus => strings.focus,
      _ShellPage.settings => strings.settings,
    };
    final titleColor = theme.textTheme.titleLarge?.color;

    return Container(
      width: double.infinity,
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          if (isSelectionMode) ...[
            IconButton(
              tooltip: strings.exitSelectionTooltip,
              onPressed: onExitSelection,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.arrow_back_rounded, size: 22, color: titleColor),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                strings.selectedCountLabel(selectedCount),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: titleColor,
                ),
              ),
            ),
            IconButton(
              tooltip: strings.deleteSelectedTasksTooltip,
              onPressed: onDeleteSelected,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 24,
                color: titleColor,
              ),
            ),
          ] else ...[
            if (page == _ShellPage.home) ...[
              IconButton(
                tooltip: strings.openSidebarTooltip,
                onPressed: onOpenSidebar,
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.menu_rounded, size: 22, color: titleColor),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  homeTitle ?? strings.inbox,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                  ),
                ),
              ),
            ] else if (page == _ShellPage.focus) ...[
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ShellTopTab(
                      label: strings.pomodoro,
                      selected: (focusSubPageIndex ?? 0) == 0,
                      onTap: () => onFocusSubPageSelected?.call(0),
                    ),
                    const SizedBox(width: 12),
                    _ShellTopTab(
                      label: strings.statistics,
                      selected: (focusSubPageIndex ?? 0) == 1,
                      onTap: () => onFocusSubPageSelected?.call(1),
                    ),
                  ],
                ),
              ),
            ] else if (page == _ShellPage.calendar) ...[
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 112),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          transitionBuilder: (child, animation) {
                            final slide =
                                Tween<Offset>(
                                  begin: const Offset(0, 0.18),
                                  end: Offset.zero,
                                ).animate(
                                  CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOutCubic,
                                  ),
                                );
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: slide,
                                child: child,
                              ),
                            );
                          },
                          child: Text(
                            calendarMonthLabel ?? title,
                            key: ValueKey(calendarMonthLabel ?? title),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: titleColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ShellTopTab(
                          label: strings.calendarTodo,
                          selected: (calendarSubPageIndex ?? 0) == 0,
                          onTap: () => onCalendarSubPageSelected?.call(0),
                        ),
                        const SizedBox(width: 12),
                        _ShellTopTab(
                          label: strings.calendarHabits,
                          selected: (calendarSubPageIndex ?? 0) == 1,
                          onTap: () => onCalendarSubPageSelected?.call(1),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ] else
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                  ),
                ),
              ),
            if (page == _ShellPage.home && onPrimaryAction != null)
              IconButton(
                tooltip: strings.newTask,
                onPressed: onPrimaryAction,
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.add_rounded, size: 24, color: titleColor),
              ),
          ],
        ],
      ),
    );
  }
}

class _ShellTopTab extends StatelessWidget {
  const _ShellTopTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final darkMode = theme.brightness == Brightness.dark;
    final selectedBackground = darkMode
        ? const Color(0xFF2A3A33)
        : const Color(0xFFE5EFE9);
    final selectedForeground = darkMode
        ? const Color(0xFFA8D4C5)
        : const Color(0xFF33544B);
    final unselectedForeground = theme.textTheme.bodyMedium?.color;
    final borderRadius = BorderRadius.circular(999);

    return Container(
      decoration: BoxDecoration(
        color: selected ? selectedBackground : Colors.transparent,
        borderRadius: borderRadius,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: borderRadius,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text(
              label,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? selectedForeground : unselectedForeground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskSidebar extends ConsumerStatefulWidget {
  const _TaskSidebar({
    required this.selectedLabel,
    required this.ownedLabels,
    required this.onSelectInbox,
    required this.onSelectLabel,
    required this.onLabelsChanged,
    required this.onDeleteLabels,
  });

  final String? selectedLabel;
  final List<String> ownedLabels;
  final VoidCallback onSelectInbox;
  final ValueChanged<String> onSelectLabel;
  final Future<void> Function(List<String> labels) onLabelsChanged;
  final Future<void> Function(Set<String> labels) onDeleteLabels;

  @override
  ConsumerState<_TaskSidebar> createState() => _TaskSidebarState();
}

class _TaskSidebarState extends ConsumerState<_TaskSidebar> {
  var _labelSelectionMode = false;
  final _selectedLabels = <String>{};

  @override
  void didUpdateWidget(covariant _TaskSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _selectedLabels.removeWhere((label) => !widget.ownedLabels.contains(label));
    if (_selectedLabels.isEmpty) {
      _labelSelectionMode = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final theme = Theme.of(context);
    final darkMode = theme.brightness == Brightness.dark;
    final canDelete = _selectedLabels.isNotEmpty;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: darkMode
                            ? const Color(0xFF2E3C35)
                            : const Color(0xFFE4EFE8),
                        child: Icon(
                          Icons.person_rounded,
                          color: darkMode
                              ? const Color(0xFFC6DDD3)
                              : const Color(0xFF4C6B60),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          strings.sidebarUserName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.inbox_rounded),
                    title: Text(strings.inbox),
                    selected: widget.selectedLabel == null,
                    onTap: _labelSelectionMode
                        ? null
                        : () {
                            widget.onSelectInbox();
                            Navigator.of(context).pop();
                          },
                  ),
                  const Divider(height: 1),
                  for (final label in widget.ownedLabels)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: _labelSelectionMode
                          ? Icon(
                              _selectedLabels.contains(label)
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked_rounded,
                            )
                          : const Icon(Icons.label_outline_rounded),
                      title: Text(strings.taskLabelName(label)),
                      selected: _labelSelectionMode
                          ? _selectedLabels.contains(label)
                          : widget.selectedLabel == label,
                      onLongPress: () => _toggleLabelSelection(label),
                      onTap: () {
                        if (_labelSelectionMode) {
                          _toggleLabelSelection(label);
                          return;
                        }
                        widget.onSelectLabel(label);
                        Navigator.of(context).pop();
                      },
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            SizedBox(
              height: 54,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _labelSelectionMode
                          ? strings.selectedCountLabel(_selectedLabels.length)
                          : '',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: _labelSelectionMode
                        ? strings.deleteLabelTooltip
                        : strings.addLabelTooltip,
                    onPressed: _labelSelectionMode
                        ? (canDelete ? _deleteSelectedLabels : null)
                        : _showCreateLabelDialog,
                    icon: Icon(
                      _labelSelectionMode
                          ? Icons.delete_outline_rounded
                          : Icons.add_rounded,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleLabelSelection(String label) {
    setState(() {
      _labelSelectionMode = true;
      if (!_selectedLabels.add(label)) {
        _selectedLabels.remove(label);
      }
      if (_selectedLabels.isEmpty) {
        _labelSelectionMode = false;
      }
    });
  }

  Future<void> _showCreateLabelDialog() async {
    final strings = ref.read(appStringsProvider);
    final created = await showDialog<String>(
      context: context,
      builder: (context) {
        return _CreateLabelDialog(
          strings: strings,
          existingLabels: widget.ownedLabels,
        );
      },
    );
    if (created == null) {
      return;
    }

    final updated = [...widget.ownedLabels, created];
    await widget.onLabelsChanged(updated);
  }

  Future<void> _deleteSelectedLabels() async {
    final strings = ref.read(appStringsProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.deleteLabelsTitle),
        content: Text(strings.deleteLabelsMessage(_selectedLabels.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    final deleting = Set<String>.from(_selectedLabels);
    final updated = widget.ownedLabels
        .where((label) => !deleting.contains(label))
        .toList(growable: false);
    await widget.onLabelsChanged(updated);
    await widget.onDeleteLabels(deleting);
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedLabels.clear();
      _labelSelectionMode = false;
    });
  }
}

class _CreateLabelDialog extends StatefulWidget {
  const _CreateLabelDialog({
    required this.strings,
    required this.existingLabels,
  });

  final AppStrings strings;
  final List<String> existingLabels;

  @override
  State<_CreateLabelDialog> createState() => _CreateLabelDialogState();
}

class _CreateLabelDialogState extends State<_CreateLabelDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.strings.createLabelTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 10,
        decoration: InputDecoration(
          hintText: widget.strings.createLabelHint,
          errorText: _errorText,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.strings.cancel),
        ),
        FilledButton(
          onPressed: () {
            final value = _controller.text.trim();
            if (value.isEmpty) {
              setState(() => _errorText = widget.strings.labelRequired);
              return;
            }
            if (value.length > 10) {
              setState(() => _errorText = widget.strings.labelTooLong);
              return;
            }
            if (widget.existingLabels.contains(value)) {
              setState(() => _errorText = widget.strings.labelAlreadyExists);
              return;
            }
            Navigator.of(context).pop(value);
          },
          child: Text(widget.strings.save),
        ),
      ],
    );
  }
}

/// 底部导航栏容器。
///
/// 使用 Flutter 自己绘制导航栏下方的安全区背景，再把系统底部区域设为透明，
/// 这样底部那一小块区域就能和页面其他部分一起跟随同一个主题补间过渡。
class _ShellBottomNavigationBar extends StatelessWidget {
  const _ShellBottomNavigationBar({
    required this.selectedIndex,
    required this.homeLabel,
    required this.quadrantLabel,
    required this.calendarLabel,
    required this.focusLabel,
    required this.settingsLabel,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final String homeLabel;
  final String quadrantLabel;
  final String calendarLabel;
  final String focusLabel;
  final String settingsLabel;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final navigationTheme = NavigationBarTheme.of(context);
    final backgroundColor =
        navigationTheme.backgroundColor ?? theme.scaffoldBackgroundColor;

    return ColoredBox(
      color: backgroundColor,
      child: SafeArea(
        top: false,
        child: NavigationBar(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.checklist_rounded),
              selectedIcon: const Icon(Icons.checklist_rtl_rounded),
              label: homeLabel,
            ),
            NavigationDestination(
              icon: const Icon(Icons.grid_view_outlined),
              selectedIcon: const Icon(Icons.grid_view_rounded),
              label: quadrantLabel,
            ),
            NavigationDestination(
              icon: const Icon(Icons.calendar_month_outlined),
              selectedIcon: const Icon(Icons.calendar_month_rounded),
              label: calendarLabel,
            ),
            NavigationDestination(
              icon: const Icon(Icons.timer_outlined),
              selectedIcon: const Icon(Icons.timer_rounded),
              label: focusLabel,
            ),
            NavigationDestination(
              icon: const Icon(Icons.tune_rounded),
              selectedIcon: const Icon(Icons.tune_rounded),
              label: settingsLabel,
            ),
          ],
        ),
      ),
    );
  }
}
