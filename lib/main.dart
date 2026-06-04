/*
 * TaskNet Flutter 应用入口文件。
 *
 * 这个文件负责初始化 Flutter 运行环境、中文日期格式化能力，
 * 并把整个应用挂载到 Riverpod 的全局 ProviderScope 中。
 * 业务逻辑和页面结构都被拆分到其他模块，这里尽量保持轻量。
 */
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app.dart';
import 'app/preferences/app_preferences.dart';

/// 应用主入口。
///
/// 在启动界面前先初始化日期格式，这样首页和任务卡片就能直接展示当前语言的日期文本。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await initializeDateFormatting();
  final initialPreferences = await const AppPreferencesStorage().load();
  runApp(
    ProviderScope(
      overrides: [
        darkModeProvider.overrideWith((ref) => initialPreferences.darkMode),
        appLanguageProvider.overrideWith((ref) => initialPreferences.language),
        taskLabelsProvider.overrideWith((ref) => initialPreferences.taskLabels),
      ],
      child: const TaskNetApp(),
    ),
  );
}
