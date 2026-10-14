import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'services/cache_service.dart';
import 'services/log_service.dart';
import 'ui/main_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize logging service with app data directory
  try {
    final cacheService = CacheService();
    final dataDir = await cacheService.dataDirectory;
    await LogService.instance.init(dataDir);
    LogService.instance.info('App', '文庫輕小說追更檢查器啟動');
  } catch (e) {
    debugPrint('LogService init error: $e');
  }

  // Desktop window configuration
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    try {
      await windowManager.ensureInitialized();
      WindowOptions windowOptions = const WindowOptions(
        size: Size(1100, 720),
        minimumSize: Size(900, 600),
        center: true,
        skipTaskbar: false,
        title: '文庫輕小說追更檢查器 (NovelUpdateChecker)',
      );
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    } catch (_) {}
  }

  runApp(const NovelUpdateCheckerApp());
}

class NovelUpdateCheckerApp extends StatelessWidget {
  const NovelUpdateCheckerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '文庫輕小說追更檢查器',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3F51B5), // Indigo Light Novel Theme
          brightness: Brightness.light,
        ),
        fontFamily: Platform.isWindows ? 'Microsoft JhengHei UI' : null,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3F51B5),
          brightness: Brightness.dark,
        ),
        fontFamily: Platform.isWindows ? 'Microsoft JhengHei UI' : null,
      ),
      themeMode: ThemeMode.system,
      home: const MainScreen(),
    );
  }
}
