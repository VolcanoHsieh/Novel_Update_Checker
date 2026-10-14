import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/app_config.dart';
import '../models/book_item.dart';
import '../services/cache_service.dart';
import '../services/scanner_service.dart';
import '../services/update_checker_service.dart';
import 'book_table.dart';
import 'format_dialog.dart';
import 'log_dialog.dart';
import 'stats_cards.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final CacheService _cacheService = CacheService();
  final ScannerService _scannerService = ScannerService();
  final UpdateCheckerService _checkerService = UpdateCheckerService();

  late AppConfig _config;
  bool _isLoading = true;
  bool _isScanning = false;
  bool _isChecking = false;

  List<BookItem> _allBooks = [];
  String _searchKeyword = '';
  String _activeFilter = 'all';

  String _statusText = '就緒';
  double? _progressValue;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    _config = await _cacheService.loadConfig();
    final cached = await _cacheService.loadCachedBooks();
    setState(() {
      _allBooks = cached.values.toList();
      _isLoading = false;
      _statusText = '已載入 ${_allBooks.length} 本書籍快取';
    });
  }

  Future<void> _pickFolder() async {
    final selectedDir = await FilePicker.getDirectoryPath(
      dialogTitle: '請選擇要掃描的小說根目錄',
      initialDirectory: _config.rootFolder.isNotEmpty ? _config.rootFolder : null,
    );

    if (selectedDir != null && selectedDir.isNotEmpty) {
      setState(() {
        _config.rootFolder = selectedDir;
      });
      await _cacheService.saveConfig(_config);
      await _startScan();
    }
  }

  Future<void> _startScan() async {
    if (_config.rootFolder.isEmpty) {
      _pickFolder();
      return;
    }

    setState(() {
      _isScanning = true;
      _statusText = '正在遞迴掃描目錄：${_config.rootFolder}...';
      _progressValue = null;
    });

    try {
      final scanned = await _scannerService.scanDirectory(
        _config.rootFolder,
        _config,
        onProgress: (path, count) {
          setState(() {
            _statusText = '掃描中 ($count 檔案)... $path';
          });
        },
      );

      // Merge with existing cache to preserve remote update data & manual edits
      final Map<String, BookItem> existingMap = {
        for (final b in _allBooks) (b.folderPath.isNotEmpty ? b.folderPath : b.title): b,
      };

      final List<BookItem> merged = [];
      for (final book in scanned) {
        final key = book.folderPath.isNotEmpty ? book.folderPath : book.title;
        final existing = existingMap[key];
        if (existing != null) {
          existing.localMaxVol = book.localMaxVol;
          existing.localVolumes = book.localVolumes;
          existing.localFilesCount = book.localFilesCount;
          existing.category = book.category;
          existing.cachedTwVol ??= book.localMaxVol;
          existing.refreshStatus();
          merged.add(existing);
        } else {
          book.cachedTwVol ??= book.localMaxVol;
          book.refreshStatus();
          merged.add(book);
        }
      }

      setState(() {
        _allBooks = merged;
        _isScanning = false;
        _statusText = '掃描完成！共找到 ${_allBooks.length} 部作品（點擊「檢查線上更新」開始比對）';
      });

      await _cacheService.saveCachedBooks(_allBooks);
    } catch (e) {
      setState(() {
        _isScanning = false;
        _statusText = '掃描失敗: $e';
      });
    }
  }

  Future<void> _startCheckUpdates({bool force = false}) async {
    if (_allBooks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先選擇目錄並掃描書籍！')),
      );
      return;
    }

    setState(() {
      _isChecking = true;
      _statusText = '正在準備查詢...';
      _progressValue = 0.0;
    });

    await _checkerService.checkAllBooks(
      _allBooks,
      _config,
      force: force,
      onProgress: (current, total, book) {
        setState(() {
          _statusText = '正在查詢 ($current / $total): ${book.title}...';
          _progressValue = total > 0 ? current / total : null;
        });
      },
      onFinished: () {
        setState(() {
          _isChecking = false;
          _progressValue = null;
          _statusText = '線上檢查完成！所有最新進度已快取至 JSON。';
        });
      },
    );
  }

  void _stopCheck() {
    _checkerService.cancel();
    setState(() {
      _isChecking = false;
      _progressValue = null;
      _statusText = '已手動停止查詢';
    });
  }

  Future<void> _checkSingleBook(BookItem book) async {
    setState(() {
      _statusText = '正在線上查詢：${book.title}...';
    });
    await _checkerService.checkSingleBook(book, _config, force: true);
    await _cacheService.saveCachedBooks(_allBooks);
    setState(() {
      _statusText = '已更新 ${book.title} 的進度資訊';
    });
  }

  List<BookItem> _getFilteredBooks() {
    return _allBooks.where((book) {
      // 1. Search keyword
      if (_searchKeyword.isNotEmpty) {
        final kw = _searchKeyword.toLowerCase();
        final matchTitle = book.title.toLowerCase().contains(kw);
        final matchJp = book.jpTitle?.toLowerCase().contains(kw) ?? false;
        final matchCat = book.category.toLowerCase().contains(kw);
        if (!matchTitle && !matchJp && !matchCat) return false;
      }

      // 2. Active filter (exact 6 tags)
      switch (_activeFilter) {
        case 'updates':
          return book.status == UpdateStatus.twUpdated ||
              book.status == UpdateStatus.jpUpdated ||
              book.status == UpdateStatus.bothUpdated;
        case 'tw':
          return book.status == UpdateStatus.twUpdated || book.status == UpdateStatus.bothUpdated;
        case 'jp':
          return book.status == UpdateStatus.jpUpdated || book.status == UpdateStatus.bothUpdated;
        case 'pending':
          return book.status == UpdateStatus.unknown;
        case 'notFound':
          return book.status == UpdateStatus.notFound || book.status == UpdateStatus.error;
        case 'all':
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final filtered = _getFilteredBooks();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset('assets/app_icon.jpg', width: 28, height: 28),
            ),
            const SizedBox(width: 12),
            const Text('文庫輕小說追更檢查器 (NovelUpdateChecker)'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: '系統日誌 (Log Viewer)',
            onPressed: () => LogDialog.show(context),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '格式規則與查詢設定',
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => FormatDialog(
                  config: _config,
                  onSave: (newCfg) async {
                    setState(() => _config = newCfg);
                    await _cacheService.saveConfig(_config);
                  },
                  onClearCache: () {
                    setState(() {
                      _allBooks.clear();
                      _statusText = '已清空快取';
                    });
                    if (_config.rootFolder.isNotEmpty) {
                      _startScan();
                    }
                  },
                ),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // 1. Top action bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.folder_special, size: 20, color: Colors.blueGrey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _config.rootFolder.isNotEmpty ? _config.rootFolder : '尚未選擇掃描目錄',
                            style: TextStyle(
                              color: _config.rootFolder.isNotEmpty ? null : Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.folder_open),
                  label: const Text('選擇資料夾'),
                  onPressed: _pickFolder,
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: _isScanning
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.refresh),
                  label: Text(_isScanning ? '掃描中...' : '掃描書籍'),
                  onPressed: (_isScanning || _isChecking) ? null : _startScan,
                ),
                const SizedBox(width: 8),
                if (_isChecking)
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.stop, color: Colors.red),
                    label: const Text('停止查詢'),
                    onPressed: _stopCheck,
                  )
                else
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.radar),
                    label: const Text('檢查線上更新'),
                    onPressed: _isScanning ? null : () => _startCheckUpdates(),
                  ),
              ],
            ),
          ),

          // 2. Stats cards (6 tags requested by user)
          StatsCards(
            books: _allBooks,
            activeFilter: _activeFilter,
            onFilterSelected: (filter) => setState(() => _activeFilter = filter),
          ),

          // 3. Search Bar and Filter Chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: '搜尋書名、日文原名或分類...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      suffixIcon: _searchKeyword.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () => setState(() => _searchKeyword = ''),
                            )
                          : null,
                    ),
                    onChanged: (val) => setState(() => _searchKeyword = val.trim()),
                  ),
                ),
                const SizedBox(width: 12),
                // 6 Exact Filter Chips
                Wrap(
                  spacing: 6,
                  children: [
                    FilterChip(
                      label: const Text('全部'),
                      selected: _activeFilter == 'all',
                      onSelected: (_) => setState(() => _activeFilter = 'all'),
                    ),
                    FilterChip(
                      label: const Text('有更新'),
                      selected: _activeFilter == 'updates',
                      selectedColor: Colors.purple.withValues(alpha: 0.2),
                      onSelected: (_) => setState(() => _activeFilter = 'updates'),
                    ),
                    FilterChip(
                      label: const Text('台版有更新'),
                      selected: _activeFilter == 'tw',
                      selectedColor: Colors.redAccent.withValues(alpha: 0.2),
                      onSelected: (_) => setState(() => _activeFilter = 'tw'),
                    ),
                    FilterChip(
                      label: const Text('日版有更新'),
                      selected: _activeFilter == 'jp',
                      selectedColor: Colors.amber.withValues(alpha: 0.2),
                      onSelected: (_) => setState(() => _activeFilter = 'jp'),
                    ),
                    FilterChip(
                      label: const Text('待確認'),
                      selected: _activeFilter == 'pending',
                      selectedColor: Colors.indigo.withValues(alpha: 0.2),
                      onSelected: (_) => setState(() => _activeFilter = 'pending'),
                    ),
                    FilterChip(
                      label: const Text('查無資料'),
                      selected: _activeFilter == 'notFound',
                      selectedColor: Colors.grey.withValues(alpha: 0.2),
                      onSelected: (_) => setState(() => _activeFilter = 'notFound'),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Text('顯示 ${filtered.length} / ${_allBooks.length} 部', style: const TextStyle(fontSize: 13, color: Colors.grey)),
              ],
            ),
          ),

          // 4. Main Table
          Expanded(
            child: BookTable(
              books: filtered,
              onBookUpdated: (updated) async {
                await _cacheService.saveCachedBooks(_allBooks);
                setState(() {});
              },
              onSingleCheck: _checkSingleBook,
            ),
          ),

          // 5. Bottom Status Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
            ),
            child: Row(
              children: [
                if (_progressValue != null) ...[
                  SizedBox(
                    width: 140,
                    child: LinearProgressIndicator(value: _progressValue),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    _statusText,
                    style: const TextStyle(fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Text(
                  '快取：純 JSON (cache.json)',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
