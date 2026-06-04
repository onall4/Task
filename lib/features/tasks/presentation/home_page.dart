/*
 * 首页任务列表页面。
 *
 * 这个文件负责实现第一版首页的主要任务体验，包括：
 * - 进行中任务列表
 * - 已完成任务折叠区
 * - 拖拽排序
 * - 长按进入多选
 * - 空状态展示
 *
 * 当前版本重点对首页卡片列表做了两项调整：
 * 1. 让单条任务卡片保持更稳定的固定占位，不再显得过高。
 * 2. 进一步收紧分区、卡片和留白的节奏，让首页更接近参考项目的密度。
 */
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/preferences/app_preferences.dart';
import '../data/task_repository.dart';
import 'task_editor_page.dart';
import 'widgets/task_card.dart';
import 'widgets/task_details_sheet.dart';

/// 首页任务列表页。
///
/// 负责把任务流数据转换成可交互的首页列表界面。
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  /// 创建首页状态对象。
  ConsumerState<HomePage> createState() => _HomePageState();
}

/// 首页任务列表状态。
///
/// 这里额外保存拖拽后的临时顺序，避免等待数据库 stream 回推时出现短暂闪回旧顺序的问题。
class _HomePageState extends ConsumerState<HomePage> {
  /// 正在等待数据库落库确认的进行中任务 ID 顺序。
  List<String>? _optimisticActiveOrder;

  /// 列表区域和折叠区使用统一的过渡时长，避免首页多个动画节奏不一致。
  static const _completedSectionAnimationDuration = Duration(milliseconds: 720);
  static const _completionStrikeDuration = Duration(milliseconds: 320);
  static const _sectionMoveDuration = Duration(milliseconds: 420);
  static const _longPressDragSlop = 12.0;
  static const _listItemGap = 6.0;
  static const _listItemExtent = TaskCard.height + _listItemGap;
  final _listViewportKey = GlobalKey();
  final _completedDividerKey = GlobalKey();
  final _taskSlotKeys = <String, GlobalKey>{};
  final _transitioningTaskIds = <String>{};
  final _strikingTaskIds = <String>{};
  final _unstrikingTaskIds = <String>{};
  final _completionPreviewByTaskId = <String, bool>{};
  final _settledCompletionAnimationTaskIds = <String>{};
  final _dragCompletingTaskIds = <String>{};
  final _dragCompletedAtByTaskId = <String, DateTime>{};
  final _sectionMoves = <String, _TaskSectionMove>{};
  bool? _activeSectionAnimatingToCollapsed;
  String? _pressedTaskId;
  Offset? _pressStartPosition;
  String? _reorderTaskId;
  var _longPressMoved = false;
  var _reorderInProgress = false;

  @override
  /// 构建首页列表。
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(taskListProvider);
    final activeCollapsed = ref.watch(activeCollapsedProvider);
    final completedCollapsed = ref.watch(completedCollapsedProvider);
    final isSelectionMode = ref.watch(taskSelectionModeProvider);
    final selectedIds = ref.watch(selectedTaskIdsProvider);
    final selectedLabel = ref.watch(selectedTaskLabelProvider);
    final strings = ref.watch(appStringsProvider);

    return tasksAsync.when(
      data: (tasks) {
        final scopedTasks = selectedLabel == null
            ? tasks
            : tasks.where((task) => task.label == selectedLabel).toList();
        final scopedMoves = _sectionMoves.values
            .where(
              (move) =>
                  selectedLabel == null || move.task.label == selectedLabel,
            )
            .toList(growable: false);
        final activeTasks = _buildActiveTasks(scopedTasks, scopedMoves);
        final orderedActiveTasks = _applyOptimisticOrder(activeTasks);
        final visibleActiveTasks =
            activeCollapsed && _activeSectionAnimatingToCollapsed != true
            ? <Task>[]
            : orderedActiveTasks;
        final pendingCompletedTasks = scopedTasks
            .where(
              (task) =>
                  task.status == TaskStatus.active.value &&
                  _dragCompletingTaskIds.contains(task.id),
            )
            .map(_buildOptimisticCompletedTask)
            .toList();
        final completedTasks = _buildCompletedTasks(
          scopedTasks,
          scopedMoves,
          pendingCompletedTasks,
        );
        final itemCount = visibleActiveTasks.length + 1;

        return KeyedSubtree(
          key: _listViewportKey,
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
            itemCount: itemCount,
            buildDefaultDragHandles: false,
            proxyDecorator: (child, index, animation) => child,
            onReorderStart: (index) {
              if (index < 0 || index >= visibleActiveTasks.length) {
                return;
              }
              _reorderInProgress = true;
              _reorderTaskId = visibleActiveTasks[index].id;
            },
            onReorderEnd: (_) {
              final selectionTaskId = _reorderTaskId;
              final shouldEnterSelection =
                  selectionTaskId != null &&
                  !_longPressMoved &&
                  !ref.read(taskSelectionModeProvider);
              _reorderInProgress = false;
              _clearLongPressTracking();
              if (shouldEnterSelection) {
                _enterSelectionModeAndToggle(ref, selectionTaskId);
              }
            },
            onReorder: (oldIndex, newIndex) async {
              if (oldIndex < 0 || oldIndex >= visibleActiveTasks.length) {
                return;
              }
              final adjustedNewIndex = oldIndex < newIndex
                  ? newIndex - 1
                  : newIndex;
              final droppedIntoCompleted =
                  adjustedNewIndex >= visibleActiveTasks.length;
              if (oldIndex != adjustedNewIndex) {
                _longPressMoved = true;
              }
              if (droppedIntoCompleted) {
                final task = visibleActiveTasks[oldIndex];
                final remainingTasks = [...visibleActiveTasks]
                  ..removeAt(oldIndex);
                final completedAt = DateTime.now();
                setState(() {
                  _dragCompletingTaskIds.add(task.id);
                  _dragCompletedAtByTaskId[task.id] = completedAt;
                  _optimisticActiveOrder = remainingTasks
                      .map((task) => task.id)
                      .toList(growable: false);
                });
                ref.read(completedCollapsedProvider.notifier).state = false;

                try {
                  await ref.read(taskRepositoryProvider).completeTask(task);
                  await _waitForTaskStatus(ref, task.id, targetCompleted: true);
                } catch (_) {
                  if (!mounted) {
                    return;
                  }
                } finally {
                  if (mounted) {
                    setState(() {
                      _dragCompletingTaskIds.remove(task.id);
                      _dragCompletedAtByTaskId.remove(task.id);
                      _optimisticActiveOrder = null;
                    });
                  }
                }
                return;
              }
              final reorderedTasks = _reorderVisibleTasks(
                visibleActiveTasks,
                oldIndex,
                newIndex,
              );
              setState(() {
                _optimisticActiveOrder = reorderedTasks
                    .map((task) => task.id)
                    .toList(growable: false);
              });

              try {
                await ref
                    .read(taskRepositoryProvider)
                    .reorderTasks(visibleActiveTasks, oldIndex, newIndex);
              } catch (_) {
                if (!mounted) {
                  return;
                }
                setState(() {
                  _optimisticActiveOrder = null;
                });
              }
            },
            header: _buildActiveDivider(
              ref,
              activeTasks,
              activeCollapsed,
              strings,
            ),
            footer: _buildCompletedTasksFooter(
              ref,
              completedTasks,
              scopedMoves,
              completedCollapsed,
              isSelectionMode,
              selectedIds,
              strings,
            ),
            itemBuilder: (context, index) {
              if (index == visibleActiveTasks.length) {
                return _buildCompletedDivider(
                  ref,
                  completedTasks,
                  completedCollapsed,
                  strings,
                );
              }
              final task = visibleActiveTasks[index];
              final isSelected = selectedIds.contains(task.id);
              final completionPreview = _completionPreviewByTaskId[task.id];
              final completionSettled = _settledCompletionAnimationTaskIds
                  .contains(task.id);
              final strikeTarget = completionPreview == true ? 1.0 : 0.0;
              final animateStrike =
                  _strikingTaskIds.contains(task.id) && !completionSettled;
              return KeyedSubtree(
                key: ValueKey(task.id),
                child: _buildMeasuredTaskSlot(
                  slotName: 'active',
                  taskId: task.id,
                  moveSlot: _activeMoveSlotFor(task.id),
                  visibleDuringAnimation:
                      _activeSectionAnimatingToCollapsed != null &&
                      !_sectionMoves.containsKey(task.id),
                  child: Listener(
                    onPointerDown: isSelectionMode
                        ? null
                        : (event) {
                            _pressedTaskId = task.id;
                            _pressStartPosition = event.position;
                            _longPressMoved = false;
                          },
                    onPointerMove: isSelectionMode
                        ? null
                        : (event) {
                            if (_pressedTaskId != task.id) {
                              return;
                            }
                            final startPosition = _pressStartPosition;
                            if (startPosition == null) {
                              return;
                            }
                            if ((event.position - startPosition).distance >
                                _longPressDragSlop) {
                              _longPressMoved = true;
                            }
                          },
                    onPointerUp: (_) {
                      if (!_reorderInProgress) {
                        _clearLongPressTracking();
                      }
                    },
                    onPointerCancel: (_) {
                      if (!_reorderInProgress) {
                        _clearLongPressTracking();
                      }
                    },
                    child: ReorderableDelayedDragStartListener(
                      enabled: !isSelectionMode,
                      index: index,
                      child: TweenAnimationBuilder<double>(
                        duration: animateStrike
                            ? _completionStrikeDuration
                            : Duration.zero,
                        curve: Curves.easeOutCubic,
                        tween: Tween<double>(
                          begin: animateStrike ? 0 : strikeTarget,
                          end: strikeTarget,
                        ),
                        builder: (context, strikeProgress, child) {
                          return TaskCard(
                            task: task,
                            strings: strings,
                            isSelectionMode: isSelectionMode,
                            isSelected: isSelected,
                            completionStrikeProgress: completionPreview == null
                                ? null
                                : strikeProgress,
                            completionPreviewCompleted: completionPreview,
                            onSelectToggle: () =>
                                _toggleSelection(ref, task.id),
                            onEditTap: () {
                              if (isSelectionMode) {
                                _toggleSelection(ref, task.id);
                                return;
                              }
                              _openTaskEditor(context, task);
                            },
                            onTap: () {
                              if (isSelectionMode) {
                                _toggleSelection(ref, task.id);
                                return;
                              }
                              _openTaskDetails(context, task, strings);
                            },
                            onCompleteToggle: () =>
                                _toggleCompletedWithTransition(ref, task),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(strings.taskLoadFailed(error)),
        ),
      ),
    );
  }

  /// 切换单个任务的多选状态。
  void _toggleSelection(WidgetRef ref, String taskId) {
    final current = ref.read(selectedTaskIdsProvider);
    final updated = <String>{...current};
    if (!updated.add(taskId)) {
      updated.remove(taskId);
    }
    ref.read(selectedTaskIdsProvider.notifier).state = updated;
  }

  /// 进入多选模式并切换当前任务选中状态。
  void _enterSelectionModeAndToggle(WidgetRef ref, String taskId) {
    ref.read(taskSelectionModeProvider.notifier).state = true;
    _toggleSelection(ref, taskId);
  }

  void _clearLongPressTracking() {
    _pressedTaskId = null;
    _pressStartPosition = null;
    _reorderTaskId = null;
    _longPressMoved = false;
  }

  void _toggleActiveCollapsed(WidgetRef ref, bool collapsed) {
    if (_activeSectionAnimatingToCollapsed != null) {
      return;
    }

    final targetCollapsed = !collapsed;
    setState(() {
      _activeSectionAnimatingToCollapsed = targetCollapsed;
    });
    ref.read(activeCollapsedProvider.notifier).state = targetCollapsed;

    Future<void>.delayed(_completedSectionAnimationDuration, () {
      if (!mounted || _activeSectionAnimatingToCollapsed != targetCollapsed) {
        return;
      }
      setState(() {
        _activeSectionAnimatingToCollapsed = null;
      });
    });
  }

  Future<void> _toggleCompletedWithTransition(WidgetRef ref, Task task) async {
    if (_transitioningTaskIds.contains(task.id)) {
      return;
    }

    final completing = task.status != TaskStatus.completed.value;
    setState(() {
      _transitioningTaskIds.add(task.id);
      _completionPreviewByTaskId[task.id] = completing;
      if (completing) {
        _strikingTaskIds.add(task.id);
      } else {
        _unstrikingTaskIds.add(task.id);
      }
    });

    try {
      await Future<void>.delayed(_completionStrikeDuration);
      if (!mounted) {
        return;
      }
      setState(() {
        _settledCompletionAnimationTaskIds.add(task.id);
      });
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) {
        return;
      }

      await _moveTaskBetweenSections(
        ref,
        task,
        targetCompleted: completing,
        fadeOut: completing
            ? ref.read(completedCollapsedProvider)
            : ref.read(activeCollapsedProvider),
      );
    } catch (_) {
      // Keep the list responsive even if persistence fails; the next stream
      // value will keep the card in its previous state.
    } finally {
      if (mounted) {
        setState(() {
          _transitioningTaskIds.remove(task.id);
          _strikingTaskIds.remove(task.id);
          _unstrikingTaskIds.remove(task.id);
          _completionPreviewByTaskId.remove(task.id);
          _settledCompletionAnimationTaskIds.remove(task.id);
        });
      }
    }
  }

  Future<void> _moveTaskBetweenSections(
    WidgetRef ref,
    Task task, {
    required bool targetCompleted,
    bool fadeOut = false,
  }) async {
    final sourceSlot = task.status == TaskStatus.completed.value
        ? 'completed'
        : 'active';
    final fromRect = _measureTaskSlot(sourceSlot, task.id);
    if (fromRect == null) {
      await ref.read(taskRepositoryProvider).toggleCompleted(task);
      return;
    }

    final move = _TaskSectionMove(
      task: task,
      targetCompleted: targetCompleted,
      fromRect: fromRect,
    );
    setState(() {
      _sectionMoves[task.id] = move;
    });

    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || _sectionMoves[task.id] != move) {
      return;
    }

    final viewportRect = _measureListViewport();
    final toRect = fadeOut
        ? _collapsedCompletedFadeTarget(fromRect)
        : _sectionMoveTargetRect(
            task.id,
            fromRect,
            viewportRect,
            targetCompleted,
            sourceSlot == 'active',
          );

    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (context) => _MovingTaskOverlay(
        task: _buildTaskWithStatus(task, targetCompleted: targetCompleted),
        strings: ref.read(appStringsProvider),
        fromRect: fromRect,
        toRect: toRect,
        clipRect: viewportRect,
        targetCompleted: targetCompleted,
        fadeOut: fadeOut,
        duration: _sectionMoveDuration,
      ),
    );
    overlay.insert(entry);

    try {
      await Future<void>.delayed(_sectionMoveDuration);
      await ref.read(taskRepositoryProvider).toggleCompleted(task);
      await _waitForTaskStatus(ref, task.id, targetCompleted: targetCompleted);
    } finally {
      if (mounted && _sectionMoves[task.id] == move) {
        setState(() {
          _sectionMoves.remove(task.id);
        });
        await WidgetsBinding.instance.endOfFrame;
      }
      entry.remove();
    }
  }

  Future<void> _waitForTaskStatus(
    WidgetRef ref,
    String taskId, {
    required bool targetCompleted,
  }) async {
    final targetStatus = targetCompleted
        ? TaskStatus.completed.value
        : TaskStatus.active.value;

    bool matches(List<Task> tasks) {
      return tasks.any(
        (task) => task.id == taskId && task.status == targetStatus,
      );
    }

    final currentTasks = ref.read(taskListProvider).asData?.value;
    if (currentTasks != null && matches(currentTasks)) {
      return;
    }

    try {
      await ref
          .read(taskRepositoryProvider)
          .watchVisibleTasks()
          .firstWhere(matches)
          .timeout(const Duration(milliseconds: 900));
      if (mounted) {
        await WidgetsBinding.instance.endOfFrame;
      }
    } catch (_) {
      if (mounted) {
        await WidgetsBinding.instance.endOfFrame;
      }
    }
  }

  List<Task> _buildActiveTasks(
    List<Task> scopedTasks,
    List<_TaskSectionMove> scopedMoves,
  ) {
    final activeTasks = scopedTasks
        .where(
          (task) =>
              task.status == TaskStatus.active.value &&
              !_dragCompletingTaskIds.contains(task.id),
        )
        .toList();

    for (final move in scopedMoves) {
      if (activeTasks.any((task) => task.id == move.task.id)) {
        continue;
      }
      activeTasks.add(_buildTaskWithStatus(move.task, targetCompleted: false));
    }

    return _sortActiveTasks(activeTasks);
  }

  List<Task> _buildCompletedTasks(
    List<Task> scopedTasks,
    List<_TaskSectionMove> scopedMoves,
    List<Task> pendingCompletedTasks,
  ) {
    final movingIntoCompletedIds = scopedMoves
        .where((move) => move.targetCompleted)
        .map((move) => move.task.id)
        .toSet();
    final completedTasks = <Task>[
      ...scopedTasks.where(
        (task) =>
            task.status == TaskStatus.completed.value &&
            !movingIntoCompletedIds.contains(task.id),
      ),
      ...pendingCompletedTasks.where(
        (task) => !movingIntoCompletedIds.contains(task.id),
      ),
    ];

    for (final move in scopedMoves) {
      if (move.targetCompleted) {
        continue;
      }
      if (completedTasks.any((task) => task.id == move.task.id)) {
        continue;
      }
      completedTasks.add(
        _buildTaskWithStatus(move.task, targetCompleted: true),
      );
    }

    return _sortCompletedTasks(completedTasks);
  }

  /// Applies the optimistic drag order to the active task list from the database stream.
  ///
  /// The temporary order is kept only while the visible task set still matches exactly.
  List<Task> _applyOptimisticOrder(List<Task> activeTasks) {
    final order = _optimisticActiveOrder;
    if (order == null) {
      return activeTasks;
    }

    final activeOrder = activeTasks
        .map((task) => task.id)
        .toList(growable: false);
    final activeTaskIds = activeTasks.map((task) => task.id).toSet();
    if (activeTaskIds.length != order.length ||
        !activeTaskIds.containsAll(order)) {
      _optimisticActiveOrder = null;
      return activeTasks;
    }

    if (_sameOrder(activeOrder, order)) {
      _optimisticActiveOrder = null;
      return activeTasks;
    }

    final tasksById = {for (final task in activeTasks) task.id: task};
    return [for (final taskId in order) tasksById[taskId]!];
  }

  List<Task> _sortActiveTasks(List<Task> activeTasks) {
    activeTasks.sort((left, right) {
      final orderComparison = left.sortOrder.compareTo(right.sortOrder);
      if (orderComparison != 0) {
        return orderComparison;
      }
      return right.updatedAt.compareTo(left.updatedAt);
    });
    return activeTasks;
  }

  List<Task> _sortCompletedTasks(List<Task> completedTasks) {
    completedTasks.sort((left, right) {
      final leftCompletedAt = left.completedAt ?? left.updatedAt;
      final rightCompletedAt = right.completedAt ?? right.updatedAt;
      final completedComparison = rightCompletedAt.compareTo(leftCompletedAt);
      if (completedComparison != 0) {
        return completedComparison;
      }
      return right.updatedAt.compareTo(left.updatedAt);
    });
    return completedTasks;
  }

  Task _buildOptimisticCompletedTask(Task task) {
    final completedAt = _dragCompletedAtByTaskId[task.id] ?? DateTime.now();
    return _buildTaskWithStatus(
      task,
      targetCompleted: true,
      completedAt: completedAt,
    );
  }

  Task _buildTaskWithStatus(
    Task task, {
    required bool targetCompleted,
    DateTime? completedAt,
  }) {
    final status = targetCompleted
        ? TaskStatus.completed.value
        : TaskStatus.active.value;
    final resolvedCompletedAt = targetCompleted
        ? completedAt ?? task.completedAt ?? DateTime.now()
        : null;
    final updatedAt = completedAt ?? task.updatedAt;
    return Task(
      id: task.id,
      title: task.title,
      description: task.description,
      dueAt: task.dueAt,
      label: task.label,
      priority: task.priority,
      isImportant: task.isImportant,
      isUrgent: task.isUrgent,
      status: status,
      completedAt: resolvedCompletedAt,
      sortOrder: task.sortOrder,
      createdAt: task.createdAt,
      updatedAt: updatedAt,
    );
  }

  /// 判断两组任务 ID 的顺序是否完全一致。
  ///
  /// 用这个判断可以知道数据库 stream 是否已经追上了用户刚刚拖拽出的视觉顺序。
  bool _sameOrder(List<String> left, List<String> right) {
    if (left.length != right.length) {
      return false;
    }

    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }

  /// 按照 Flutter 拖拽列表的索引规则计算新的显示顺序。
  ///
  /// `newIndex` 在向下拖拽时会包含被移除项原来的位置，因此需要和仓储层保持同样的修正逻辑。
  List<Task> _reorderVisibleTasks(
    List<Task> activeTasks,
    int oldIndex,
    int newIndex,
  ) {
    final adjustedNewIndex = oldIndex < newIndex ? newIndex - 1 : newIndex;
    final reordered = [...activeTasks];
    final item = reordered.removeAt(oldIndex);
    reordered.insert(adjustedNewIndex, item);
    return reordered;
  }

  _SectionMoveSlot? _activeMoveSlotFor(String taskId) {
    final move = _sectionMoves[taskId];
    if (move != null) {
      return move.targetCompleted
          ? _SectionMoveSlot.source
          : _SectionMoveSlot.target;
    }

    final activeSectionAnimatingToCollapsed =
        _activeSectionAnimatingToCollapsed;
    if (activeSectionAnimatingToCollapsed == null) {
      return null;
    }
    return activeSectionAnimatingToCollapsed
        ? _SectionMoveSlot.source
        : _SectionMoveSlot.target;
  }

  _SectionMoveSlot? _completedMoveSlotFor(String taskId) {
    final move = _sectionMoves[taskId];
    if (move == null) {
      return null;
    }
    return move.targetCompleted ? null : _SectionMoveSlot.source;
  }

  Widget _buildMeasuredTaskSlot({
    required String slotName,
    required String taskId,
    required _SectionMoveSlot? moveSlot,
    required Widget child,
    bool visibleDuringAnimation = false,
  }) {
    final measuredChild = KeyedSubtree(
      key: _taskSlotKey(slotName, taskId),
      child: SizedBox(
        height: _listItemExtent,
        child: Padding(
          padding: const EdgeInsets.only(bottom: _listItemGap),
          child: child,
        ),
      ),
    );
    if (moveSlot == null) {
      return measuredChild;
    }

    final source = moveSlot == _SectionMoveSlot.source;
    return TweenAnimationBuilder<double>(
      duration: _sectionMoveDuration,
      curve: Curves.linear,
      tween: Tween<double>(begin: source ? 1 : 0, end: source ? 0 : 1),
      builder: (context, heightFactor, child) {
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: heightFactor,
            child: Opacity(
              opacity: visibleDuringAnimation ? heightFactor : 0,
              child: child,
            ),
          ),
        );
      },
      child: measuredChild,
    );
  }

  GlobalKey _taskSlotKey(String slotName, String taskId) {
    final key = '$slotName:$taskId';
    return _taskSlotKeys.putIfAbsent(key, GlobalKey.new);
  }

  Rect? _measureTaskSlot(String slotName, String taskId) {
    final context = _taskSlotKeys['$slotName:$taskId']?.currentContext;
    final renderObject = context?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    final overlayBox = Overlay.of(context!).context.findRenderObject();
    if (overlayBox is! RenderBox) {
      return null;
    }
    final globalTopLeft = renderObject.localToGlobal(Offset.zero);
    final overlayTopLeft = overlayBox.globalToLocal(globalTopLeft);
    return overlayTopLeft & renderObject.size;
  }

  Rect? _measureListViewport() {
    final context = _listViewportKey.currentContext;
    final renderObject = context?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    final overlayBox = Overlay.of(context!).context.findRenderObject();
    if (overlayBox is! RenderBox) {
      return null;
    }
    final globalTopLeft = renderObject.localToGlobal(Offset.zero);
    final overlayTopLeft = overlayBox.globalToLocal(globalTopLeft);
    return overlayTopLeft & renderObject.size;
  }

  Rect? _measureCompletedDivider() {
    final context = _completedDividerKey.currentContext;
    final renderObject = context?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    final overlayBox = Overlay.of(context!).context.findRenderObject();
    if (overlayBox is! RenderBox) {
      return null;
    }
    final globalTopLeft = renderObject.localToGlobal(Offset.zero);
    final overlayTopLeft = overlayBox.globalToLocal(globalTopLeft);
    return overlayTopLeft & renderObject.size;
  }

  Rect _sectionMoveTargetRect(
    String taskId,
    Rect fromRect,
    Rect? viewportRect,
    bool targetCompleted,
    bool sourceWasActive,
  ) {
    if (!targetCompleted) {
      return _measureTaskSlot('active', taskId) ??
          _offscreenMoveTarget(fromRect, viewportRect, targetCompleted);
    }

    final dividerRect = _measureCompletedDivider();
    final targetRect = _measureTaskSlot('completed-target', taskId);
    if (targetRect != null) {
      return sourceWasActive
          ? targetRect.translate(0, -fromRect.height)
          : targetRect;
    }
    if (dividerRect == null) {
      return _offscreenMoveTarget(fromRect, viewportRect, targetCompleted);
    }
    final fallbackRect = Rect.fromLTWH(
      fromRect.left,
      dividerRect.bottom + _listItemGap,
      fromRect.width,
      fromRect.height,
    );
    return sourceWasActive
        ? fallbackRect.translate(0, -fromRect.height)
        : fallbackRect;
  }

  Rect _collapsedCompletedFadeTarget(Rect fromRect) {
    return fromRect.translate(0, -fromRect.height * 0.2);
  }

  Rect _offscreenMoveTarget(
    Rect fromRect,
    Rect? viewportRect,
    bool targetCompleted,
  ) {
    if (viewportRect == null) {
      return fromRect;
    }
    final targetTop = targetCompleted
        ? viewportRect.bottom
        : viewportRect.top - fromRect.height;
    return Rect.fromLTWH(
      fromRect.left,
      targetTop,
      fromRect.width,
      fromRect.height,
    );
  }

  /// 为列表区域提供统一的淡入加纵向展开过渡。
  Widget _buildSectionTransition(Widget child, Animation<double> animation) {
    final curvedAnimation = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curvedAnimation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.04),
          end: Offset.zero,
        ).animate(curvedAnimation),
        child: SizeTransition(
          sizeFactor: curvedAnimation,
          axisAlignment: -1,
          child: child,
        ),
      ),
    );
  }

  Widget _buildActiveDivider(
    WidgetRef ref,
    List<Task> activeTasks,
    bool collapsed,
    AppStrings strings,
  ) {
    return SizedBox(
      height: _listItemExtent,
      child: Padding(
        padding: const EdgeInsets.only(bottom: _listItemGap),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            _toggleActiveCollapsed(ref, collapsed);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                _SectionLabel(
                  title: strings.activeTasks,
                  subtitle: strings.itemCount(activeTasks.length),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: collapsed ? 0 : 0.5,
                  duration: _completedSectionAnimationDuration,
                  curve: Curves.easeInOutCubic,
                  child: const Icon(
                    Icons.expand_more_rounded,
                    color: Color(0xFF68756F),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompletedDivider(
    WidgetRef ref,
    List<Task> completedTasks,
    bool collapsed,
    AppStrings strings,
  ) {
    return SizedBox(
      key: const ValueKey('completed-divider'),
      height: _listItemExtent,
      child: Padding(
        padding: const EdgeInsets.only(bottom: _listItemGap),
        child: KeyedSubtree(
          key: _completedDividerKey,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              ref.read(completedCollapsedProvider.notifier).state = !collapsed;
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  _SectionLabel(
                    title: strings.completedTasks,
                    subtitle: strings.itemCount(completedTasks.length),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: collapsed ? 0 : 0.5,
                    duration: _completedSectionAnimationDuration,
                    curve: Curves.easeInOutCubic,
                    child: const Icon(
                      Icons.expand_more_rounded,
                      color: Color(0xFF68756F),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建已完成任务区域，作为 [ReorderableListView] 的 footer。
  Widget _buildCompletedTasksFooter(
    WidgetRef ref,
    List<Task> completedTasks,
    List<_TaskSectionMove> scopedMoves,
    bool collapsed,
    bool isSelectionMode,
    Set<String> selectedIds,
    AppStrings strings,
  ) {
    final completedTargetMoves = collapsed
        ? const <_TaskSectionMove>[]
        : scopedMoves
              .where((move) => move.targetCompleted)
              .toList(growable: false);
    return AnimatedSwitcher(
      duration: _completedSectionAnimationDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: _buildSectionTransition,
      child: collapsed
          ? const SizedBox.shrink(key: ValueKey('completed-collapsed'))
          : KeyedSubtree(
              key: const ValueKey('completed-expanded'),
              child: Column(
                children: [
                  for (final move in completedTargetMoves)
                    _buildMeasuredTaskSlot(
                      slotName: 'completed-target',
                      taskId: move.task.id,
                      moveSlot: _SectionMoveSlot.target,
                      child: const SizedBox.expand(),
                    ),
                  for (var i = 0; i < completedTasks.length; i++)
                    Builder(
                      builder: (context) {
                        final task = completedTasks[i];
                        final completionPreview =
                            _completionPreviewByTaskId[task.id];
                        final completionSettled =
                            _settledCompletionAnimationTaskIds.contains(
                              task.id,
                            );
                        final strikeTarget = completionPreview == false
                            ? 0.0
                            : 1.0;
                        final animateUnstrike =
                            _unstrikingTaskIds.contains(task.id) &&
                            !completionSettled;
                        return _buildMeasuredTaskSlot(
                          slotName: 'completed',
                          taskId: task.id,
                          moveSlot: _completedMoveSlotFor(task.id),
                          child: GestureDetector(
                            key: ValueKey('completed-${task.id}'),
                            onLongPressEnd: (_) =>
                                _enterSelectionModeAndToggle(ref, task.id),
                            child: TweenAnimationBuilder<double>(
                              duration: animateUnstrike
                                  ? _completionStrikeDuration
                                  : Duration.zero,
                              curve: Curves.easeOutCubic,
                              tween: Tween<double>(
                                begin: animateUnstrike ? 1 : strikeTarget,
                                end: strikeTarget,
                              ),
                              builder: (context, strikeProgress, child) {
                                return TaskCard(
                                  task: task,
                                  strings: strings,
                                  isSelectionMode: isSelectionMode,
                                  isSelected: selectedIds.contains(task.id),
                                  completionStrikeProgress:
                                      completionPreview == null
                                      ? null
                                      : strikeProgress,
                                  completionPreviewCompleted: completionPreview,
                                  onSelectToggle: () =>
                                      _toggleSelection(ref, task.id),
                                  onEditTap: () {
                                    if (isSelectionMode) {
                                      _toggleSelection(ref, task.id);
                                      return;
                                    }
                                    _openTaskEditor(context, task);
                                  },
                                  onTap: () {
                                    if (isSelectionMode) {
                                      _toggleSelection(ref, task.id);
                                      return;
                                    }
                                    _openTaskDetails(context, task, strings);
                                  },
                                  onCompleteToggle: () =>
                                      _toggleCompletedWithTransition(ref, task),
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }

  void _openTaskEditor(BuildContext context, Task task) {
    Navigator.of(context).push(
      buildTaskEditorRoute(
        taskId: task.id,
        initialValue: TaskEditorValue.fromTask(task),
      ),
    );
  }

  void _openTaskDetails(BuildContext context, Task task, AppStrings strings) {
    showTaskDetailsSheet(context: context, task: task, strings: strings);
  }
}

enum _SectionMoveSlot { source, target }

class _TaskSectionMove {
  const _TaskSectionMove({
    required this.task,
    required this.targetCompleted,
    required this.fromRect,
  });

  final Task task;
  final bool targetCompleted;
  final Rect fromRect;
}

class _MovingTaskOverlay extends StatelessWidget {
  const _MovingTaskOverlay({
    required this.task,
    required this.strings,
    required this.fromRect,
    required this.toRect,
    required this.clipRect,
    required this.targetCompleted,
    required this.fadeOut,
    required this.duration,
  });

  final Task task;
  final AppStrings strings;
  final Rect fromRect;
  final Rect toRect;
  final Rect? clipRect;
  final bool targetCompleted;
  final bool fadeOut;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: duration,
      curve: Curves.linear,
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, progress, child) {
        final rect = Rect.lerp(fromRect, toRect, progress)!;
        final opacity = fadeOut ? 1 - progress : 1.0;
        final positioned = Positioned.fromRect(
          rect: rect,
          child: IgnorePointer(
            child: Opacity(opacity: opacity, child: child),
          ),
        );
        final clipRect = this.clipRect;
        if (clipRect == null) {
          return positioned;
        }
        return Positioned.fill(
          child: ClipRect(
            clipper: _OverlayRectClipper(clipRect),
            child: Stack(children: [positioned]),
          ),
        );
      },
      child: Align(
        alignment: Alignment.topCenter,
        child: TaskCard(
          task: task,
          strings: strings,
          onTap: () {},
          onEditTap: () {},
          onCompleteToggle: () {},
          completionPreviewCompleted: targetCompleted,
          completionStrikeProgress: targetCompleted ? 1.0 : null,
        ),
      ),
    );
  }
}

class _OverlayRectClipper extends CustomClipper<Rect> {
  const _OverlayRectClipper(this.rect);

  final Rect rect;

  @override
  Rect getClip(Size size) => rect;

  @override
  bool shouldReclip(covariant _OverlayRectClipper oldClipper) {
    return oldClipper.rect != rect;
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, required this.subtitle});

  /// 分区标题。
  final String title;

  /// 分区副标题，一般用于展示数量。
  final String subtitle;

  @override
  /// 构建分区标题行。
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: TaskCard.height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 12),
          Text(subtitle, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}
