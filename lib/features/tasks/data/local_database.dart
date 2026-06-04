/*
 * TaskNet 本地数据库定义文件。
 *
 * 这是离线优先架构的核心文件之一，负责声明：
 * - 任务表结构
 * - 草稿表结构
 * - SQLite 数据库连接方式
 * - Drift 数据库入口
 *
 * 第一版所有任务相关操作都先落本地数据库，后续再在此基础上继续扩展同步能力。
 */
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'local_database.g.dart';

/// 任务表定义。
///
/// 保存第一版任务页真正需要落库的所有字段，并预留后续状态扩展空间。
class Tasks extends Table {
  /// 本地任务唯一标识。
  TextColumn get id => text()();

  /// 任务标题，第一版必填。
  TextColumn get title => text()();

  /// 任务描述，可为空。
  TextColumn get description => text().nullable()();

  /// 截止时间，可为空。
  DateTimeColumn get dueAt => dateTime().nullable()();

  /// 任务标签，可为空（空表示未设置标签）。
  TextColumn get label => text().nullable()();

  /// 优先级，默认值为 3。
  IntColumn get priority => integer().withDefault(const Constant(3))();

  /// 是否重要。
  BoolColumn get isImportant => boolean().withDefault(const Constant(false))();

  /// 是否紧急。
  BoolColumn get isUrgent => boolean().withDefault(const Constant(false))();

  /// 任务状态。
  IntColumn get status => integer().withDefault(const Constant(0))();

  /// 完成时间，仅在任务被标记完成后有值。
  DateTimeColumn get completedAt => dateTime().nullable()();

  /// 首页手动拖拽排序使用的排序值。
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// 任务创建时间。
  DateTimeColumn get createdAt => dateTime()();

  /// 任务更新时间。
  DateTimeColumn get updatedAt => dateTime()();

  @override
  /// 指定任务表主键。
  Set<Column<Object>> get primaryKey => {id};
}

/// 草稿表定义。
///
/// 第一版只需要保存单个任务编辑草稿，因此使用固定 key 的简单表结构即可。
class DraftEntries extends Table {
  /// 草稿主键。
  TextColumn get key => text()();

  /// 草稿中的标题内容。
  TextColumn get title => text().nullable()();

  /// 草稿中的描述内容。
  TextColumn get description => text().nullable()();

  /// 草稿中的截止时间。
  DateTimeColumn get dueAt => dateTime().nullable()();

  /// 草稿中的标签。
  TextColumn get label => text().nullable()();

  /// 草稿中的优先级。
  IntColumn get priority => integer().withDefault(const Constant(3))();

  /// 草稿中的重要标记。
  BoolColumn get isImportant => boolean().withDefault(const Constant(false))();

  /// 草稿中的紧急标记。
  BoolColumn get isUrgent => boolean().withDefault(const Constant(false))();

  /// 草稿最后修改时间。
  DateTimeColumn get updatedAt => dateTime()();

  @override
  /// 指定草稿表主键。
  Set<Column<Object>> get primaryKey => {key};
}

/// 创建懒加载数据库连接。
///
/// 只有在真正访问数据库时才创建 SQLite 文件，减少应用启动时的无谓开销。
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(p.join(directory.path, 'tasknet.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

/// 应用本地数据库入口。
///
/// 所有 Repository 都通过这个类访问具体表结构和数据库操作能力。
@DriftDatabase(tables: [Tasks, DraftEntries])
class LocalDatabase extends _$LocalDatabase {
  LocalDatabase() : super(_openConnection());

  @override
  /// 当前数据库 schema 版本。
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.addColumn(tasks, tasks.label);
        await migrator.addColumn(draftEntries, draftEntries.label);
      }
    },
  );
}
