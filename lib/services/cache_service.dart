import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/app_config.dart';
import '../models/book_item.dart';

class CacheService {
  static const String configFileName = 'config.json';
  static const String cacheFileName = 'cache.json';

  Directory? _dataDir;

  Future<Directory> get dataDirectory async {
    if (_dataDir != null) return _dataDir!;

    try {
      // Prefer application support directory for cross-platform safety
      final appSupport = await getApplicationSupportDirectory();
      final dir = Directory(p.join(appSupport.path, 'NovelUpdateChecker'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // Seamless migration from legacy com.example directory if present
      try {
        final legacyPath = dir.path.replaceFirst(r'\com.volcanohsieh\', r'\com.example\');
        if (legacyPath != dir.path) {
          final legacyDir = Directory(legacyPath);
          if (await legacyDir.exists()) {
            final oldCache = File(p.join(legacyDir.path, cacheFileName));
            final newCache = File(p.join(dir.path, cacheFileName));
            if (await oldCache.exists() && !await newCache.exists()) {
              await oldCache.copy(newCache.path);
            }

            final oldConfig = File(p.join(legacyDir.path, configFileName));
            final newConfig = File(p.join(dir.path, configFileName));
            if (await oldConfig.exists() && !await newConfig.exists()) {
              await oldConfig.copy(newConfig.path);
            }
          }
        }
      } catch (_) {}

      _dataDir = dir;
      return _dataDir!;
    } catch (_) {
      // Fallback to local executable directory or current directory
      final current = Directory.current;
      _dataDir = current;
      return current;
    }
  }

  Future<File> getConfigFile() async {
    final dir = await dataDirectory;
    return File(p.join(dir.path, configFileName));
  }

  Future<File> getCacheFile() async {
    final dir = await dataDirectory;
    return File(p.join(dir.path, cacheFileName));
  }

  /// Load AppConfig from JSON
  Future<AppConfig> loadConfig() async {
    try {
      final file = await getConfigFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final Map<String, dynamic> json = jsonDecode(content);
        return AppConfig.fromJson(json);
      }
    } catch (e) {
      // Ignore and use default
    }
    return AppConfig();
  }

  /// Save AppConfig to JSON
  Future<void> saveConfig(AppConfig config) async {
    try {
      final file = await getConfigFile();
      final content = const JsonEncoder.withIndent('  ').convert(config.toJson());
      await file.writeAsString(content);
    } catch (e) {
      // Log or handle error
    }
  }

  /// Load cached books map (keyed by book title or folder path)
  Future<Map<String, BookItem>> loadCachedBooks() async {
    final Map<String, BookItem> result = {};
    try {
      final file = await getCacheFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final Map<String, dynamic> json = jsonDecode(content);
        final booksJson = json['books'] as Map<String, dynamic>? ?? {};
        for (final entry in booksJson.entries) {
          try {
            final book = BookItem.fromJson(entry.value as Map<String, dynamic>);
            result[book.folderPath.isNotEmpty ? book.folderPath : book.title] = book;
          } catch (_) {}
        }
      }
    } catch (e) {
      // Ignore
    }
    return result;
  }

  /// Save cached books map to JSON
  Future<void> saveCachedBooks(List<BookItem> books) async {
    try {
      final file = await getCacheFile();
      final Map<String, dynamic> booksMap = {};
      for (final book in books) {
        final key = book.folderPath.isNotEmpty ? book.folderPath : book.title;
        booksMap[key] = book.toJson();
      }
      final payload = {
        'version': 1,
        'updated_at': DateTime.now().toIso8601String(),
        'books': booksMap,
      };
      final content = const JsonEncoder.withIndent('  ').convert(payload);
      await file.writeAsString(content);
    } catch (e) {
      // Log or handle error
    }
  }

  /// Delete cache.json file from disk
  Future<bool> clearCache() async {
    try {
      final file = await getCacheFile();
      if (await file.exists()) {
        await file.delete();
        return true;
      }
    } catch (_) {}
    return false;
  }
}
