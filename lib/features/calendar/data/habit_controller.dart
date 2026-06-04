import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart'
    show StateNotifier, StateNotifierProvider;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final habitControllerProvider =
    StateNotifierProvider<HabitController, List<HabitEntry>>(
      (ref) => HabitController(const HabitStorage()),
    );

class HabitEntry {
  const HabitEntry({
    required this.id,
    required this.title,
    this.description = '',
    required this.createdAt,
    this.checkedDateKeys = const {},
  });

  factory HabitEntry.fromJson(Map<String, Object?> json) {
    final checked = switch (json['checkedDateKeys']) {
      List<Object?> values => values.whereType<String>().toSet(),
      _ => <String>{},
    };
    final rawId = json['id'];
    final rawTitle = json['title'];
    final rawDescription = json['description'];
    final rawCreatedAt = json['createdAt'];
    return HabitEntry(
      id: rawId is String ? rawId : '',
      title: rawTitle is String ? rawTitle : '',
      description: rawDescription is String ? rawDescription : '',
      createdAt: DateTime.tryParse(rawCreatedAt is String ? rawCreatedAt : '') ??
          DateTime.now(),
      checkedDateKeys: checked,
    );
  }

  final String id;
  final String title;
  final String description;
  final DateTime createdAt;
  final Set<String> checkedDateKeys;

  bool isCheckedOn(DateTime date) {
    return checkedDateKeys.contains(habitDateKey(date));
  }

  HabitEntry copyWith({
    String? title,
    String? description,
    Set<String>? checkedDateKeys,
  }) {
    return HabitEntry(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      createdAt: createdAt,
      checkedDateKeys: checkedDateKeys ?? this.checkedDateKeys,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
      'checkedDateKeys': checkedDateKeys.toList()..sort(),
    };
  }
}

class HabitController extends StateNotifier<List<HabitEntry>> {
  HabitController(this._storage) : super(const []) {
    _hydrate();
  }

  final HabitStorage _storage;
  var _hydrated = false;

  Future<void> _hydrate() async {
    state = await _storage.load();
    _hydrated = true;
  }

  Future<void> createHabit({
    required String title,
    String description = '',
  }) async {
    final now = DateTime.now();
    final habit = HabitEntry(
      id: '${now.microsecondsSinceEpoch}',
      title: title.trim(),
      description: description.trim(),
      createdAt: now,
    );
    state = [...state, habit];
    await _persist();
  }

  Future<void> toggleCheck(String habitId, DateTime date) async {
    final key = habitDateKey(date);
    state = [
      for (final habit in state)
        if (habit.id == habitId)
          habit.copyWith(
            checkedDateKeys: _toggledDateKeys(habit.checkedDateKeys, key),
          )
        else
          habit,
    ];
    await _persist();
  }

  Future<void> deleteHabit(String habitId) async {
    state = state.where((habit) => habit.id != habitId).toList(growable: false);
    await _persist();
  }

  Future<void> _persist() async {
    if (!_hydrated) {
      return;
    }
    await _storage.save(state);
  }
}

class HabitStorage {
  const HabitStorage();

  static const _fileName = 'tasknet_habits.json';

  Future<List<HabitEntry>> load() async {
    try {
      final file = await _storageFile();
      if (!await file.exists()) {
        return const [];
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List<Object?>) {
        return const [];
      }
      final habits = <HabitEntry>[];
      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }
        final habit = HabitEntry.fromJson(Map<String, Object?>.from(item));
        if (habit.id.isNotEmpty && habit.title.isNotEmpty) {
          habits.add(habit);
        }
      }
      return habits;
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<HabitEntry> habits) async {
    final file = await _storageFile();
    final encoded = habits.map((habit) => habit.toJson()).toList();
    await file.writeAsString(jsonEncode(encoded), flush: true);
  }

  Future<File> _storageFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File(p.join(directory.path, _fileName));
  }
}

String habitDateKey(DateTime date) {
  final normalized = DateTime(date.year, date.month, date.day);
  return normalized.toIso8601String();
}

Set<String> _toggledDateKeys(Set<String> source, String key) {
  final next = {...source};
  if (!next.add(key)) {
    next.remove(key);
  }
  return next;
}
