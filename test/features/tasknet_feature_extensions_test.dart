import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/calendar/data/habit_controller.dart';
import 'package:frontend/features/tasks/data/local_database.dart' show Task;
import 'package:frontend/features/tasks/data/task_schedule_controller.dart';

void main() {
  group('Task schedule metadata', () {
    test('creates metadata from task dueAt', () {
      final dueAt = DateTime(2026, 6, 4, 18, 30);
      final task = _task(dueAt: dueAt);

      final schedule = TaskScheduleMetadata.fromTask(task);

      expect(schedule.endAt, dueAt);
    });

    test('task occurs on date', () {
      final dueAt = DateTime(2026, 6, 4, 9);
      final task = _task(dueAt: dueAt);

      expect(taskOccursOnDate(task, DateTime(2026, 6, 4)), isTrue);
      expect(taskOccursOnDate(task, DateTime(2026, 6, 5)), isFalse);
      expect(taskOccursOnDate(task, DateTime(2026, 6, 3)), isFalse);
    });

    test('controller persists schedule changes and removals', () async {
      final storage = _MemoryTaskScheduleStorage();
      final controller = TaskScheduleController(storage);
      await Future<void>.delayed(Duration.zero);

      final schedule = TaskScheduleMetadata(
        endAt: DateTime(2026, 6, 4, 10),
      );
      await controller.saveSchedule('task-1', schedule);

      expect(controller.state['task-1'], schedule);
      expect(storage.saved['task-1'], schedule);

      await controller.removeSchedules(['task-1']);

      expect(controller.state.containsKey('task-1'), isFalse);
      expect(storage.saved.containsKey('task-1'), isFalse);
    });
  });

  group('Habit controller', () {
    test('creates, toggles, and deletes a habit', () async {
      final storage = _MemoryHabitStorage();
      final controller = HabitController(storage);
      await Future<void>.delayed(Duration.zero);

      await controller.createHabit(title: 'Read');

      expect(controller.state, hasLength(1));
      expect(storage.saved, hasLength(1));

      final habit = controller.state.single;
      final day = DateTime(2026, 6, 4);

      await controller.toggleCheck(habit.id, day);
      expect(controller.state.single.isCheckedOn(day), isTrue);

      await controller.toggleCheck(habit.id, day);
      expect(controller.state.single.isCheckedOn(day), isFalse);

      await controller.deleteHabit(habit.id);
      expect(controller.state, isEmpty);
      expect(storage.saved, isEmpty);
    });
  });
}

Task _task({
  DateTime? dueAt,
  int priority = 3,
  int status = 0,
}) {
  final now = DateTime(2026, 6, 4, 8);
  return Task(
    id: 'task-1',
    title: 'Task',
    dueAt: dueAt,
    priority: priority,
    isImportant: false,
    isUrgent: false,
    status: status,
    sortOrder: 0,
    createdAt: now,
    updatedAt: now,
  );
}

class _MemoryTaskScheduleStorage extends TaskScheduleStorage {
  Map<String, TaskScheduleMetadata> saved = const {};

  @override
  Future<Map<String, TaskScheduleMetadata>> load() async {
    return saved;
  }

  @override
  Future<void> save(Map<String, TaskScheduleMetadata> schedules) async {
    saved = Map<String, TaskScheduleMetadata>.from(schedules);
  }
}

class _MemoryHabitStorage extends HabitStorage {
  List<HabitEntry> saved = const [];

  @override
  Future<List<HabitEntry>> load() async {
    return saved;
  }

  @override
  Future<void> save(List<HabitEntry> habits) async {
    saved = List<HabitEntry>.from(habits);
  }
}
