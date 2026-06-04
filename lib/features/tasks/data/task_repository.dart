/*
 * 任务数据访问层。
 *
 * 这个文件负责把 Drift 数据库操作包装成更贴近业务语义的接口，例如：
 * - 监听首页任务列表
 * - 新建任务
 * - 编辑任务
 * - 标记完成
 * - 批量删除
 * - 保存和清空草稿
 * - 维护拖拽排序
 *
 * 同时它也承载第一版需要的 Riverpod Provider 定义，
 * 方便页面层直接订阅本地数据变化。
 */
import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;

import 'local_database.dart';
export 'local_database.dart' show DraftEntry, Task;

/// 任务状态枚举。
///
/// 当前只保留第一版会实际使用到的状态，并映射到数据库中的整数值。
enum TaskStatus {
  active(0),
  completed(1),
  archived(2);

  const TaskStatus(this.value);

  final int value;
}

/// 任务编辑页值对象。
///
/// 这个类把“编辑表单的中间状态”从页面组件中抽离出来，
/// 让新建、编辑、草稿恢复三种场景共享同一套数据结构。
class TaskEditorValue {
  const TaskEditorValue({
    this.title = '',
    this.description = '',
    this.dueAt,
    this.label,
    this.isImportant = false,
    this.isUrgent = false,
  });

  /// 从正式任务实体构造编辑器值对象。
  factory TaskEditorValue.fromTask(Task task) {
    return TaskEditorValue(
      title: task.title,
      description: task.description ?? '',
      dueAt: task.dueAt,
      label: task.label,
      isImportant: task.isImportant,
      isUrgent: task.isUrgent,
    );
  }

  /// 从草稿实体构造编辑器值对象。
  factory TaskEditorValue.fromDraft(DraftEntry draft) {
    return TaskEditorValue(
      title: draft.title ?? '',
      description: draft.description ?? '',
      dueAt: draft.dueAt,
      label: draft.label,
      isImportant: draft.isImportant,
      isUrgent: draft.isUrgent,
    );
  }

  final String title;
  final String description;
  final DateTime? dueAt;
  final String? label;
  final bool isImportant;
  final bool isUrgent;

  /// 复制当前值对象，并按需替换部分字段。
  TaskEditorValue copyWith({
    String? title,
    String? description,
    DateTime? dueAt,
    bool clearDueAt = false,
    String? label,
    bool clearLabel = false,
    bool? isImportant,
    bool? isUrgent,
  }) {
    return TaskEditorValue(
      title: title ?? this.title,
      description: description ?? this.description,
      dueAt: clearDueAt ? null : dueAt ?? this.dueAt,
      label: clearLabel ? null : label ?? this.label,
      isImportant: isImportant ?? this.isImportant,
      isUrgent: isUrgent ?? this.isUrgent,
    );
  }

  /// 判断当前编辑器中是否已经存在值得保存为草稿的内容。
  bool get hasMeaningfulContent {
    return title.trim().isNotEmpty ||
        description.trim().isNotEmpty ||
        dueAt != null ||
        label != null ||
        isImportant ||
        isUrgent;
  }
}

/// 全局数据库实例 Provider。
final localDatabaseProvider = Provider<LocalDatabase>((ref) {
  final database = LocalDatabase();
  ref.onDispose(database.close);
  return database;
});

/// 任务仓储 Provider。
final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return TaskRepository(ref.watch(localDatabaseProvider));
});

/// 首页任务列表流 Provider。
final taskListProvider = StreamProvider<List<Task>>((ref) {
  return ref.watch(taskRepositoryProvider).watchVisibleTasks();
});

/// 草稿监听 Provider。
final taskDraftProvider = StreamProvider<DraftEntry?>((ref) {
  return ref.watch(taskRepositoryProvider).watchDraft();
});

/// 批量选择中的任务 ID 集合。
final selectedTaskIdsProvider = StateProvider<Set<String>>((ref) => <String>{});

/// 首页是否处于多选模式。
///
/// 注意：多选模式和“是否有选中项”不是同一个概念。
/// 当最后一个已选中项被取消时，多选模式仍然可以保持开启。
final taskSelectionModeProvider = StateProvider<bool>((ref) => false);

/// 当前首页按标签筛选状态，`null` 表示收集箱（不过滤）。
final selectedTaskLabelProvider = StateProvider<String?>((ref) => null);

/// 控制“已完成”分组是否折叠。
final completedCollapsedProvider = StateProvider<bool>((ref) => true);

/// 控制“进行中”分组是否折叠。
final activeCollapsedProvider = StateProvider<bool>((ref) => false);

/// 任务仓储实现。
///
/// 这一层把底层表操作翻译成“创建任务”“拖拽排序”“保存草稿”这类业务动作，
/// 便于后续继续接同步、远程接口和工作区逻辑。
class TaskRepository {
  TaskRepository(this._database);

  final LocalDatabase _database;

  /// 监听首页可见任务列表。
  ///
  /// 当前会排除归档任务，并按照拖拽顺序优先、最近更新时间次之的规则排序。
  Stream<List<Task>> watchVisibleTasks() {
    return (_database.select(_database.tasks)
          ..where((table) => table.status.isNotValue(TaskStatus.archived.value))
          ..orderBy([
            (table) => OrderingTerm(expression: table.sortOrder),
            (table) => OrderingTerm.desc(table.updatedAt),
          ]))
        .watch();
  }

  /// 监听当前任务编辑草稿。
  Stream<DraftEntry?> watchDraft() {
    return (_database.select(
      _database.draftEntries,
    )..where((table) => table.key.equals(_draftKey))).watchSingleOrNull();
  }

  /// 一次性读取当前任务编辑草稿。
  Future<DraftEntry?> getDraft() async {
    return (_database.select(
      _database.draftEntries,
    )..where((table) => table.key.equals(_draftKey))).getSingleOrNull();
  }

  /// 创建一条新任务。
  Future<void> createTask(TaskEditorValue value) async {
    final firstActiveTask =
        await (_database.select(_database.tasks)
              ..where((table) => table.status.equals(TaskStatus.active.value))
              ..orderBy([
                (table) => OrderingTerm(expression: table.sortOrder),
                (table) => OrderingTerm.desc(table.updatedAt),
              ])
              ..limit(1))
            .getSingleOrNull();
    final now = DateTime.now();

    await _database
        .into(_database.tasks)
        .insert(
          TasksCompanion.insert(
            id: '${now.microsecondsSinceEpoch}',
            title: value.title.trim(),
            description: Value(_nullableText(value.description)),
            dueAt: Value(value.dueAt),
            label: Value(_nullableText(value.label ?? '')),
            isImportant: Value(value.isImportant),
            isUrgent: Value(value.isUrgent),
            status: Value(TaskStatus.active.value),
            completedAt: const Value(null),
            sortOrder: Value((firstActiveTask?.sortOrder ?? 0) - 1),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  /// 更新一条已有任务。
  ///
  /// 当任务在编辑过程中已被删除时，通过 [StateError] 提前终止，
  /// 并由调用方的 try-catch 统一转换为用户可见的错误提示。
  Future<void> updateTask(String taskId, TaskEditorValue value) async {
    final existing = await (_database.select(
      _database.tasks,
    )..where((table) => table.id.equals(taskId))).getSingleOrNull();

    if (existing == null) {
      throw StateError('Task not found');
    }

    final now = DateTime.now();

    await (_database.update(
      _database.tasks,
    )..where((table) => table.id.equals(taskId))).write(
      TasksCompanion(
        title: Value(value.title.trim()),
        description: Value(_nullableText(value.description)),
        dueAt: Value(value.dueAt),
        label: Value(_nullableText(value.label ?? '')),
        isImportant: Value(value.isImportant),
        isUrgent: Value(value.isUrgent),
        completedAt: Value(existing.completedAt),
        updatedAt: Value(now),
      ),
    );
  }

  /// 切换任务完成状态。
  ///
  /// 如果任务被标记完成，会写入完成时间；取消完成时则清空完成时间。
  Future<void> toggleCompleted(Task task) async {
    final nextCompleted = task.status != TaskStatus.completed.value;
    final now = DateTime.now();

    await (_database.update(
      _database.tasks,
    )..where((table) => table.id.equals(task.id))).write(
      TasksCompanion(
        status: Value(
          nextCompleted ? TaskStatus.completed.value : TaskStatus.active.value,
        ),
        completedAt: Value(nextCompleted ? now : null),
        updatedAt: nextCompleted ? Value(now) : const Value.absent(),
      ),
    );
  }

  /// 将任务显式标记为已完成。
  ///
  /// 拖拽到“已完成”分组下方时使用这个动作，避免 toggle 在异步边界上误把状态翻回去。
  Future<void> completeTask(Task task) async {
    if (task.status == TaskStatus.completed.value) {
      return;
    }

    final now = DateTime.now();

    await (_database.update(
      _database.tasks,
    )..where((table) => table.id.equals(task.id))).write(
      TasksCompanion(
        status: Value(TaskStatus.completed.value),
        completedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  /// 删除单个任务。
  Future<void> deleteTask(String taskId) async {
    await (_database.delete(
      _database.tasks,
    )..where((table) => table.id.equals(taskId))).go();
  }

  /// 批量删除任务。
  Future<void> deleteTasks(Iterable<String> taskIds) async {
    final ids = taskIds.toList(growable: false);
    if (ids.isEmpty) {
      return;
    }

    await (_database.delete(
      _database.tasks,
    )..where((table) => table.id.isIn(ids))).go();
  }

  /// 清理任务标签（通常用于删除标签后解除任务关联）。
  Future<void> clearLabels(Iterable<String> labels) async {
    final normalized = labels
        .map((label) => label.trim())
        .where((label) => label.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalized.isEmpty) {
      return;
    }

    await (_database.update(
      _database.tasks,
    )..where((table) => table.label.isIn(normalized))).write(
      TasksCompanion(
        label: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// 处理首页拖拽排序。
  ///
  /// 拖拽后的顺序会被写回 `sortOrder` 字段，这样应用重启后顺序仍然能够保持。
  /// 仅被拖拽任务的 `updatedAt` 会刷新，其余任务只更新排序值。
  Future<void> reorderTasks(
    List<Task> activeTasks,
    int oldIndex,
    int newIndex,
  ) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final reordered = [...activeTasks];
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);

    await _database.batch((batch) {
      for (var index = 0; index < reordered.length; index++) {
        final task = reordered[index];
        final isMoved = task.id == item.id;
        batch.update(
          _database.tasks,
          TasksCompanion(
            sortOrder: Value(index),
            updatedAt: isMoved ? Value(DateTime.now()) : const Value.absent(),
          ),
          where: (table) => table.id.equals(task.id),
        );
      }
    });
  }

  /// 保存当前编辑器内容为草稿。
  Future<void> saveDraft(TaskEditorValue value) async {
    final now = DateTime.now();
    await _database
        .into(_database.draftEntries)
        .insertOnConflictUpdate(
          DraftEntriesCompanion.insert(
            key: _draftKey,
            title: Value(_nullableText(value.title)),
            description: Value(_nullableText(value.description)),
            dueAt: Value(value.dueAt),
            label: Value(_nullableText(value.label ?? '')),
            isImportant: Value(value.isImportant),
            isUrgent: Value(value.isUrgent),
            updatedAt: now,
          ),
        );
  }

  /// 清空当前任务编辑草稿。
  Future<void> clearDraft() async {
    await (_database.delete(
      _database.draftEntries,
    )..where((table) => table.key.equals(_draftKey))).go();
  }

  /// 第一版任务编辑器固定使用的草稿槽位。
  static const _draftKey = 'task_editor';

  /// 把空白文本统一标准化为 `null`，减少数据库中的无意义空字符串。
  String? _nullableText(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }
}
