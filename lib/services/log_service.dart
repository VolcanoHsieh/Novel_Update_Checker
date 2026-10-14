import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

enum LogLevel { debug, info, warn, error }

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;
  final String? error;
  final String? stackTrace;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.error,
    this.stackTrace,
  });

  String get formattedTime {
    final y = timestamp.year.toString().padLeft(4, '0');
    final m = timestamp.month.toString().padLeft(2, '0');
    final d = timestamp.day.toString().padLeft(2, '0');
    final h = timestamp.hour.toString().padLeft(2, '0');
    final min = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min:$s';
  }

  @override
  String toString() {
    final lvl = level.name.toUpperCase().padRight(5);
    var str = '[$formattedTime] [$lvl] [$tag] $message';
    if (error != null && error!.isNotEmpty) str += ' | Error: $error';
    if (stackTrace != null && stackTrace!.isNotEmpty) str += '\n$stackTrace';
    return str;
  }
}

class LogService extends ChangeNotifier {
  static final LogService instance = LogService._internal();
  LogService._internal();

  final List<LogEntry> _logs = [];
  File? _logFile;
  IOSink? _sink;

  List<LogEntry> get logs => List.unmodifiable(_logs);
  File? get logFile => _logFile;

  Future<void> init(Directory dataDir) async {
    try {
      _logFile = File(p.join(dataDir.path, 'app.log'));
      // Truncate if larger than 5MB to keep it lightweight
      if (await _logFile!.exists()) {
        final length = await _logFile!.length();
        if (length > 5 * 1024 * 1024) {
          await _logFile!.writeAsString('--- Log rotated at ${DateTime.now()} ---\n');
        }
      }
      _sink = _logFile!.openWrite(mode: FileMode.append);
      log(LogLevel.info, 'System', '日誌系統已初始化。檔案路徑: ${_logFile!.path}');
    } catch (e) {
      debugPrint('Failed to initialize log file: $e');
    }
  }

  void log(LogLevel level, String tag, String message, {dynamic error, StackTrace? stackTrace}) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
      error: error?.toString(),
      stackTrace: stackTrace?.toString(),
    );

    _logs.add(entry);
    if (_logs.length > 800) {
      _logs.removeAt(0);
    }

    try {
      _sink?.writeln(entry.toString());
      _sink?.flush();
    } catch (_) {}

    debugPrint(entry.toString());
    notifyListeners();
  }

  void info(String tag, String message) => log(LogLevel.info, tag, message);
  void warn(String tag, String message, {dynamic error}) => log(LogLevel.warn, tag, message, error: error);
  void error(String tag, String message, {dynamic error, StackTrace? stackTrace}) =>
      log(LogLevel.error, tag, message, error: error, stackTrace: stackTrace);
  void debug(String tag, String message) => log(LogLevel.debug, tag, message);

  Future<void> clear() async {
    _logs.clear();
    try {
      await _sink?.close();
      if (_logFile != null) {
        await _logFile!.writeAsString('');
        _sink = _logFile!.openWrite(mode: FileMode.append);
      }
    } catch (_) {}
    notifyListeners();
  }
}
