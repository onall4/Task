# TaskNet 代码库文档

## 目录结构

```
lib/
├── main.dart
├── app/
│   ├── app.dart
│   ├── preferences/
│   │   └── app_preferences.dart
│   ├── theme/
│   │   └── app_theme.dart
│   └── widgets/
│       ├── app_notice.dart
│       └── wheel_picker.dart
└── features/
    ├── calendar/
    │   ├── data/
    │   │   ├── calendar_controller.dart
    │   │   └── habit_controller.dart
    │   └── presentation/
    │       └── calendar_page.dart
    ├── focus/
    │   ├── data/
    │   │   ├── focus_controller.dart
    │   │   └── focus_storage.dart
    │   └── presentation/
    │       └── focus_page.dart
    ├── navigation/
    │   └── presentation/
    │       └── tasknet_shell.dart
    ├── settings/
    │   └── presentation/
    │       └── settings_page.dart
    └── tasks/
        ├── data/
        │   ├── local_database.dart
        │   ├── local_database.g.dart
        │   ├── task_repository.dart
        │   └── task_schedule_controller.dart
        └── presentation/
            ├── home_page.dart
            ├── quadrant_page.dart
            ├── task_editor_page.dart
            └── widgets/
                ├── task_card.dart
                └── task_details_sheet.dart
```

---

## 文件详解

### 1. `lib/main.dart` — 应用入口

程序的启动点。负责初始化 Flutter 绑定、加载应用偏好设置，然后启动 `TaskNetApp`。不包含业务逻辑，仅做启动前的准备工作。

---

### 2. `lib/app/app.dart` — MaterialApp 壳

定义 `TaskNetApp` 这个 `ConsumerWidget`，返回 `MaterialApp` 实例。配置全局主题（亮色/暗色）、本地化委托、路由。是 Flutter widget 树的根节点，所有页面都在其下渲染。

---

### 3. `lib/app/preferences/app_preferences.dart` — 应用偏好与本地化字符串

**职责：** 管理应用的轻量偏好（暗色模式、语言选择）和全部 UI 文案。

**具体包含：**
- `AppStrings` 类：中英文双语字符串，覆盖整个应用的所有 UI 文案（导航标签、按钮文字、占位提示、空状态引导等）。通过 `isChinese` 标志自动切换语言。
- `AppPreferences` 类：持久化用户偏好（主题、语言）到本地 JSON 文件。
- 默认标签列表（`defaultTaskLabels`）："工作任务"、"学习安排"、"购物清单"等。
- 标签的本地化映射（中英文名称互换）。
- 相关 Riverpod Provider。

**在应用中的表现：** 用户切换语言或暗色模式时，整个应用的文案和颜色实时更新。侧边栏的标签名称也依赖此文件的映射。

---

### 4. `lib/app/theme/app_theme.dart` — 主题定义

**职责：** 定义应用的亮色和暗色 Material 3 主题。

**具体包含：**
- `lightTheme` 和 `darkTheme` 两个 `ThemeData` 实例。
- 配色方案（`ColorScheme`）、文字样式（`TextTheme`）、组件样式（卡片、按钮、输入框等）的统一配置。

**在应用中的表现：** 所有页面的颜色、圆角、阴影、字体大小等视觉风格均由此文件控制。切换暗色模式时，主题随之切换。

---

### 5. `lib/app/widgets/app_notice.dart` — 统一轻提示组件

**职责：** 提供应用内统一风格的 SnackBar / 轻提示。

**具体包含：**
- `AppNotice` 类：封装 `ScaffoldMessenger.showSnackBar`，统一提示的样式、持续时间和动画。

**在应用中的表现：** 各处显示的临时消息（如"任务已保存"、"操作失败"等）均通过此组件展示，保证视觉一致性。

---

### 6. `lib/app/widgets/wheel_picker.dart` — 滚轮选择器组件

**职责：** 提供通用的滚轮式选择器 UI 组件。

**具体包含：**
- `TaskNetWheelSheetFrame`：底部弹出面板的外框，包含标题栏（取消/标题/确认）。
- `TaskNetWheelColumn`：单个滚轮列，使用 `ListWheelScrollView` 实现。

**在应用中的表现：** 任务编辑器中设置截止时间、优先级时弹出的滚轮选择器均使用此组件。所有滚轮弹窗共享相同的布局和交互模式。

---

### 7. `lib/features/calendar/data/calendar_controller.dart` — 日历状态控制器

**职责：** 管理日历页的核心交互状态。

**具体包含：**
- `CalendarState`：包含选中日期、今天日期、可见周起始日、展开/收起状态、用户是否手动导航等字段。
- `CalendarController`：提供 `selectDate`、`setVisibleWeekStart`、`toggleExpanded`、`jumpToToday` 等方法。每天午夜自动推进 `todayDate`，并根据用户是否手动导航决定是否自动跟随日期。
- `CalendarVisibleMonthRange`：当前可见周覆盖的月份范围。
- 相关 Provider：`calendarControllerProvider`、`calendarVisibleMonthRangeProvider`。

**在应用中的表现：** 用户在日历页滑动切换周、点击日期、展开/收起月网格时，所有状态变化由此控制器驱动。

---

### 8. `lib/features/calendar/data/habit_controller.dart` — 习惯追踪数据层

**职责：** 管理习惯条目的 CRUD 和打卡状态。

**具体包含：**
- `HabitEntry`：习惯条目数据模型，包含 ID、标题、描述、创建时间、已打卡日期集合。
- `HabitController`：提供 `createHabit`、`toggleCheck`、`deleteHabit` 方法。状态变更自动持久化。
- `HabitStorage`：本地 JSON 文件的读写操作。
- `habitDateKey`：生成标准化的日期键（yyyy-MM-dd 格式）。
- 相关 Provider：`habitControllerProvider`。

**在应用中的表现：** 日历页的"习惯"子页面中，用户添加习惯、点击打卡、删除习惯的操作均由此控制器处理。数据保存在 `tasknet_habits.json` 中。

---

### 9. `lib/features/calendar/presentation/calendar_page.dart` — 日历页面

**职责：** 实现日历页的完整 UI。

**具体包含：**
- `CalendarPage`：日历主页，包含可展开/收起的月网格视图、周分页滑动导航。
- `_CalendarTodoTab`：待办子页面，展示选定日期的任务列表及周/月任务计数。
- `_CalendarHabitTab`：习惯子页面，展示习惯列表和每日打卡状态。
- `_MonthGrid`：月网格组件，渲染一个月的日期格子。
- `_HabitCard`：习惯卡片组件。
- `_HabitEditorDialog`：习惯编辑对话框。
- `_WeekdayHeaderRow`：周标题行（一、二、三……）。
- 顶部信息栏在 `tasknet_shell.dart` 中渲染，包含待办/习惯切换按钮。

**在应用中的表现：** 底部导航栏的第二个标签页。用户在此查看日历、选择日期、管理待办任务和习惯打卡。

---

### 10. `lib/features/focus/data/focus_controller.dart` — 专注（番茄钟）控制器

**职责：** 管理专注计时器的状态和逻辑。

**具体包含：**
- `FocusPhase`：专注阶段枚举（工作、短休、长休）。
- `FocusState`：当前阶段、剩余秒数、会话计数、是否运行中。
- `FocusController`：计时器管理（启动、暂停、恢复、跳过、重置），自动在阶段之间切换，记录完成的工作会话。
- `FocusSessionRecord`：专注会话记录（开始时间、时长、阶段）。
- 相关 Provider：`focusControllerProvider`。

**在应用中的表现：** 专注页的番茄钟功能。用户点击开始后倒计时运行，工作结束时自动切换到休息，完成指定次数的工作会话后触发长休息。

---

### 11. `lib/features/focus/data/focus_storage.dart` — 专注数据持久化

**职责：** 专注会话记录和统计数据的本地存储。

**具体包含：**
- `FocusStorage`：读写 `tasknet_focus_sessions.json`，保存和加载历史专注会话列表。
- 支持按日期范围查询统计（总分钟数、完成会话数）。

**在应用中的表现：** 专注页的"统计"子页面展示的历史数据（今日/本周的专注时长和次数）来源于此存储。

---

### 12. `lib/features/focus/presentation/focus_page.dart` — 专注页面

**职责：** 实现专注（番茄钟）页面的完整 UI。

**具体包含：**
- `FocusPage`：专注主页，包含计时器圆环、阶段标签、控制按钮（开始/暂停/跳过）。
- `_FocusStatsTab`：统计子页面，展示今日和本周的专注时长、完成会话数。
- 环形进度条动画、阶段切换动画。

**在应用中的表现：** 底部导航栏的第三个标签页。用户在此使用番茄钟进行专注工作，查看历史统计数据。

---

### 13. `lib/features/navigation/presentation/tasknet_shell.dart` — 主导航壳

**职责：** 应用的主导航框架。

**具体包含：**
- `TaskNetShell`：底部导航栏 + 顶部信息栏 + 页面切换的整体布局。
- `_PageInfoBar`：顶部的信息栏，根据当前页面显示不同的标题和控件：
  - 首页：显示当前标签名或"收集箱"，以及标签筛选按钮、多选操作栏。
  - 日历页：显示月份标签和待办/习惯切换按钮。
  - 专注页：显示专注/统计切换按钮。
- `_TaskSidebar`：左侧抽屉菜单，显示标签列表（收集箱 + 所有自定义标签），支持标签管理（创建、删除）和标签筛选模式。
- `_HomeFloatingActionButton`：首页右下角的悬浮按钮，点击进入新建任务页。

**在应用中的表现：** 这是应用的"骨架"——底部导航切换页面、顶部信息栏的标题和按钮、左侧抽屉的标签列表均在此渲染。

---

### 14. `lib/features/settings/presentation/settings_page.dart` — 设置页面

**职责：** 实现应用设置页面的 UI。

**具体包含：**
- 暗色模式开关。
- 语言切换（中文/英文）。
- 数据管理（清除数据等）。
- 关于信息。

**在应用中的表现：** 从侧边栏或导航栏进入的设置页。用户在此切换主题、语言或管理数据。

---

### 15. `lib/features/tasks/data/local_database.dart` — 本地数据库定义

**职责：** 使用 Drift（SQLite）定义任务和草稿的数据表结构。

**具体包含：**
- `Tasks` 表：任务的数据库表定义，包含 `id`、`title`、`description`、`dueAt`、`label`、`priority`、`isImportant`、`isUrgent`、`status`、`completedAt`、`sortOrder`、`createdAt`、`updatedAt` 等列。
- `Drafts` 表：编辑器草稿表，结构与 Tasks 相似，用于保存未提交的编辑内容。
- `LocalDatabase`：Drift 数据库类，管理表的创建和迁移。

**在应用中的表现：** 所有任务数据的底层存储。不直接被 UI 层使用，由 `TaskRepository` 封装后提供。

---

### 16. `lib/features/tasks/data/local_database.g.dart` — 数据库生成代码

**职责：** Drift 代码生成器自动生成的数据库辅助代码。

**具体包含：**
- `Tasks` 和 `Drafts` 表的 Drift DAO（数据访问对象）。
- 类型安全的查询方法。
- 表结构的 Drift 内部表示。

**在应用中的表现：** 不可手动编辑。由 `build_runner` 从 `local_database.dart` 自动生成。

---

### 17. `lib/features/tasks/data/task_repository.dart` — 任务数据访问层

**职责：** 把底层数据库操作包装成贴近业务语义的接口。

**具体包含：**
- `Task`：任务实体类（由 Drift 生成，重新导出）。
- `TaskEditorValue`：编辑器值对象，把编辑表单的中间状态从页面组件中抽离出来，让新建、编辑、草稿恢复三种场景共享同一套数据结构。
- `TaskStatus` 枚举：`active`（进行中）、`completed`（已完成）、`archived`（已归档）。
- `TaskRepository`：任务仓储实现，提供 `watchVisibleTasks`（监听任务流）、`createTask`、`updateTask`、`toggleCompleted`、`deleteTask`、`deleteTasks`、`reorderTasks`、`saveDraft`、`clearDraft`、`clearLabels` 等方法。
- 全部 Riverpod Provider：`localDatabaseProvider`、`taskRepositoryProvider`、`taskListProvider`、`taskSelectionModeProvider`、`selectedTaskIdsProvider`、`taskSearchQueryProvider`、`taskPriorityFilterProvider`、`taskStatusFilterProvider`、`activeCollapsedProvider`、`completedCollapsedProvider`、`selectedTaskLabelProvider`。
- `buildTaskEditorRoute`：任务编辑页的路由构建函数。

**在应用中的表现：** 首页的任务列表流、新建/编辑/删除/完成/拖拽排序任务、草稿保存与恢复、标签筛选——所有任务相关的数据操作都经过此文件。它是数据层和 UI 层之间的核心枢纽。

---

### 18. `lib/features/tasks/data/task_schedule_controller.dart` — 任务调度数据层

**职责：** 管理任务的截止时间和在日历中的出现规则。

**具体包含：**
- `TaskScheduleMetadata`：调度元数据值对象，保存任务的截止时间（`endAt`）。
- `TaskScheduleController`：以任务 ID 为键的调度状态管理器，提供 `saveSchedule`、`removeSchedules` 方法。
- `TaskScheduleStorage`：调度数据的本地 JSON 文件持久化（`tasknet_task_schedules.json`）。
- `effectiveTaskSchedule`：获取任务的有效调度元数据。
- `taskDateOnly`、`isSameTaskDate`：日期工具函数。
- `taskOccursOnDate`：判断任务是否在指定日期出现（任务仅在截止日期当天出现）。
- 相关 Provider：`taskScheduleControllerProvider`。

**在应用中的表现：** 日历页判定每个日期下有哪些任务时使用 `taskOccursOnDate`。调度信息与任务实体分离存储。

---

### 19. `lib/features/tasks/presentation/home_page.dart` — 首页任务列表

**职责：** 实现首页的主要任务体验。

**具体包含：**
- `HomePage`：首页主组件，包含搜索/筛选栏、"进行中"和"已完成"两个分区，支持拖拽排序、长按进入多选、空状态占位 UI。
- `_HomePageState`：管理拖拽临时顺序、完成状态过渡动画、分区折叠/展开动画。
- `_HomeSearchAndFilterBar`：搜索框 + 筛选按钮（优先级、状态过滤）。
- `_HomeFilterMenuButton`：筛选菜单按钮。
- `_HomeEmptyState`：空列表占位 UI（收集箱或标签下无任务时显示）。
- `_MovingTaskOverlay`：拖拽完成/取消完成时的飞行动画覆盖层。
- `_SectionLabel`：分区标题组件。

**在应用中的表现：** 底部导航栏的第一个标签页。用户在此浏览所有任务、搜索、按标签/优先级/状态筛选、拖拽排序、点击完成。

---

### 20. `lib/features/tasks/presentation/quadrant_page.dart` — 四象限页面

**职责：** 按艾森豪威尔矩阵（重要 × 紧急）将任务划分为四个象限展示。

**具体包含：**
- 四个象限的网格布局。
- 每个象限显示对应分类下的任务列表。
- 空状态占位。

**在应用中的表现：** 帮助用户按优先级矩阵审视任务分布。目前可能是隐藏或辅助页面。

---

### 21. `lib/features/tasks/presentation/task_editor_page.dart` — 任务编辑页面

**职责：** 实现任务的创建和编辑表单。

**具体包含：**
- `TaskEditorPage`：编辑页主组件，包含标题输入、描述输入、截止时间选择器（滚轮式日期+时间）、优先级选择器、标签选择器、重要/紧急开关。
- 草稿自动保存与恢复（切换到后台时保存，重新打开时提示恢复）。
- 新建/编辑/草稿恢复三种场景的统一处理。
- `_EditorPickerTile`：统一的编辑项行组件。
- `_DeadlinePickerSheet`：截止时间的滚轮选择面板。
- `_SingleWheelPickerSheet`：单列滚轮选择面板（用于优先级等）。

**在应用中的表现：** 点击首页悬浮按钮或编辑任务卡片时打开的页面。用户在此设置标题、描述、截止时间、优先级和标签。

---

### 22. `lib/features/tasks/presentation/widgets/task_card.dart` — 任务卡片组件

**职责：** 首页、日历页和已完成区域共用的任务条目卡片。

**具体包含：**
- `TaskCard`：固定高度 64px 的任务卡片，包含勾选框（完成切换）、标题行和编辑按钮。
- `_TaskCardSelectionBox`：左侧勾选框。在多选模式下为圆形，普通模式下为圆角方形。已过期的未完成任务显示琥珀色时钟图标作为警告。
- `_TaskCardTitleRow`：标题文本。已完成的任务文字变灰并显示删除线。
- `_AnimatedStrikeText`：从左到右绘制删除线的动画组件。
- `_StrikeLinePainter`：删除线绘制的 `CustomPainter`。
- `_TaskCardEditButton`：右侧编辑按钮（圆形背景 + 铅笔图标）。

**在应用中的表现：** 任务列表中的每一条任务。外观根据完成状态、选中状态、过期状态动态变化。

---

### 23. `lib/features/tasks/presentation/widgets/task_details_sheet.dart` — 任务详情弹出面板

**职责：** 点击任务卡片后从底部弹出的详情面板。

**具体包含：**
- `showTaskDetailsSheet`：弹出详情面板的入口函数。
- `_TaskDetailsSheet`：面板主体，显示任务标题、描述、截止时间、标签、创建时间等完整信息。
- 提供编辑和完成切换的快捷操作按钮。

**在应用中的表现：** 点击任务卡片（而非编辑按钮）时弹出的半屏面板，用于快速查看任务详情。
