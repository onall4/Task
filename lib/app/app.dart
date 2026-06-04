/*
 * TaskNet 应用壳入口。
 *
 * 这里统一装配全局主题、应用标题和根页面壳，
 * 让具体业务页面专注于自身职责，而不用关心 MaterialApp 级别的配置。
 */
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:frontend/app/preferences/app_preferences.dart';
import 'package:frontend/app/theme/app_theme.dart';
import 'package:frontend/features/navigation/presentation/tasknet_shell.dart';

/// 应用根级 Widget。
///
/// 负责提供全局主题和首个页面容器，是整个 Flutter 界面的总入口。
class TaskNetApp extends ConsumerWidget {
  const TaskNetApp({super.key});

  @override
  /// 构建应用根级 MaterialApp。
  Widget build(BuildContext context, WidgetRef ref) {
    final darkMode = ref.watch(darkModeProvider);
    final language = ref.watch(appLanguageProvider);

    return MaterialApp(
      title: 'TaskNet',
      debugShowCheckedModeBanner: false,
      theme: darkMode ? AppTheme.dark() : AppTheme.light(),
      themeAnimationDuration: const Duration(milliseconds: 180),
      themeAnimationCurve: Curves.easeOutCubic,
      locale: Locale(language.name),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      home: const TaskNetShell(),
    );
  }
}
