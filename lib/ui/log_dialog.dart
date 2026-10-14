import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/log_service.dart';

class LogDialog extends StatefulWidget {
  const LogDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const LogDialog(),
    );
  }

  @override
  State<LogDialog> createState() => _LogDialogState();
}

class _LogDialogState extends State<LogDialog> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  LogLevel? _selectedLevel;
  String _filterQuery = '';
  bool _autoScroll = true;

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Color _getLevelColor(LogLevel level, bool isDark) {
    switch (level) {
      case LogLevel.error:
        return Colors.redAccent;
      case LogLevel.warn:
        return Colors.orangeAccent;
      case LogLevel.info:
        return isDark ? Colors.lightBlueAccent : Colors.blue.shade700;
      case LogLevel.debug:
        return isDark ? Colors.tealAccent : Colors.teal.shade700;
    }
  }

  void _openLogFile() {
    final file = LogService.instance.logFile;
    if (file != null && file.existsSync()) {
      if (Platform.isWindows) {
        Process.run('notepad.exe', [file.path]);
      } else {
        Process.run('open', [file.path]);
      }
    }
  }

  void _openFolder() {
    final file = LogService.instance.logFile;
    if (file != null) {
      if (Platform.isWindows) {
        Process.run('explorer.exe', ['/select,', file.path]);
      } else {
        Process.run('open', [file.parent.path]);
      }
    }
  }

  void _copyLogs(List<LogEntry> filteredLogs) {
    final text = filteredLogs.map((e) => e.toString()).join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已複製 ${filteredLogs.length} 條日誌至剪貼簿'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ListenableBuilder(
            listenable: LogService.instance,
            builder: (context, _) {
              final allLogs = LogService.instance.logs;
              final filtered = allLogs.where((entry) {
                if (_selectedLevel != null && entry.level != _selectedLevel) {
                  return false;
                }
                if (_filterQuery.isNotEmpty) {
                  final q = _filterQuery.toLowerCase();
                  final matchMsg = entry.message.toLowerCase().contains(q);
                  final matchTag = entry.tag.toLowerCase().contains(q);
                  final matchErr = entry.error?.toLowerCase().contains(q) ?? false;
                  return matchMsg || matchTag || matchErr;
                }
                return true;
              }).toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title and Quick Action Bar
                  Row(
                    children: [
                      const Icon(Icons.receipt_long_rounded, size: 28),
                      const SizedBox(width: 12),
                      Text(
                        '系統執行日誌 (System Logs)',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '共 ${filtered.length} / ${allLogs.length} 筆',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.note_outlined),
                        tooltip: '使用記事本開啟日誌檔',
                        onPressed: _openLogFile,
                      ),
                      IconButton(
                        icon: const Icon(Icons.folder_open_rounded),
                        tooltip: '開啟日誌所在資料夾',
                        onPressed: _openFolder,
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded),
                        tooltip: '複製顯示中之日誌',
                        onPressed: () => _copyLogs(filtered),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded),
                        tooltip: '清空日誌',
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('清空日誌'),
                              content: const Text('確定要清除所有日誌記錄嗎？此動作亦會重設日誌檔案。'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('確定清空')),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await LogService.instance.clear();
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Filter Row
                  Row(
                    children: [
                      // Search field
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: '搜尋關鍵字 (例如: 實力至上, 夏儂, 404, 預購...)',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            suffixIcon: _filterQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _filterQuery = '');
                                    },
                                  )
                                : null,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onChanged: (val) => setState(() => _filterQuery = val.trim()),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Level Filter Chips
                      FilterChip(
                        label: const Text('全部'),
                        selected: _selectedLevel == null,
                        onSelected: (_) => setState(() => _selectedLevel = null),
                      ),
                      const SizedBox(width: 6),
                      FilterChip(
                        avatar: const CircleAvatar(backgroundColor: Colors.redAccent, radius: 4),
                        label: const Text('ERROR'),
                        selected: _selectedLevel == LogLevel.error,
                        onSelected: (_) => setState(() => _selectedLevel = LogLevel.error),
                      ),
                      const SizedBox(width: 6),
                      FilterChip(
                        avatar: const CircleAvatar(backgroundColor: Colors.orangeAccent, radius: 4),
                        label: const Text('WARN'),
                        selected: _selectedLevel == LogLevel.warn,
                        onSelected: (_) => setState(() => _selectedLevel = LogLevel.warn),
                      ),
                      const SizedBox(width: 6),
                      FilterChip(
                        avatar: CircleAvatar(backgroundColor: Colors.blue.shade700, radius: 4),
                        label: const Text('INFO'),
                        selected: _selectedLevel == LogLevel.info,
                        onSelected: (_) => setState(() => _selectedLevel = LogLevel.info),
                      ),
                      const SizedBox(width: 6),
                      FilterChip(
                        avatar: CircleAvatar(backgroundColor: Colors.teal.shade700, radius: 4),
                        label: const Text('DEBUG'),
                        selected: _selectedLevel == LogLevel.debug,
                        onSelected: (_) => setState(() => _selectedLevel = LogLevel.debug),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Log List View
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF8F9FA),
                        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                _filterQuery.isEmpty ? '目前暫無日誌記錄' : '查無符合條件之日誌',
                                style: TextStyle(color: theme.hintColor),
                              ),
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              itemCount: filtered.length,
                              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                              itemBuilder: (context, idx) {
                                final entry = filtered[idx];
                                final lvlColor = _getLevelColor(entry.level, isDark);

                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 3),
                                  child: SelectableText.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: '[${entry.formattedTime}] ',
                                          style: TextStyle(
                                            fontFamily: 'Consolas',
                                            fontSize: 12,
                                            color: theme.hintColor,
                                          ),
                                        ),
                                        WidgetSpan(
                                          alignment: PlaceholderAlignment.middle,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                            margin: const EdgeInsets.only(right: 6),
                                            decoration: BoxDecoration(
                                              color: lvlColor.withValues(alpha: 0.18),
                                              border: Border.all(color: lvlColor, width: 0.8),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              entry.level.name.toUpperCase(),
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: lvlColor,
                                                fontFamily: 'Consolas',
                                              ),
                                            ),
                                          ),
                                        ),
                                        TextSpan(
                                          text: '[${entry.tag}] ',
                                          style: TextStyle(
                                            fontFamily: 'Consolas',
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: theme.colorScheme.primary,
                                          ),
                                        ),
                                        TextSpan(
                                          text: entry.message,
                                          style: TextStyle(
                                            fontFamily: 'Consolas',
                                            fontSize: 12,
                                            color: isDark ? Colors.white70 : Colors.black87,
                                          ),
                                        ),
                                        if (entry.error != null)
                                          TextSpan(
                                            text: '\n   錯誤: ${entry.error}',
                                            style: const TextStyle(
                                              fontFamily: 'Consolas',
                                              fontSize: 11,
                                              color: Colors.redAccent,
                                            ),
                                          ),
                                        if (entry.stackTrace != null)
                                          TextSpan(
                                            text: '\n${entry.stackTrace}',
                                            style: TextStyle(
                                              fontFamily: 'Consolas',
                                              fontSize: 10,
                                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
