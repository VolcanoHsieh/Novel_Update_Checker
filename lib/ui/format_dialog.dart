import 'dart:io';
import 'package:flutter/material.dart';
import '../models/app_config.dart';
import '../models/book_item.dart';
import '../services/cache_service.dart';
import '../services/scanner_service.dart';

class FormatDialog extends StatefulWidget {
  final AppConfig config;
  final ValueChanged<AppConfig> onSave;
  final VoidCallback? onClearCache;

  const FormatDialog({
    super.key,
    required this.config,
    required this.onSave,
    this.onClearCache,
  });

  @override
  State<FormatDialog> createState() => _FormatDialogState();
}

class _FormatDialogState extends State<FormatDialog> {
  late TextEditingController _patternCtrl;
  late TextEditingController _regexCtrl;
  late TextEditingController _testSampleCtrl;
  late bool _useRegex;
  late bool _checkTw;
  late bool _checkJp;
  late double _delayMs;
  late double _expireDays;

  double _previewVol = 0.0;
  String _previewTitle = '';

  @override
  void initState() {
    super.initState();
    _patternCtrl = TextEditingController(text: widget.config.customPattern);
    _regexCtrl = TextEditingController(text: widget.config.customRegex);
    _testSampleCtrl = TextEditingController(text: '[-01-] 轉生公主與天才千金的魔法革命.epub');
    _useRegex = widget.config.useRegex;
    _checkTw = widget.config.checkTw;
    _checkJp = widget.config.checkJp;
    _delayMs = widget.config.requestDelayMs.toDouble();
    _expireDays = widget.config.cacheExpireDays.toDouble();

    _updatePreview();
  }

  void _updatePreview() {
    final tempConfig = AppConfig(
      customPattern: _patternCtrl.text.trim(),
      useRegex: _useRegex,
      customRegex: _regexCtrl.text.trim(),
    );
    final reg = tempConfig.compilePatternRegex();
    final (vol, title, isExtra) = ScannerService.parseVolumeAndTitle(_testSampleCtrl.text.trim(), reg);
    setState(() {
      _previewVol = vol;
      _previewTitle = title;
    });
  }

  @override
  void dispose() {
    _patternCtrl.dispose();
    _regexCtrl.dispose();
    _testSampleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.tune, color: Colors.blueAccent),
          SizedBox(width: 8),
          Text('檔案格式與查詢設定'),
        ],
      ),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '檔名辨識規則',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Radio<bool>(
                    value: false,
                    groupValue: _useRegex,
                    onChanged: (val) {
                      setState(() => _useRegex = val!);
                      _updatePreview();
                    },
                  ),
                  const Text('範本格式標籤 (推薦)'),
                  const SizedBox(width: 20),
                  Radio<bool>(
                    value: true,
                    groupValue: _useRegex,
                    onChanged: (val) {
                      setState(() => _useRegex = val!);
                      _updatePreview();
                    },
                  ),
                  const Text('進階自訂正規表達式 (Regex)'),
                ],
              ),
              const SizedBox(height: 6),
              if (!_useRegex) ...[
                TextField(
                  controller: _patternCtrl,
                  decoration: const InputDecoration(
                    labelText: '範本格式',
                    hintText: '例如：[-{vol}-] {title}',
                    helperText: '支援標籤：{vol} (卷數，可相容 01 或 01-05), {title} (書名)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _updatePreview(),
                ),
              ] else ...[
                TextField(
                  controller: _regexCtrl,
                  decoration: const InputDecoration(
                    labelText: '正規表達式 (Regex)',
                    hintText: r'\[-(\d+)(?:-(\d+))?-\]\s*(.*)',
                    helperText: '捕獲組 1: 起始卷數, 捕獲組 2: 結束卷數 (選填), 捕獲組 3: 書名',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _updatePreview(),
                ),
              ],
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                '即時測試與預覽',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _testSampleCtrl,
                decoration: const InputDecoration(
                  labelText: '測試用檔案名稱',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.science_outlined),
                ),
                onChanged: (_) => _updatePreview(),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '解析結果：卷數 = 第 ${BookItem.formatVol(_previewVol)} 卷 | 書名 = "${_previewTitle.isNotEmpty ? _previewTitle : '(使用資料夾名稱)'}"',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                '爬蟲查詢選項',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  Checkbox(
                    value: _checkTw,
                    onChanged: (val) => setState(() => _checkTw = val ?? true),
                  ),
                  const Text('檢查台灣版 (BookWalker TW)'),
                  const SizedBox(width: 20),
                  Checkbox(
                    value: _checkJp,
                    onChanged: (val) => setState(() => _checkJp = val ?? true),
                  ),
                  const Text('檢查日本版 (BookWalker JP)'),
                ],
              ),
              const SizedBox(height: 8),
              Text('查詢請求間隔：${_delayMs.toInt()} 毫秒 (避免被目標網站封鎖 IP)'),
              Slider(
                value: _delayMs,
                min: 300,
                max: 3000,
                divisions: 27,
                label: '${_delayMs.toInt()} ms',
                onChanged: (val) => setState(() => _delayMs = val),
              ),
              Text('本地快取過期天數：${_expireDays.toInt()} 天 (過期後才會重新連網查詢)'),
              Slider(
                value: _expireDays,
                min: 1,
                max: 30,
                divisions: 29,
                label: '${_expireDays.toInt()} 天',
                onChanged: (val) => setState(() => _expireDays = val),
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                '快取資料管理',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('開啟快取資料夾'),
                    onPressed: () async {
                      final dir = await CacheService().dataDirectory;
                      if (Platform.isWindows) {
                        Process.run('explorer.exe', [dir.path]);
                      }
                    },
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('清空所有快取'),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('確認清空快取？'),
                          content: const Text('清空快取後，所有書籍的線上進度與手動校對紀錄將被清除，下次將重新查詢網路。'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: Colors.red),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('確認清空'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await CacheService().clearCache();
                        widget.onClearCache?.call();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已成功清空快取檔案！')),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final newConfig = AppConfig(
              rootFolder: widget.config.rootFolder,
              customPattern: _patternCtrl.text.trim(),
              useRegex: _useRegex,
              customRegex: _regexCtrl.text.trim(),
              checkTw: _checkTw,
              checkJp: _checkJp,
              requestDelayMs: _delayMs.toInt(),
              cacheExpireDays: _expireDays.toInt(),
            );
            widget.onSave(newConfig);
            Navigator.of(context).pop();
          },
          child: const Text('儲存設定'),
        ),
      ],
    );
  }
}
