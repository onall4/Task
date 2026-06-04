/*
 * TaskNet 全局主题定义文件。
 *
 * 这个文件集中管理第一版应用的颜色、卡片、导航栏、输入框和文字层级等视觉规则。
 * 这样做可以保证首页、设置页、编辑页共享一套统一的设计语言，便于后续继续迭代。
 */
import 'package:flutter/material.dart';

/// 全局主题构建器。
///
/// 当前提供亮色和深色两套主题，二者共用克制、柔和、低噪声的 TaskNet 视觉语言。
class AppTheme {
  /// 缓存亮色主题，避免语言切换等非主题操作重复构建整套 ThemeData。
  static ThemeData? _cachedLightTheme;

  /// 缓存深色主题，避免设置页频繁重建时重复构建整套 ThemeData。
  static ThemeData? _cachedDarkTheme;

  /// 生成第一版应用使用的亮色主题。
  ///
  /// 视觉目标是柔和、克制、舒适的高完成度轻任务管理体验。
  static ThemeData light() {
    final cachedTheme = _cachedLightTheme;
    if (cachedTheme != null) {
      return cachedTheme;
    }

    const seed = Color(0xFF476C63);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
      surface: const Color(0xFFFFFCF7),
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFFF5F1EA),
    );

    return _cachedLightTheme = base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
          color: const Color(0xFF1F2A26),
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: const Color(0xFF1F2A26),
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: const Color(0xFF2B3733),
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(
          height: 1.35,
          color: const Color(0xFF384540),
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          height: 1.35,
          color: const Color(0xFF53605C),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Color(0xFF1F2A26),
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: Colors.white.withValues(alpha: 0.88),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(
            color: const Color(0xFFE8DED0).withValues(alpha: 0.75),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFFF5F1EA),
        indicatorColor: const Color(0xFFE1EEE7),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? const Color(0xFF33544B) : const Color(0xFF72807A),
          );
        }),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Color(0xFF33544B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: const Color(0xFFF0E8DB),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          color: Color(0xFF5B635C),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: Color(0xFFE5DBCF)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: Color(0xFFE5DBCF)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: Color(0xFF476C63), width: 1.5),
        ),
      ),
    );
  }

  /// 生成第一版应用使用的深色主题。
  ///
  /// 深色主题不是纯黑高对比风格，而是偏暖的深灰绿色，尽量保持夜间阅读舒适。
  static ThemeData dark() {
    final cachedTheme = _cachedDarkTheme;
    if (cachedTheme != null) {
      return cachedTheme;
    }

    const seed = Color(0xFF86A89B);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
      surface: const Color(0xFF171D1A),
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFF121713),
      fontFamily: 'sans-serif',
    );

    return _cachedDarkTheme = base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
          color: const Color(0xFFEAF1EC),
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: const Color(0xFFEAF1EC),
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: const Color(0xFFDDE7E1),
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(
          height: 1.35,
          color: const Color(0xFFC9D6CF),
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          height: 1.35,
          color: const Color(0xFFACBBB3),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF171D1A),
        foregroundColor: Color(0xFFEAF1EC),
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF202822).withValues(alpha: 0.94),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(
            color: const Color(0xFF354239).withValues(alpha: 0.9),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF121713),
        indicatorColor: const Color(0xFF2A3A33),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? const Color(0xFFA8D4C5) : const Color(0xFF93A59B),
          );
        }),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Color(0xFFA8D4C5),
        foregroundColor: Color(0xFF15201B),
        elevation: 0,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: const Color(0xFF263128),
        selectedColor: const Color(0xFF365548),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          color: Color(0xFFD8E5DE),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1C241F),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: Color(0xFF334039)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: Color(0xFF334039)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: Color(0xFFA8D4C5), width: 1.5),
        ),
      ),
      dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF202822)),
    );
  }
}
