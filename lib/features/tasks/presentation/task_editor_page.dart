/*
 * 任务编辑页。
 *
 * 这个文件负责承载第一版任务编辑器的全部交互：
 * - 新建任务
 * - 编辑已有任务
 * - 截止时间选择
 * - 重要/紧急开关
 * - 退出时保存草稿确认
 * - 点击非输入区时收起输入法
 *
 * 当前版本额外针对移动端交互做了两点优化：
 * 1. 截止时间选择器改为更紧凑的五列滚轮底部弹窗。
 * 2. 所有非文本输入交互都会主动收起键盘，避免输入法遮挡页面。
 */
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/preferences/app_preferences.dart';
import '../../../app/widgets/app_notice.dart';
import '../../../app/widgets/wheel_picker.dart';
import '../data/task_repository.dart';

/// 任务编辑页。
///
/// 当 [taskId] 为空时表示创建模式，不为空时表示编辑模式。
class TaskEditorPage extends ConsumerStatefulWidget {
  const TaskEditorPage({
    super.key,
    this.taskId,
    this.initialValue = const TaskEditorValue(),
  });

  final String? taskId;
  final TaskEditorValue initialValue;

  @override
  /// 创建可维护表单状态的 State 对象。
  ConsumerState<TaskEditorPage> createState() => _TaskEditorPageState();
}

/// 构建任务编辑页路由。
///
/// 统一首页悬浮按钮和任务卡片的进入方式，避免不同入口各自维护路由细节。
Route<void> buildTaskEditorRoute({
  String? taskId,
  TaskEditorValue initialValue = const TaskEditorValue(),
}) {
  return MaterialPageRoute<void>(
    builder: (_) => TaskEditorPage(taskId: taskId, initialValue: initialValue),
  );
}

/// 任务编辑页状态实现。
///
/// 这一层负责维护表单控制器、截止时间和草稿保存判断等交互状态。
class _TaskEditorPageState extends ConsumerState<TaskEditorPage> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final FocusNode _titleFocusNode;
  late final FocusNode _descriptionFocusNode;

  late DateTime? _dueAt;
  late String? _selectedLabelId;
  late int _priority;
  late bool _isImportant;
  late bool _isUrgent;
  var _submitting = false;
  var _draftChecked = false;

  @override
  /// 初始化编辑器默认值，并在首帧后检查是否存在待恢复草稿。
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialValue.title);
    _descriptionController = TextEditingController(
      text: widget.initialValue.description,
    );
    _titleFocusNode = FocusNode();
    _descriptionFocusNode = FocusNode();
    _dueAt = widget.initialValue.endAt ?? widget.initialValue.dueAt;
    _selectedLabelId = widget.initialValue.label;
    _priority = widget.initialValue.priority;
    _isImportant = widget.initialValue.isImportant;
    _isUrgent = widget.initialValue.isUrgent;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _checkAndRestoreDraft();
    });
  }

  @override
  /// 释放输入框控制器和焦点节点，避免页面销毁后内存泄漏。
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _titleFocusNode.dispose();
    _descriptionFocusNode.dispose();
    super.dispose();
  }

  @override
  /// 构建任务编辑页界面。
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = ref.watch(appStringsProvider);
    final isEditing = widget.taskId != null;
    final darkMode = theme.brightness == Brightness.dark;

    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        final navigator = Navigator.of(context);
        final shouldClose = await _handleExitRequest();
        if (!mounted || !shouldClose) {
          return;
        }
        navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            isEditing ? strings.taskDetailsTitle : strings.createTaskTitle,
          ),
          leading: IconButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final shouldClose = await _handleExitRequest();
              if (!mounted || !shouldClose) {
                return;
              }
              navigator.pop();
            },
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          actions: [
            TextButton(
              onPressed: _submitting ? null : _submit,
              child: Text(strings.save),
            ),
          ],
        ),
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _dismissKeyboard,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              TextField(
                controller: _titleController,
                focusNode: _titleFocusNode,
                maxLength: 40,
                onTapOutside: (_) => _dismissKeyboard(),
                decoration: InputDecoration(
                  labelText: strings.titleLabel,
                  hintText: strings.titleHint,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _descriptionController,
                focusNode: _descriptionFocusNode,
                maxLines: 5,
                minLines: 4,
                maxLength: 240,
                onTapOutside: (_) => _dismissKeyboard(),
                decoration: InputDecoration(
                  labelText: strings.descriptionLabel,
                  hintText: strings.descriptionHint,
                ),
              ),
              const SizedBox(height: 22),
              ..._buildScheduleFields(theme, darkMode, strings),
              const SizedBox(height: 22),
              Text(strings.endTime, style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: _pickDueDateTime,
                child: Ink(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    color: darkMode ? const Color(0xFF1C241F) : Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: darkMode
                          ? const Color(0xFF334039)
                          : const Color(0xFFE5DBCF),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _buildDueDateSummary(),
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                      if (_dueAt != null)
                        IconButton(
                          onPressed: () {
                            _dismissKeyboard();
                            setState(() => _dueAt = null);
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(strings.taskLabel, style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: _pickLabel,
                child: Ink(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    color: darkMode ? const Color(0xFF1C241F) : Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: darkMode
                          ? const Color(0xFF334039)
                          : const Color(0xFFE5DBCF),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _buildLabelSummary(),
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                      if (_selectedLabelId != null)
                        IconButton(
                          onPressed: () {
                            _dismissKeyboard();
                            setState(() => _selectedLabelId = null);
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(strings.important),
                subtitle: Text(strings.importantSubtitle),
                value: _isImportant,
                onChanged: (value) {
                  _dismissKeyboard();
                  setState(() => _isImportant = value);
                },
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(strings.urgent),
                subtitle: Text(strings.urgentSubtitle),
                value: _isUrgent,
                onChanged: (value) {
                  _dismissKeyboard();
                  setState(() => _isUrgent = value);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 汇总当前表单值，生成统一的编辑器值对象。
  TaskEditorValue get _currentValue => TaskEditorValue(
    title: _titleController.text,
    description: _descriptionController.text,
    dueAt: _dueAt,
    endAt: _dueAt,
    label: _selectedLabelId,
    priority: _priority,
    isImportant: _isImportant,
    isUrgent: _isUrgent,
  );

  List<Widget> _buildScheduleFields(
    ThemeData theme,
    bool darkMode,
    AppStrings strings,
  ) {
    return [
      Text(strings.priority, style: theme.textTheme.titleMedium),
      const SizedBox(height: 12),
      _EditorPickerTile(
        darkMode: darkMode,
        value: strings.priorityName(_priority),
        onTap: _pickPriority,
      ),
    ];
  }

  /// 关闭当前页面上的输入焦点和输入法。
  ///
  /// 用于满足“点击标题和描述区域外部时收起键盘”的交互要求。
  void _dismissKeyboard() {
    _titleFocusNode.unfocus();
    _descriptionFocusNode.unfocus();
    FocusScope.of(context).unfocus();
  }

  /// 生成截止时间区域的摘要文本。
  ///
  /// 如果尚未设置截止时间，返回占位文案；否则返回包含日期和时间的完整文本。
  String _buildDueDateSummary() {
    if (_dueAt == null) {
      return ref.read(appStringsProvider).noEndTime;
    }

    final strings = ref.read(appStringsProvider);
    final datePart = DateFormat(
      strings.dateSummaryPattern,
      strings.dateLocale,
    ).format(_dueAt!);
    final timePart = DateFormat(
      strings.timeSummaryPattern,
      strings.dateLocale,
    ).format(_dueAt!);
    return '$datePart  $timePart';
  }

  /// 生成标签区域的摘要文本。
  String _buildLabelSummary() {
    final strings = ref.read(appStringsProvider);
    final labelId = _selectedLabelId;
    if (labelId == null) {
      return strings.noLabel;
    }
    return strings.taskLabelName(labelId);
  }

  /// 判断表单是否被修改过。
  bool get _isDirty {
    final value = _currentValue;
    return value.title.trim() != widget.initialValue.title.trim() ||
        value.description.trim() != widget.initialValue.description.trim() ||
        value.dueAt != widget.initialValue.dueAt ||
        value.endAt != widget.initialValue.endAt ||
        value.label != widget.initialValue.label ||
        value.priority != widget.initialValue.priority ||
        value.isImportant != widget.initialValue.isImportant ||
        value.isUrgent != widget.initialValue.isUrgent;
  }

  /// 检查是否存在上次未完成的草稿，仅针对新建任务自动恢复。
  Future<void> _checkAndRestoreDraft() async {
    if (_draftChecked) {
      return;
    }
    _draftChecked = true;

    if (widget.taskId != null) {
      return;
    }

    final repository = ref.read(taskRepositoryProvider);
    final draft = await repository.getDraft();
    if (draft == null) {
      return;
    }

    final draftValue = TaskEditorValue.fromDraft(draft);
    if (!draftValue.hasMeaningfulContent) {
      await repository.clearDraft();
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _titleController.text = draftValue.title;
      _descriptionController.text = draftValue.description;
      _dueAt = draftValue.dueAt;
      _selectedLabelId = draftValue.label;
      _priority = draftValue.priority;
      _isImportant = draftValue.isImportant;
      _isUrgent = draftValue.isUrgent;
    });
  }

  /// 处理页面退出请求。
  ///
  /// 新建任务退出时询问是否保存草稿，编辑已有任务退出时询问是否保存更改。
  Future<bool> _handleExitRequest() async {
    if (_submitting || !_isDirty) {
      return true;
    }

    final repository = ref.read(taskRepositoryProvider);
    final strings = ref.read(appStringsProvider);

    if (widget.taskId == null) {
      return _handleNewTaskExit(repository, strings);
    } else {
      return _handleEditTaskExit(strings);
    }
  }

  /// 新建任务退出确认 —— 询问是否保存草稿。
  Future<bool> _handleNewTaskExit(
    TaskRepository repository,
    AppStrings strings,
  ) async {
    final decision = await showDialog<_ExitDecision>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.saveDraftTitle),
        content: Text(strings.saveDraftMessage),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(_ExitDecision.cancel),
                child: Text(strings.keepEditing),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(_ExitDecision.discard),
                child: Text(strings.discardDraft),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(_ExitDecision.saveDraft),
                child: Text(strings.saveDraft),
              ),
            ],
          ),
        ],
      ),
    );

    switch (decision) {
      case _ExitDecision.saveDraft:
        if (_currentValue.hasMeaningfulContent) {
          await repository.saveDraft(_currentValue);
        }
        return true;
      case _ExitDecision.discard:
        await repository.clearDraft();
        return true;
      case _ExitDecision.cancel:
      case null:
        return false;
      case _ExitDecision.save:
        return false;
    }
  }

  /// 编辑已有任务退出确认 —— 询问是否保存更改。
  Future<bool> _handleEditTaskExit(AppStrings strings) async {
    final decision = await showDialog<_ExitDecision>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.saveChangesTitle),
        content: Text(strings.saveChangesMessage),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(_ExitDecision.cancel),
                child: Text(strings.keepEditing),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(_ExitDecision.discard),
                child: Text(strings.discardDraft),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(_ExitDecision.save),
                child: Text(strings.save),
              ),
            ],
          ),
        ],
      ),
    );

    switch (decision) {
      case _ExitDecision.save:
        await _submit();
        return false;
      case _ExitDecision.discard:
        return true;
      case _ExitDecision.cancel:
      case null:
        return false;
      case _ExitDecision.saveDraft:
        return false;
    }
  }

  /// 打开截止时间选择器。
  ///
  Future<void> _pickPriority() async {
    _dismissKeyboard();
    final strings = ref.read(appStringsProvider);
    final options = [1, 2, 3];
    var selectedIndex = options.indexOf(_priority);
    if (selectedIndex < 0) {
      selectedIndex = 0;
    }
    final controller = FixedExtentScrollController(initialItem: selectedIndex);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return _SingleWheelPickerSheet(
          strings: strings,
          title: strings.priority,
          controller: controller,
          itemCount: options.length,
          itemLabelBuilder: (index) => strings.priorityName(options[index]),
          onCancel: () => Navigator.of(context).pop(),
          onConfirm: () {
            setState(() => _priority = options[selectedIndex]);
            Navigator.of(context).pop();
          },
          onSelectedItemChanged: (index) => selectedIndex = index,
        );
      },
    );
  }

  Future<void> _pickDueDateTime() async {
    _dismissKeyboard();
    final strings = ref.read(appStringsProvider);

    final now = DateTime.now();
    final base = _dueAt ?? now;
    var selectedYear = base.year.clamp(now.year, 2100).toInt();
    var selectedMonth = base.month;
    var selectedDay = base.day;
    var selectedHour = (_dueAt ?? now).hour;
    var selectedMinute = (_dueAt ?? now).minute;

    int currentMaxDay() =>
        DateUtils.getDaysInMonth(selectedYear, selectedMonth);

    selectedDay = selectedDay.clamp(1, currentMaxDay()).toInt();

    final yearController = FixedExtentScrollController(
      initialItem: selectedYear - now.year,
    );
    final monthController = FixedExtentScrollController(
      initialItem: selectedMonth - 1,
    );
    final dayController = FixedExtentScrollController(
      initialItem: selectedDay - 1,
    );
    final hourController = FixedExtentScrollController(
      initialItem: selectedHour,
    );
    final minuteController = FixedExtentScrollController(
      initialItem: selectedMinute,
    );

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final maxDay = currentMaxDay();
            final dayItems = List<int>.generate(maxDay, (index) => index + 1);

            void syncDayWithinRange() {
              if (selectedDay > maxDay) {
                selectedDay = maxDay;
                dayController.jumpToItem(selectedDay - 1);
              }
            }

            return _DeadlinePickerSheet(
              yearController: yearController,
              monthController: monthController,
              dayController: dayController,
              hourController: hourController,
              minuteController: minuteController,
              dayItems: dayItems,
              startYear: now.year,
              strings: strings,
              onCancel: () => Navigator.of(context).pop(),
              onConfirm: () {
                setState(() {
                  _dueAt = DateTime(
                    selectedYear,
                    selectedMonth,
                    selectedDay,
                    selectedHour,
                    selectedMinute,
                  );
                });
                Navigator.of(context).pop();
              },
              onYearChanged: (index) {
                setModalState(() {
                  selectedYear = now.year + index;
                  syncDayWithinRange();
                });
              },
              onMonthChanged: (index) {
                setModalState(() {
                  selectedMonth = index + 1;
                  syncDayWithinRange();
                });
              },
              onDayChanged: (index) {
                selectedDay = index + 1;
              },
              onHourChanged: (index) {
                selectedHour = index;
              },
              onMinuteChanged: (index) {
                selectedMinute = index;
              },
            );
          },
        );
      },
    );

    _dismissKeyboard();
  }

  /// 打开标签选择器。
  Future<void> _pickLabel() async {
    _dismissKeyboard();
    final strings = ref.read(appStringsProvider);
    final userLabels = ref.read(taskLabelsProvider);
    final labelOptions = <String?>[null, ...userLabels];
    var selectedIndex = _selectedLabelId == null
        ? 0
        : labelOptions.indexOf(_selectedLabelId);
    if (selectedIndex < 0) {
      selectedIndex = 0;
    }

    final controller = FixedExtentScrollController(initialItem: selectedIndex);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return _SingleWheelPickerSheet(
          strings: strings,
          title: strings.taskLabel,
          controller: controller,
          itemCount: labelOptions.length,
          itemLabelBuilder: (index) {
            final option = labelOptions[index];
            if (option == null) {
              return strings.noLabel;
            }
            return strings.taskLabelName(option);
          },
          onCancel: () => Navigator.of(context).pop(),
          onConfirm: () {
            setState(() => _selectedLabelId = labelOptions[selectedIndex]);
            Navigator.of(context).pop();
          },
          onSelectedItemChanged: (index) => selectedIndex = index,
        );
      },
    );

    _dismissKeyboard();
  }

  /// 提交当前表单。
  ///
  /// 会先校验标题，再根据是否存在 [taskId] 决定执行创建还是更新，
  /// 操作成功后再清理草稿并返回上一页；失败时恢复按钮状态并提示错误。
  Future<void> _submit() async {
    final trimmedTitle = _titleController.text.trim();
    if (trimmedTitle.isEmpty) {
      TaskNetNotice.showInfo(
        context,
        ref.read(appStringsProvider).titleRequired,
      );
      return;
    }
    _dismissKeyboard();
    setState(() => _submitting = true);
    final repository = ref.read(taskRepositoryProvider);
    final scheduleController = ref.read(taskScheduleControllerProvider.notifier);
    final savingValue = _currentValue.copyWith(title: trimmedTitle);

    try {
      if (widget.taskId == null) {
        final taskId = await repository.createTask(savingValue);
        await scheduleController.saveSchedule(
          taskId,
          savingValue.toScheduleMetadata(),
        );
        await repository.clearDraft();
      } else {
        await repository.updateTask(widget.taskId!, savingValue);
        await scheduleController.saveSchedule(
          widget.taskId!,
          savingValue.toScheduleMetadata(),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _submitting = false);
      TaskNetNotice.showInfo(
        context,
        ref.read(appStringsProvider).taskSaveFailed(error),
      );
      return;
    }

    if (!mounted) {
      return;
    }

    Navigator.of(context).pop();
  }
}

/// 截止时间选择底部弹窗。
///
/// 这个组件把标题栏、列标签、滚轮区和中心高亮区组织成一个更统一的视觉结构，
/// 避免使用默认样式时出现“提示文字过大”“选中项不在视觉中心”这类问题。
class _EditorPickerTile extends StatelessWidget {
  const _EditorPickerTile({
    required this.darkMode,
    required this.value,
    required this.onTap,
  });

  final bool darkMode;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        decoration: BoxDecoration(
          color: darkMode ? const Color(0xFF1C241F) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: darkMode ? const Color(0xFF334039) : const Color(0xFFE5DBCF),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(value, style: Theme.of(context).textTheme.bodyLarge),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _DeadlinePickerSheet extends StatelessWidget {
  const _DeadlinePickerSheet({
    required this.yearController,
    required this.monthController,
    required this.dayController,
    required this.hourController,
    required this.minuteController,
    required this.dayItems,
    required this.startYear,
    required this.strings,
    required this.onCancel,
    required this.onConfirm,
    required this.onYearChanged,
    required this.onMonthChanged,
    required this.onDayChanged,
    required this.onHourChanged,
    required this.onMinuteChanged,
  });

  /// 年列滚轮控制器。
  final FixedExtentScrollController yearController;

  /// 月列滚轮控制器。
  final FixedExtentScrollController monthController;

  /// 日列滚轮控制器。
  final FixedExtentScrollController dayController;

  /// 小时列滚轮控制器。
  final FixedExtentScrollController hourController;

  /// 分钟列滚轮控制器。
  final FixedExtentScrollController minuteController;

  /// 当前月份可选的日期集合。
  final List<int> dayItems;

  /// 年份起始值。
  final int startYear;

  /// 当前应用文案集合。
  final AppStrings strings;

  /// 取消按钮回调。
  final VoidCallback onCancel;

  /// 确认按钮回调。
  final VoidCallback onConfirm;

  /// 年份变化回调。
  final ValueChanged<int> onYearChanged;

  /// 月份变化回调。
  final ValueChanged<int> onMonthChanged;

  /// 日期变化回调。
  final ValueChanged<int> onDayChanged;

  /// 小时变化回调。
  final ValueChanged<int> onHourChanged;

  /// 分钟变化回调。
  final ValueChanged<int> onMinuteChanged;

  @override
  /// 构建截止时间选择底部弹窗。
  Widget build(BuildContext context) {
    return TaskNetWheelSheetFrame(
      title: strings.dueDate,
      cancelText: strings.cancel,
      confirmText: strings.save,
      onCancel: onCancel,
      onConfirm: onConfirm,
      labels: [
        strings.year,
        strings.month,
        strings.day,
        strings.hour,
        strings.minute,
      ],
      child: Row(
        children: [
          TaskNetWheelColumn(
            controller: yearController,
            itemCount: 2100 - startYear + 1,
            displayBuilder: (index) => '${startYear + index}',
            onSelectedItemChanged: onYearChanged,
          ),
          TaskNetWheelColumn(
            controller: monthController,
            itemCount: 12,
            displayBuilder: (index) => '${index + 1}',
            onSelectedItemChanged: onMonthChanged,
          ),
          TaskNetWheelColumn(
            controller: dayController,
            itemCount: dayItems.length,
            displayBuilder: (index) => '${dayItems[index]}',
            onSelectedItemChanged: onDayChanged,
          ),
          TaskNetWheelColumn(
            controller: hourController,
            itemCount: 24,
            displayBuilder: (index) => index.toString().padLeft(2, '0'),
            onSelectedItemChanged: onHourChanged,
          ),
          TaskNetWheelColumn(
            controller: minuteController,
            itemCount: 60,
            displayBuilder: (index) => index.toString().padLeft(2, '0'),
            onSelectedItemChanged: onMinuteChanged,
          ),
        ],
      ),
    );
  }
}

/// 单列滑轮选择底部弹窗。
class _SingleWheelPickerSheet extends StatelessWidget {
  const _SingleWheelPickerSheet({
    required this.strings,
    required this.title,
    required this.controller,
    required this.itemCount,
    required this.itemLabelBuilder,
    required this.onCancel,
    required this.onConfirm,
    required this.onSelectedItemChanged,
  });

  final AppStrings strings;
  final String title;
  final FixedExtentScrollController controller;
  final int itemCount;
  final String Function(int index) itemLabelBuilder;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final ValueChanged<int> onSelectedItemChanged;

  @override
  Widget build(BuildContext context) {
    return TaskNetWheelSheetFrame(
      title: title,
      cancelText: strings.cancel,
      confirmText: strings.save,
      onCancel: onCancel,
      onConfirm: onConfirm,
      wheelHeight: 200,
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
          builder: (context, index) => Center(
            child: Text(
              itemLabelBuilder(index),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}

/// 退出编辑页时的用户决策枚举。
enum _ExitDecision { cancel, discard, saveDraft, save }
