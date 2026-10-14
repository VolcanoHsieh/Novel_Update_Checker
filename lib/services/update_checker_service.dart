import 'dart:async';
import '../models/app_config.dart';
import '../models/book_item.dart';
import 'bangumi_service.dart';
import 'bookwalker_service.dart';
import 'cache_service.dart';
import 'log_service.dart';

class UpdateCheckerService {
  final BangumiService bangumiService;
  final BookWalkerService bookWalkerService;
  final CacheService cacheService;

  bool _isCancelled = false;
  bool _isRunning = false;

  bool get isRunning => _isRunning;

  UpdateCheckerService({
    BangumiService? bangumiService,
    BookWalkerService? bookWalkerService,
    CacheService? cacheService,
  })  : bangumiService = bangumiService ?? BangumiService(),
        bookWalkerService = bookWalkerService ?? BookWalkerService(),
        cacheService = cacheService ?? CacheService();

  void cancel() {
    _isCancelled = true;
  }

  /// Check a single book item
  Future<void> checkSingleBook(BookItem book, AppConfig config, {bool force = false}) async {
    book.status = UpdateStatus.checking;
    book.statusMessage = '正在查詢中...';
    LogService.instance.info('Checker', '開始查詢 [${book.title}] (本地最大卷: ${book.localMaxVol})');

    try {
      BangumiSubject? bgmSubject;

      // 1. Wikipedia & Bangumi check for Japanese title mapping
      // If user has manualOverride, or already has a valid jpTitle, NEVER overwrite it during update check!
      final needsJpTitle = (book.jpTitle == null || book.jpTitle!.isEmpty);

      if (needsJpTitle) {
        bgmSubject = await bangumiService.searchNovel(book.title);
        if (bgmSubject != null) {
          book.jpTitle = bgmSubject.name;
          if (bgmSubject.id > 0) {
            book.bangumiId = bgmSubject.id;
          }
          LogService.instance.info('Checker', '[${book.title}] 取得日文書名: ${book.jpTitle}');
        }
      }

      // 2. BookWalker Taiwan
      if (config.checkTw) {
        final twResult = await bookWalkerService.searchTaiwan(book.title, targetUrl: book.twUrl);
        if (twResult != null) {
          book.twLatestVol = twResult.latestVol;
          book.twLatestTitle = twResult.title;
          book.twUrl = twResult.url;
        }
      }

      // 3. BookWalker Japan & Multi-source Fallbacks
      if (config.checkJp) {
        final queryJp = (book.jpTitle != null && book.jpTitle!.isNotEmpty)
            ? book.jpTitle!
            : book.title;

        // Source 1: BookWalker Japan
        final jpResult = await bookWalkerService.searchJapan(queryJp, targetUrl: book.jpUrl);
        if (jpResult != null && jpResult.latestVol > 0) {
          book.jpLatestVol = jpResult.latestVol;
          book.jpLatestTitle = jpResult.title;
          book.jpUrl = jpResult.url;
        } else {
          // Source 2: Japanese Wikipedia Volume
          final wikiResult = await bookWalkerService.fetchJaWikipediaVolume(queryJp);
          if (wikiResult != null && wikiResult.latestVol > 0) {
            book.jpLatestVol = wikiResult.latestVol;
            book.jpLatestTitle = wikiResult.title;
            book.jpUrl = wikiResult.url;
          } else if (bgmSubject != null && bgmSubject.volsCount != null && bgmSubject.volsCount! > 0) {
            // Source 3: Bangumi (if novel volsCount exists)
            book.jpLatestVol = bgmSubject.volsCount!.toDouble();
          }
        }
      }

      book.lastChecked = DateTime.now();
      book.refreshStatus();
      LogService.instance.info('Checker', '[${book.title}] 查詢完成: 狀態=${book.statusMessage ?? book.status.name}, 台版最新=${book.twLatestVol}, 日版最新=${book.jpLatestVol}');
    } catch (e, stack) {
      book.status = UpdateStatus.error;
      book.statusMessage = '查詢發生錯誤: $e';
      LogService.instance.error('Checker', '[${book.title}] 查詢發生錯誤: $e', error: e, stackTrace: stack);
    }
  }

  /// Batch check all books in queue
  Future<void> checkAllBooks(
    List<BookItem> books,
    AppConfig config, {
    bool force = false,
    void Function(int current, int total, BookItem book)? onProgress,
    void Function()? onFinished,
  }) async {
    if (_isRunning) return;
    _isRunning = true;
    _isCancelled = false;

    final targetBooks = books.where((b) {
      if (b.isIgnored) return false;
      if (force) return true;
      if (b.lastChecked == null) return true;
      final diffDays = DateTime.now().difference(b.lastChecked!).inDays;
      return diffDays >= config.cacheExpireDays;
    }).toList();

    int completed = 0;
    final total = targetBooks.length;
    LogService.instance.info('Checker', '開始批次檢查更新: 共 $total 本書籍待檢查');

    for (final book in targetBooks) {
      if (_isCancelled) {
        LogService.instance.warn('Checker', '使用者取消了更新檢查');
        break;
      }

      onProgress?.call(completed + 1, total, book);
      await checkSingleBook(book, config, force: force);
      completed++;

      // Save cache every 5 books
      if (completed % 5 == 0) {
        await cacheService.saveCachedBooks(books);
      }

      if (_isCancelled) {
        LogService.instance.warn('Checker', '使用者取消了更新檢查');
        break;
      }

      // Rate limit delay
      if (config.requestDelayMs > 0) {
        await Future.delayed(Duration(milliseconds: config.requestDelayMs));
      }
    }

    // Final save
    await cacheService.saveCachedBooks(books);

    _isRunning = false;
    _isCancelled = false;
    LogService.instance.info('Checker', '批次更新檢查全部完成 (已檢查 $completed / $total)');
    onFinished?.call();
  }
}
