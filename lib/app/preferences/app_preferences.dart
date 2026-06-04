/*
 * TaskNet 应用偏好状态文件。
 *
 * 这个文件集中保存当前只影响前端外观和文案的轻量偏好：
 * - 是否启用深色模式
 * - 当前应用语言
 * - 当前语言对应的系统文案
 *
 * 当前使用 Riverpod 承载运行期状态，同时把偏好写入本地 JSON 文件，
 * 这样重启应用后仍然能恢复上一次的主题和语言选择。
 */
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 应用支持的语言枚举。
///
/// 当前只提供中文和英文，后续新增语言时继续扩展这个枚举即可。
enum AppLanguage {
  /// 简体中文。
  zh,

  /// 英文。
  en,
}

/// 深色模式开关 Provider。
///
/// 页面和应用壳通过监听它来决定当前使用亮色主题还是深色主题。
final darkModeProvider = StateProvider<bool>((ref) => false);

/// 当前应用语言 Provider。
///
/// 所有系统文案都通过这个状态选择中文或英文。
final appLanguageProvider = StateProvider<AppLanguage>((ref) => AppLanguage.zh);

/// 所有用户默认拥有的初始化标签。
const defaultTaskLabels = <String>[
  '工作任务',
  '学习安排',
  '购物清单',
  '锻炼计划',
  '心愿清单',
  '个人备忘',
];

/// 当前用户拥有的标签集合。
final taskLabelsProvider = StateProvider<List<String>>(
  (ref) => defaultTaskLabels,
);

/// 当前语言文案 Provider。
///
/// UI 组件只需要读取这个 Provider，就能拿到对应语言的文案集合。
final appStringsProvider = Provider<AppStrings>((ref) {
  return AppStrings(ref.watch(appLanguageProvider));
});

/// 应用偏好文件存储 Provider。
///
/// 设置页通过它把用户选择写入本地文件，应用启动时也使用同一个存储读取初始值。
final appPreferencesStorageProvider = Provider<AppPreferencesStorage>((ref) {
  return const AppPreferencesStorage();
});

/// 应用偏好快照。
///
/// 这个不可变对象用于在内存状态和本地文件之间传递完整偏好，避免只保存其中一个字段。
class AppPreferencesSnapshot {
  const AppPreferencesSnapshot({
    this.darkMode = false,
    this.language = AppLanguage.zh,
    this.taskLabels = defaultTaskLabels,
  });

  /// 是否启用深色模式。
  final bool darkMode;

  /// 当前应用语言。
  final AppLanguage language;

  /// 当前用户的标签集合。
  final List<String> taskLabels;

  /// 从 JSON 对象恢复偏好快照。
  factory AppPreferencesSnapshot.fromJson(Map<String, Object?> json) {
    return AppPreferencesSnapshot(
      darkMode: json['darkMode'] == true,
      language: AppLanguage.values.firstWhere(
        (language) => language.name == json['language'],
        orElse: () => AppLanguage.zh,
      ),
      taskLabels: _normalizeTaskLabels(json['taskLabels']),
    );
  }

  /// 把偏好快照转换为可写入文件的 JSON 对象。
  Map<String, Object?> toJson() {
    return {
      'darkMode': darkMode,
      'language': language.name,
      'taskLabels': taskLabels,
    };
  }
}

List<String> _normalizeTaskLabels(Object? raw) {
  final source = switch (raw) {
    List<Object?> value => value,
    _ => defaultTaskLabels,
  };
  final normalized = <String>[];
  for (final item in source) {
    if (item is! String) {
      continue;
    }
    final label = _mapLegacyLabel(item.trim());
    if (label.isEmpty || label.length > 10 || normalized.contains(label)) {
      continue;
    }
    normalized.add(label);
  }
  if (normalized.isEmpty) {
    return defaultTaskLabels;
  }
  return normalized;
}

String _mapLegacyLabel(String label) {
  switch (label) {
    case 'work':
      return '工作任务';
    case 'study':
      return '学习安排';
    case 'life':
      return '个人备忘';
    case 'health':
      return '锻炼计划';
    case 'shopping':
      return '购物清单';
    default:
      return label;
  }
}

/// 应用偏好本地文件存储。
///
/// 使用 `path_provider` 找到应用文档目录，把深色模式和语言保存为一个很小的 JSON 文件。
class AppPreferencesStorage {
  const AppPreferencesStorage();

  /// 偏好文件名。
  static const _fileName = 'tasknet_preferences.json';

  /// 读取本地偏好；文件不存在或解析失败时返回默认偏好。
  Future<AppPreferencesSnapshot> load() async {
    try {
      final file = await _preferencesFile();
      if (!await file.exists()) {
        return const AppPreferencesSnapshot();
      }

      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, Object?>) {
        return const AppPreferencesSnapshot();
      }
      return AppPreferencesSnapshot.fromJson(decoded);
    } catch (_) {
      return const AppPreferencesSnapshot();
    }
  }

  /// 保存当前偏好。
  Future<void> save(AppPreferencesSnapshot snapshot) async {
    final file = await _preferencesFile();
    await file.writeAsString(jsonEncode(snapshot.toJson()), flush: true);
  }

  /// 获取偏好文件路径。
  Future<File> _preferencesFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File(p.join(directory.path, _fileName));
  }
}

/// TaskNet 应用内系统文案集合。
///
/// 这里不保存用户输入的任务内容，只保存按钮、标题、提示、菜单等应用自身文字。
class AppStrings {
  const AppStrings(this.language);

  /// 当前文案对应的语言。
  final AppLanguage language;

  /// 当前语言是否为中文。
  bool get isChinese => language == AppLanguage.zh;

  /// intl 日期格式化使用的 locale。
  String get dateLocale => isChinese ? 'zh_CN' : 'en_US';

  /// 首页名称。
  String get home => isChinese ? '首页' : 'Home';

  /// 收集箱名称。
  String get inbox => isChinese ? '收集箱' : 'Inbox';

  /// 设置页名称。
  String get settings => isChinese ? '设置' : 'Settings';

  /// 专注页名称。
  String get focus => isChinese ? '专注' : 'Focus';

  /// 四象限页名称。
  String get quadrants => isChinese ? '四象限' : 'Quadrants';

  /// 日历页名称。
  String get calendar => isChinese ? '日历' : 'Calendar';

  /// 日历页子标签：待办。
  String get calendarTodo => isChinese ? '待办' : 'Todo';

  /// 日历页子标签：习惯。
  String get calendarHabits => isChinese ? '习惯' : 'Habits';

  /// 日历周标题（周一到周日）。
  List<String> get calendarWeekdayLabels => isChinese
      ? const ['一', '二', '三', '四', '五', '六', '日']
      : const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// 格式化单个月份标题。
  String formatCalendarMonth(DateTime month) {
    if (isChinese) {
      return '${month.month}月';
    }
    return _englishMonthNames[month.month - 1];
  }

  /// 格式化周视图顶部月份标题（支持跨月）。
  String formatCalendarMonthRange(DateTime startMonth, DateTime endMonth) {
    final startText = formatCalendarMonth(startMonth);
    final endText = formatCalendarMonth(endMonth);
    if (startMonth.year == endMonth.year &&
        startMonth.month == endMonth.month) {
      return startText;
    }
    return '$startText-$endText';
  }

  /// 专注页子标签：番茄钟。
  String get pomodoro => isChinese ? '番茄钟' : 'Pomodoro';

  /// 专注页子标签：数据统计。
  String get statistics => isChinese ? '数据统计' : 'Statistics';

  /// 纯专注模式入口文案。
  String get pureFocusMode => isChinese ? '纯专注' : 'Pure focus';

  /// 纯专注页退出按钮文案。
  String get exitPureFocus => isChinese ? '退出专注' : 'Exit focus';

  /// 侧边栏头像占位名。
  String get sidebarUserName => isChinese ? '用户名' : 'User Name';

  /// 新建任务按钮。
  String get newTask => isChinese ? '新建任务' : 'New task';

  /// 新建任务页标题。
  String get createTaskTitle => isChinese ? '新建任务' : 'New task';

  /// 编辑任务页标题。
  String get editTaskTitle => isChinese ? '编辑任务' : 'Edit task';

  /// 保存按钮。
  String get save => isChinese ? '保存' : 'Save';

  /// 取消按钮。
  String get cancel => isChinese ? '取消' : 'Cancel';

  /// 删除按钮。
  String get delete => isChinese ? '删除' : 'Delete';

  /// 首页进行中分区。
  String get activeTasks => isChinese ? '进行中' : 'In progress';

  /// 首页已完成分区。
  String get completedTasks => isChinese ? '已完成' : 'Completed';

  /// 四象限：第一象限标题。
  String get quadrantOneTitle => isChinese ? '第一象限' : 'Quadrant I';

  /// 四象限：第二象限标题。
  String get quadrantTwoTitle => isChinese ? '第二象限' : 'Quadrant II';

  /// 四象限：第三象限标题。
  String get quadrantThreeTitle => isChinese ? '第三象限' : 'Quadrant III';

  /// 四象限：第四象限标题。
  String get quadrantFourTitle => isChinese ? '第四象限' : 'Quadrant IV';

  /// 四象限：重要且紧急。
  String get importantAndUrgent =>
      isChinese ? '重要且紧急的待办' : 'Important and urgent';

  /// 四象限：重要但不紧急。
  String get importantNotUrgent =>
      isChinese ? '重要但不紧急的待办' : 'Important but not urgent';

  /// 四象限：不重要但紧急。
  String get notImportantButUrgent =>
      isChinese ? '不重要但紧急的待办' : 'Not important but urgent';

  /// 四象限：不重要不紧急。
  String get notImportantNotUrgent =>
      isChinese ? '不重要不紧急的待办' : 'Not important and not urgent';

  /// 四象限空分区提示。
  String get quadrantEmpty => isChinese ? '暂无待办' : 'No todo';

  /// 空列表标题。
  String get emptyHomeTitle => isChinese ? '先放进第一件事' : 'Start with one thing';

  /// 空列表说明。
  String get emptyHomeBody => isChinese
      ? '这里会优先服务你每天最常打开的清单体验。现在可以先点右下角，写下今天要推进的第一项任务。'
      : 'Your daily list will live here. Tap the button in the corner to add the first task you want to move forward.';

  /// 日历待办空状态标题。
  String get calendarNoTodoTitle =>
      isChinese ? '这一天没有待办' : 'No todo on this day';

  /// 日历待办空状态说明。
  String get calendarNoTodoBody => isChinese
      ? '选择其他日期，查看截止时间落在那一天的任务。'
      : 'Pick another date to see tasks due on that day.';

  /// 删除任务确认标题。
  String get deleteTaskTitle => isChinese ? '删除任务？' : 'Delete task?';

  /// 根据任务标题生成删除确认说明。
  String deleteTaskMessage(String title) {
    return isChinese ? '确定要永久删除“$title”吗？' : 'Delete "$title" permanently?';
  }

  /// 顶部栏多选状态文案。
  String selectedCountLabel(int count) {
    return isChinese ? '已选择 $count 项' : '$count selected';
  }

  /// 退出多选的按钮辅助说明。
  String get exitSelectionTooltip => isChinese ? '退出多选' : 'Exit multi-select';

  /// 多选批量删除按钮辅助说明。
  String get deleteSelectedTasksTooltip =>
      isChinese ? '删除所选任务' : 'Delete selected tasks';

  /// 多选批量删除确认标题。
  String get deleteSelectedTasksTitle =>
      isChinese ? '删除选中任务？' : 'Delete selected tasks?';

  /// 多选批量删除确认说明。
  String deleteSelectedTasksMessage(int count) {
    return isChinese
        ? '确定要删除已选中的 $count 项任务吗？'
        : 'Delete $count selected task(s)?';
  }

  /// 任务列表加载失败提示。
  String taskLoadFailed(Object error) {
    return isChinese ? '任务列表加载失败：$error' : 'Failed to load tasks: $error';
  }

  /// 任务数量文案。
  String itemCount(int count) {
    if (isChinese) {
      return '$count 项';
    }
    return count == 1 ? '1 item' : '$count items';
  }

  /// 任务标题输入框标签。
  String get titleLabel => isChinese ? '标题' : 'Title';

  /// 任务标题输入框占位提示。
  String get titleHint => isChinese
      ? '例如：整理这周要推进的三件事'
      : 'For example: Plan three things for this week';

  /// 任务编辑页标题。
  ///
  /// 这是一页更偏“查看与补充具体信息”的详情页，因此标题不再强调“编辑”动作本身。
  String get taskDetailsTitle => isChinese ? '具体信息' : 'Details';

  /// 任务描述输入框标签。
  String get descriptionLabel => isChinese ? '描述' : 'Description';

  /// 任务描述输入框占位提示。
  String get descriptionHint => isChinese
      ? '补充一点上下文，会更容易回到这件事里。'
      : 'Add a little context so it is easier to come back to this.';

  /// 截止时间字段标题。
  String get dueDate => isChinese ? '截止时间' : 'Due date';

  /// 标签字段标题。
  String get taskLabel => isChinese ? '标签' : 'Label';

  /// 倒计时模式名称。
  String get countdownMode => isChinese ? '倒计时' : 'Countdown';

  /// 正计时模式名称。
  String get countupMode => isChinese ? '正计时' : 'Count-up';

  /// 开始按钮。
  String get start => isChinese ? '开始' : 'Start';

  /// 暂停按钮。
  String get pause => isChinese ? '暂停' : 'Pause';

  /// 继续按钮。
  String get resume => isChinese ? '继续' : 'Resume';

  /// 重置按钮。
  String get reset => isChinese ? '重置' : 'Reset';

  /// 常用时长标题。
  String get commonDurations => isChinese ? '常用时间' : 'Common durations';

  /// 时长设置标题。
  String get durationPickerTitle => isChinese ? '选择时间' : 'Pick duration';

  /// 新增常用时长按钮。
  String get addDuration => isChinese ? '添加时间' : 'Add duration';

  /// 编辑常用时长按钮。
  String get editDuration => isChinese ? '编辑时间' : 'Edit duration';

  /// 删除常用时长按钮。
  String get deleteDuration => isChinese ? '删除时间' : 'Delete duration';

  /// 时长重复提示。
  String get durationAlreadyExists =>
      isChinese ? '该时长已存在' : 'This duration already exists';

  /// 今日专注时长。
  String get todayFocusTime => isChinese ? '今日专注时长' : 'Today focus time';

  /// 累计专注时长。
  String get totalFocusTime => isChinese ? '累计专注时长' : 'Total focus time';

  /// 完成会话数。
  String get completedSessions => isChinese ? '完成会话数' : 'Completed sessions';

  /// 中断会话数。
  String get interruptedSessions =>
      isChinese ? '中断会话数' : 'Interrupted sessions';

  /// 最长单次专注。
  String get longestSession => isChinese ? '最长单次专注' : 'Longest session';

  /// 倒计时会话数。
  String get countdownSessions => isChinese ? '倒计时会话' : 'Countdown sessions';

  /// 正计时会话数。
  String get countupSessions => isChinese ? '正计时会话' : 'Count-up sessions';

  /// 最近7天趋势。
  String get recent7Days => isChinese ? '最近 7 天趋势' : 'Last 7 days trend';

  /// 专注时间分布。
  String get timeDistribution => isChinese ? '时段分布' : 'Time distribution';

  /// 最活跃时段。
  String get mostActivePeriod => isChinese ? '最活跃时段' : 'Most active period';

  /// 暂无数据文案。
  String get noStatsYet =>
      isChinese ? '暂无统计数据，开始一次专注吧。' : 'No stats yet. Start a focus session.';

  /// 效率概览标题。
  String get focusOverview => isChinese ? '效率概览' : 'Focus overview';

  /// 平均单次专注时长。
  String get averageSession => isChinese ? '平均单次时长' : 'Average session';

  /// 完成率。
  String get completionRate => isChinese ? '完成率' : 'Completion rate';

  /// 近7天活跃天数。
  String get activeDays => isChinese ? '近7天活跃天数' : 'Active days (7d)';

  /// 连续专注天数。
  String get currentStreak => isChinese ? '连续专注天数' : 'Current streak';

  /// 本周会话数。
  String get thisWeekSessions => isChinese ? '本周会话数' : 'Sessions this week';

  /// 近 14 天专注趋势图标题。
  String get focusCurve14Days => isChinese ? '近14天专注曲线' : '14-day focus curve';

  /// 近 12 周专注热力图标题。
  String get focusHeatmap12Weeks =>
      isChinese ? '专注热力图（12周）' : 'Focus heatmap (12 weeks)';

  /// 时段分布：清晨。
  String get periodMorning => isChinese ? '清晨 05-11' : 'Morning 05-11';

  /// 时段分布：午后。
  String get periodAfternoon => isChinese ? '午后 11-17' : 'Afternoon 11-17';

  /// 时段分布：傍晚。
  String get periodEvening => isChinese ? '傍晚 17-22' : 'Evening 17-22';

  /// 时段分布：夜间。
  String get periodNight => isChinese ? '夜间 22-05' : 'Night 22-05';

  /// 专注会话完成提示。
  String get focusCompleted => isChinese ? '本次专注完成' : 'Focus session completed';

  /// 未设置截止时间时的占位文案。
  String get noDueDate => isChinese ? '暂不设置' : 'Not set';

  /// 未设置标签时的占位文案。
  String get noLabel => isChinese ? '无标签' : 'No label';

  /// 任务没有描述时的占位文案。
  String get noDescription => isChinese ? '暂无描述' : 'No description';

  /// 重要开关标题。
  String get important => isChinese ? '重要' : 'Important';

  /// 重要开关说明。
  String get importantSubtitle =>
      isChinese ? '这件事值得优先被看见。' : 'This deserves to stay visible.';

  /// 紧急开关标题。
  String get urgent => isChinese ? '紧急' : 'Urgent';

  /// 紧急开关说明。
  String get urgentSubtitle =>
      isChinese ? '这件事需要你尽快处理。' : 'This needs your attention soon.';

  /// 已过期任务状态。
  String get overdue => isChinese ? '已过期' : 'Overdue';

  /// 删除任务按钮的辅助说明。
  String get deleteTaskTooltip => isChinese ? '删除任务' : 'Delete task';

  /// 拖拽排序按钮的辅助说明。
  String get dragToSortTooltip =>
      isChinese ? '按住拖动排序' : 'Hold and drag to sort';

  /// 保存草稿弹窗标题。
  String get saveDraftTitle => isChinese ? '要保存草稿吗？' : 'Save draft?';

  /// 保存草稿弹窗说明。
  String get saveDraftMessage => isChinese
      ? '现在退出的话，可以先把这次编辑暂时保留下来，稍后再继续。'
      : 'You can keep this edit as a draft and continue later.';

  /// 继续编辑按钮。
  String get keepEditing => isChinese ? '继续编辑' : 'Keep editing';

  /// 不保存按钮。
  String get discardDraft => isChinese ? '不保存' : 'Discard';

  /// 保存草稿按钮。
  String get saveDraft => isChinese ? '保存草稿' : 'Save draft';

  /// 保存更改弹窗标题。
  String get saveChangesTitle => isChinese ? '保存更改？' : 'Save changes?';

  /// 保存更改弹窗说明。
  String get saveChangesMessage =>
      isChinese ? '当前任务有未保存的更改。' : 'This task has unsaved changes.';

  /// 标题为空时的提示。
  String get titleRequired => isChinese ? '标题不能为空' : 'Title is required';

  /// 保存失败时的提示。
  String taskSaveFailed(Object error) {
    return isChinese ? '保存失败：$error' : 'Save failed: $error';
  }

  /// 日期滚轮的年列标签。
  String get year => isChinese ? '年' : 'Year';

  /// 日期滚轮的月列标签。
  String get month => isChinese ? '月' : 'Month';

  /// 日期滚轮的日列标签。
  String get day => isChinese ? '日' : 'Day';

  /// 日期滚轮的小时列标签。
  String get hour => isChinese ? '时' : 'Hour';

  /// 日期滚轮的分钟列标签。
  String get minute => isChinese ? '分' : 'Min';

  /// 设置项：深色模式。
  String get darkMode => isChinese ? '深色模式' : 'Dark mode';

  /// 设置项：语言。
  String get languageLabel => isChinese ? '语言' : 'Language';

  /// 中文语言名称。
  String get chinese => isChinese ? '中文' : 'Chinese';

  /// 中文语言补充说明。
  String get chineseSubtitle => isChinese ? '简体中文' : 'Simplified Chinese';

  /// 英文语言名称。
  String get english => isChinese ? '英文' : 'English';

  /// 英文语言补充说明。
  String get englishSubtitle => 'English';

  /// 语言选择按钮辅助说明。
  String get chooseLanguageTooltip => isChinese ? '选择语言' : 'Choose language';

  /// 侧边栏按钮辅助说明。
  String get openSidebarTooltip => isChinese ? '打开侧边栏' : 'Open sidebar';

  /// 新建标签按钮辅助说明。
  String get addLabelTooltip => isChinese ? '添加标签' : 'Add label';

  /// 删除标签按钮辅助说明。
  String get deleteLabelTooltip => isChinese ? '删除标签' : 'Delete labels';

  /// 新建标签弹窗标题。
  String get createLabelTitle => isChinese ? '新建标签' : 'Create label';

  /// 新建标签输入提示。
  String get createLabelHint =>
      isChinese ? '标签名称（最多10个字）' : 'Label name (max 10 chars)';

  /// 标签名为空提示。
  String get labelRequired => isChinese ? '标签名称不能为空' : 'Label name is required';

  /// 标签名超过长度提示。
  String get labelTooLong =>
      isChinese ? '标签名称不能超过10个字符' : 'Label must be 10 chars or less';

  /// 标签名重复提示。
  String get labelAlreadyExists =>
      isChinese ? '该标签已存在' : 'Label already exists';

  /// 标签删除确认标题。
  String get deleteLabelsTitle => isChinese ? '删除标签？' : 'Delete labels?';

  /// 标签删除确认描述。
  String deleteLabelsMessage(int count) {
    return isChinese
        ? '确定要删除选中的 $count 个标签吗？'
        : 'Delete $count selected label(s)?';
  }

  /// 标签名称展示。
  String taskLabelName(String label) {
    final labelId = _defaultLabelAliasToId[label];
    if (labelId == null) {
      return label;
    }
    switch (labelId) {
      case 'work_tasks':
        return isChinese ? '工作任务' : 'Work Tasks';
      case 'study_plan':
        return isChinese ? '学习安排' : 'Study Plan';
      case 'shopping_list':
        return isChinese ? '购物清单' : 'Shopping List';
      case 'workout_plan':
        return isChinese ? '锻炼计划' : 'Workout Plan';
      case 'wish_list':
        return isChinese ? '心愿清单' : 'Wish List';
      case 'personal_notes':
        return isChinese ? '个人备忘' : 'Personal Notes';
      default:
        return label;
    }
  }

  /// 任务列表和编辑页里的完整日期时间格式。
  ///
  /// 日期部分固定使用 `yyyy-MM-dd`，避免中英文环境下显示方式不一致。
  String get fullDateTimePattern => 'yyyy-MM-dd HH:mm';

  /// 任务编辑页日期摘要中的日期格式。
  ///
  /// 日期部分固定使用 `yyyy-MM-dd`，保持不同语言下的展示一致。
  String get dateSummaryPattern => 'yyyy-MM-dd';

  /// 任务编辑页日期摘要中的时间格式。
  String get timeSummaryPattern => 'HH:mm';
}

const _englishMonthNames = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const _defaultLabelAliasToId = <String, String>{
  '工作任务': 'work_tasks',
  'Work Tasks': 'work_tasks',
  '学习安排': 'study_plan',
  'Study Plan': 'study_plan',
  '购物清单': 'shopping_list',
  'Shopping List': 'shopping_list',
  '锻炼计划': 'workout_plan',
  'Workout Plan': 'workout_plan',
  '心愿清单': 'wish_list',
  'Wish List': 'wish_list',
  '个人备忘': 'personal_notes',
  'Personal Notes': 'personal_notes',
};
