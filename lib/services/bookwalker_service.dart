import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'log_service.dart';

class RemoteBookResult {
  final double latestVol;
  final String title;
  final String url;
  final String? publishDate;

  RemoteBookResult({
    required this.latestVol,
    required this.title,
    required this.url,
    this.publishDate,
  });
}

class BookWalkerService {
  final Dio _dio;

  BookWalkerService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                'Accept':
                    'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
                'Accept-Language': 'zh-TW,zh;q=0.9,en-US;q=0.8,en;q=0.7,ja;q=0.6',
                'Referer': 'https://www.bookwalker.com.tw/',
              },
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 12),
            ));

  /// Convert Japanese full-width numbers to standard ASCII numbers
  static String normalizeFullWidth(String text) {
    const fullWidth = '０１２３４５６７８９';
    const halfWidth = '0123456789';
    var res = text;
    for (int i = 0; i < fullWidth.length; i++) {
      res = res.replaceAll(fullWidth[i], halfWidth[i]);
    }
    return res;
  }

  /// Clean BookWalker URLs: Convert tracking / SSO redirect links to direct canonical URLs
  static String cleanUrl(String rawUrl) {
    if (rawUrl.isEmpty) return rawUrl;
    try {
      final uri = Uri.parse(rawUrl);
      if (uri.host.contains('member.bookwalker.jp')) {
        final r = uri.queryParameters['r'];
        if (r != null && r.isNotEmpty) {
          var path = Uri.decodeComponent(r);
          if (path.contains(':CHECK:')) {
            path = path.split(':CHECK:').first;
          }
          if (!path.startsWith('/')) {
            path = '/$path';
          }
          return 'https://bookwalker.jp$path';
        }
      }
    } catch (_) {}
    return rawUrl.startsWith('http') ? rawUrl : 'https://bookwalker.jp$rawUrl';
  }

  /// Check if an item is a site guide, banner, or irrelevant promotional item
  static bool isIrrelevantItem(String title, String url) {
    final lowerTitle = title.toLowerCase();
    final lowerUrl = url.toLowerCase();

    // Check URL patterns that are NOT book details or series
    if (lowerUrl.contains('serviceguide') ||
        lowerUrl.contains('/feature/') ||
        lowerUrl.contains('/select/') ||
        lowerUrl.contains('/campaign/') ||
        lowerUrl.contains('/special/') ||
        lowerUrl.contains('/company/') ||
        lowerUrl.contains('/help/') ||
        lowerUrl.contains('/tag/')) {
      return true;
    }

    if (lowerTitle.contains('使いこなしガイド') ||
        lowerTitle.contains('便利なサービス') ||
        lowerTitle.contains('35選') ||
        lowerTitle.contains('サービスガイド') ||
        lowerTitle.contains('キャンペーン') ||
        lowerTitle.contains('購入特典') ||
        lowerTitle.contains('アンソロジー') ||
        lowerTitle.contains('単話') ||
        lowerTitle.contains('分冊版') ||
        lowerTitle.contains('特集') ||
        lowerTitle.contains('メディア化') ||
        lowerTitle.contains('フェア') ||
        lowerTitle.contains('おすすめ') ||
        lowerTitle.contains('試し読み') ||
        lowerTitle.contains('セール')) {
      return true;
    }

    return false;
  }

  /// Check if title indicates comic/manga rather than novel
  static bool isComicItem(String title) {
    final lower = title.toLowerCase();
    return lower.contains('（漫畫）') ||
        lower.contains('(漫畫)') ||
        lower.contains('【漫畫】') ||
        lower.contains('漫畫版') ||
        lower.contains('漫画') ||
        lower.contains('コミック') ||
        lower.contains('コミックス') ||
        lower.contains('comic');
  }

  /// Check if an item is a pre-order / reservation (預購 / 予約) rather than published
  static bool isPreorderItem(String title, {String label = '', String text = ''}) {
    final lowerTitle = title.toLowerCase();
    final lowerLabel = label.toLowerCase();
    final lowerText = text.toLowerCase();

    // Title markers for pre-orders
    if (lowerTitle.contains('【預購】') ||
        lowerTitle.contains('[預購]') ||
        lowerTitle.contains('(預購)') ||
        lowerTitle.contains('（預購）') ||
        lowerTitle.contains('【預約】') ||
        lowerTitle.contains('[預約]') ||
        lowerTitle.contains('(預約)') ||
        lowerTitle.contains('（預約）') ||
        lowerTitle.contains('【予約】') ||
        lowerTitle.contains('[予約]') ||
        lowerTitle.contains('(予約)') ||
        lowerTitle.contains('（予約）') ||
        lowerTitle.contains('予約受付中') ||
        lowerTitle.contains('預購商品')) {
      return true;
    }

    // Label or badge markers
    if (lowerLabel.contains('予約') ||
        lowerLabel.contains('預購') ||
        lowerLabel.contains('預約') ||
        lowerLabel.contains('配信予定') ||
        lowerLabel.contains('即將上市') ||
        lowerLabel.contains('即將出版')) {
      return true;
    }

    // Card content markers
    if (lowerText.contains('予約受付') ||
        lowerText.contains('予約する') ||
        lowerText.contains('預購中') ||
        lowerText.contains('配信予定日') ||
        lowerText.contains('尚未上市')) {
      return true;
    }

    return false;
  }

  /// Search BookWalker Taiwan for latest volume of light novel
  Future<RemoteBookResult?> searchTaiwan(String title, {String? targetUrl}) async {
    final cleanTitle = _cleanTitle(title);

    // 1. If targetUrl is explicitly provided (e.g. series URL or product URL)
    if (targetUrl != null && targetUrl.trim().isNotEmpty) {
      final trimmedUrl = targetUrl.trim();
      try {
        if (trimmedUrl.contains('/product/')) {
          final res = await _dio.get(trimmedUrl);
          if (res.statusCode == 200 && res.data != null) {
            final doc = html_parser.parse(res.data);
            final ogTitle = doc.querySelector('meta[property="og:title"]')?.attributes['content'] ??
                doc.querySelector('h1, .book-title, title')?.text.trim() ?? '';
            final pTitle = ogTitle.split('線上看').first.trim();
            final vol = _extractVolume(pTitle, baseTitle: cleanTitle);
            return RemoteBookResult(
              latestVol: vol > 0.0 ? vol : 1.0,
              title: pTitle.isNotEmpty ? pTitle : cleanTitle,
              url: trimmedUrl,
            );
          }
        } else if (trimmedUrl.contains('series=') || trimmedUrl.contains('/search')) {
          final res = await _dio.get(trimmedUrl);
          if (res.statusCode == 200 && res.data != null) {
            final parsed = _parseTaiwanBookList(
              res.data,
              cleanTitle,
              defaultUrl: trimmedUrl,
              isSeriesUrl: trimmedUrl.contains('series='),
            );
            if (parsed != null) return parsed;
          }
        }
      } catch (_) {
        // Fall back to keyword search on error
      }
    }

    if (cleanTitle.isEmpty) return null;

    // 2. Keyword search on BookWalker Taiwan
    try {
      final response = await _dio.get(
        'https://www.bookwalker.com.tw/search',
        queryParameters: {
          'w': cleanTitle,
          'order': 'sell_date', // Most recent release first
        },
      );

      if (response.statusCode != 200 || response.data == null) {
        return null;
      }

      return _parseTaiwanBookList(response.data, cleanTitle);
    } catch (_) {
      // Ignore network errors
    }
    return null;
  }

  RemoteBookResult? _parseTaiwanBookList(
    dynamic responseData,
    String cleanTitle, {
    String? defaultUrl,
    bool isSeriesUrl = false,
  }) {
    final doc = html_parser.parse(responseData);
    final bookBoxes = doc.querySelectorAll('.bookbox, .bookitem, .bookinfo, li.item, div[class*="book"]');

    double maxVol = 0.0;
    String bestTitle = '';
    String bestUrl = '';
    int matchedCount = 0;
    String firstMatchedTitle = '';
    String firstMatchedUrl = '';

    final matchKey = cleanTitle.length > 3 ? cleanTitle.substring(0, 3) : cleanTitle;

    // First pass: inspect structured book items
    for (final box in bookBoxes) {
      final catLabel = box.querySelector('.cat-label, .category, .tag, .lablename')?.text.trim() ?? '';
      // Strictly reject if marked as comic
      if (catLabel.contains('漫畫') || catLabel.contains('漫画')) {
        continue;
      }

      final a = box.querySelector('a.gtag-click, h2.bookname a, h4.bookname a, .bookname a, a[title]') ??
          box.querySelector('a');
      final itemTitle = a?.attributes['title'] ??
          box.querySelector('.bookname')?.text.trim() ??
          box.querySelector('img')?.attributes['alt'] ??
          a?.text.trim() ??
          '';
      var href = a?.attributes['href'] ?? '';

      if (itemTitle.isEmpty || href.isEmpty || href == '#') continue;
      if (isIrrelevantItem(itemTitle, href) || isComicItem(itemTitle)) continue;

      if (isPreorderItem(itemTitle, label: catLabel, text: box.text)) {
        LogService.instance.info('BookWalker TW', '[$cleanTitle] 排除預購商品: $itemTitle');
        continue;
      }

      if (href.startsWith('/')) {
        href = 'https://www.bookwalker.com.tw$href';
      }

      // Check title relevance (if not on an explicit series page)
      if (!isSeriesUrl && matchKey.isNotEmpty && !itemTitle.contains(matchKey)) {
        continue;
      }

      matchedCount++;
      if (firstMatchedTitle.isEmpty) {
        firstMatchedTitle = itemTitle;
        firstMatchedUrl = href;
      }

      final vol = _extractVolume(itemTitle, baseTitle: cleanTitle);
      if (vol > maxVol) {
        maxVol = vol;
        bestTitle = itemTitle;
        bestUrl = href;
      }
    }

    // Fallback pass: all title links if structured parse yielded nothing
    if (matchedCount == 0 && !isSeriesUrl) {
      final links = doc.querySelectorAll('a[title]');
      for (final a in links) {
        final itemTitle = a.attributes['title'] ?? '';
        var href = a.attributes['href'] ?? '';

        if (itemTitle.isEmpty || href.isEmpty || href == '#') continue;
        if (isIrrelevantItem(itemTitle, href) || isComicItem(itemTitle)) continue;

        if (isPreorderItem(itemTitle, text: a.text)) {
          LogService.instance.info('BookWalker TW', '[$cleanTitle] 排除預購商品: $itemTitle');
          continue;
        }

        if (matchKey.isNotEmpty && !itemTitle.contains(matchKey)) continue;

        if (href.startsWith('/')) {
          href = 'https://www.bookwalker.com.tw$href';
        }

        matchedCount++;
        if (firstMatchedTitle.isEmpty) {
          firstMatchedTitle = itemTitle;
          firstMatchedUrl = href;
        }

        final vol = _extractVolume(itemTitle, baseTitle: cleanTitle);
        if (vol > maxVol) {
          maxVol = vol;
          bestTitle = itemTitle;
          bestUrl = href;
        }
      }
    }

    // Crucial: Single-volume novel handling (本系列僅有一冊)
    if (maxVol == 0.0 && matchedCount > 0) {
      maxVol = (matchedCount == 1) ? 1.0 : matchedCount.toDouble();
      bestTitle = bestTitle.isNotEmpty ? bestTitle : firstMatchedTitle;
      bestUrl = bestUrl.isNotEmpty ? bestUrl : firstMatchedUrl;
    }

    if (maxVol > 0.0) {
      LogService.instance.debug('BookWalker TW', '[$cleanTitle] 解析成功: 最新卷數=$maxVol, 標題=$bestTitle');
      return RemoteBookResult(
        latestVol: maxVol,
        title: bestTitle.isNotEmpty ? bestTitle : cleanTitle,
        url: bestUrl.isNotEmpty ? bestUrl : (defaultUrl ?? ''),
      );
    }
    return null;
  }

  static int romanToInt(String roman) {
    const romanMap = {
      'I': 1, 'II': 2, 'III': 3, 'IV': 4, 'V': 5,
      'VI': 6, 'VII': 7, 'VIII': 8, 'IX': 9, 'X': 10,
      'XI': 11, 'XII': 12, 'XIII': 13, 'XIV': 14, 'XV': 15,
      'XVI': 16, 'XVII': 17, 'XVIII': 18, 'XIX': 19, 'XX': 20,
      'XXI': 21, 'XXII': 22, 'XXIII': 23, 'XXIV': 24, 'XXV': 25,
      'XXVI': 26, 'XXVII': 27, 'XXVIII': 28, 'XXIX': 29, 'XXX': 30,
    };
    return romanMap[roman.toUpperCase()] ?? 0;
  }

  /// Search BookWalker Japan for latest volume of light novel
  Future<RemoteBookResult?> searchJapan(String jpTitle, {String? targetUrl}) async {
    final cleanTitle = _cleanTitle(jpTitle);
    if (cleanTitle.isEmpty) return null;

    // 1. If targetUrl is explicitly provided (e.g. series URL or detail page)
    if (targetUrl != null && targetUrl.trim().isNotEmpty) {
      final direct = cleanUrl(targetUrl.trim());
      try {
        if (direct.contains('/series/')) {
          final res = await _parseJapanSeriesPage(direct, cleanTitle);
          if (res != null) return res;
        } else if (direct.contains('/de')) {
          final res = await _dio.get(direct);
          if (res.statusCode == 200 && res.data != null) {
            final doc = html_parser.parse(res.data);
            final title = normalizeFullWidth(
              doc.querySelector('h1, .p-main__title, meta[property="og:title"]')?.text.trim() ??
                  doc.querySelector('meta[property="og:title"]')?.attributes['content'] ??
                  cleanTitle,
            );
            final vol = _extractVolume(title, baseTitle: cleanTitle);
            return RemoteBookResult(
              latestVol: vol > 0.0 ? vol : 1.0,
              title: title.isNotEmpty ? title : cleanTitle,
              url: direct,
            );
          }
        }
      } catch (_) {
        // Fall back to keyword search
      }
    }

    // 2. Try with genre=2 (Light Novel)
    var result = await _executeJapanSearch(cleanTitle, genre: '2');
    if (result != null) return result;

    // 3. Try without genre filter (for Shinbungei / Tankobon like GA Novel, Kadokawa Books)
    result = await _executeJapanSearch(cleanTitle);
    if (result != null) return result;

    // 4. Fallback: Try with root title (strip subtitle like 〜, ～, :, -)
    final rootTitle = cleanTitle.split(RegExp(r'[〜～:：―\-]')).first.trim();
    if (rootTitle.isNotEmpty && rootTitle != cleanTitle && rootTitle.length >= 2) {
      result = await _executeJapanSearch(rootTitle, genre: '2');
      if (result != null) return result;

      result = await _executeJapanSearch(rootTitle);
      if (result != null) return result;
    }

    // 5. Fallback: Check Japanese Wikipedia if BookWalker has no volume data
    return await fetchJaWikipediaVolume(cleanTitle);
  }

  /// Fetch volume count from Japanese Wikipedia if BookWalker has no results
  Future<RemoteBookResult?> fetchJaWikipediaVolume(String jpTitle) async {
    try {
      final res = await _dio.get('https://ja.wikipedia.org/w/api.php', queryParameters: {
        'action': 'query',
        'prop': 'revisions',
        'titles': jpTitle,
        'rvprop': 'content',
        'rvslots': 'main',
        'format': 'json',
      });
      final pages = res.data['query']?['pages'] as Map<String, dynamic>?;
      if (pages != null && !pages.containsKey('-1')) {
        final p = pages.values.first;
        final content = p['revisions']?[0]?['slots']?['main']?['*'] as String? ?? '';
        final m1 = RegExp(r'(?:巻数|卷数)\s*=\s*(?:既刊)?\s*(\d+(?:\.\d+)?)巻?').firstMatch(content);
        final m2 = RegExp(r'既刊(\d+(?:\.\d+)?)巻').firstMatch(content);
        double vol = double.tryParse(m1?.group(1) ?? '') ?? double.tryParse(m2?.group(1) ?? '') ?? 0.0;
        if (vol > 0.0) {
          return RemoteBookResult(
            latestVol: vol,
            title: jpTitle,
            url: 'https://ja.wikipedia.org/wiki/${Uri.encodeComponent(jpTitle)}',
          );
        }
      }
    } catch (_) {}
    return null;
  }

  Future<RemoteBookResult?> _executeJapanSearch(String cleanTitle, {String? genre}) async {
    try {
      final queryParams = <String, String>{
        'word': cleanTitle,
        'order': 'rank',
      };
      if (genre != null) {
        queryParams['genre'] = genre;
      }

      final response = await _dio.get(
        'https://bookwalker.jp/search/',
        queryParameters: queryParams,
      );

      if (response.statusCode != 200 || response.data == null) {
        return null;
      }

      final doc = html_parser.parse(response.data);
      String? seriesUrl;
      int seriesCardCount = 0;
      // Strictly query only book card containers, never bare li!
      final items = doc.querySelectorAll('.m-book-item, li.o-mod-list__item');

      for (final item in items) {
        final img = item.querySelector('img');
        final alt = img?.attributes['alt'] ?? '';
        final titleA = item.querySelector('p.m-book-item__title a, a.m-book-item__title, a.m-thumb__image, .m-book-item__title a') ??
            item.querySelector('a:not(.m-thumb__check)');
        final rawHref = titleA?.attributes['href'] ?? '';
        final label = item.querySelector('.m-book-item__label')?.text.trim() ?? '';

        if (isIrrelevantItem(alt, rawHref) || isComicItem(alt) || label.contains('コミック')) {
          continue;
        }

        if (isPreorderItem(alt, label: label, text: item.text)) {
          LogService.instance.info('BookWalker JP', '[$cleanTitle] 排除預購系列/書籍: $alt');
          continue;
        }

        final directHref = cleanUrl(rawHref);

        // Check if this link points to a series list
        if (directHref.contains('/series/') && alt.isNotEmpty) {
          final normAlt = normalizeFullWidth(alt).replaceAll(RegExp(r'[―—–ー−\-]'), '-');
          final normClean = normalizeFullWidth(cleanTitle).replaceAll(RegExp(r'[―—–ー−\-]'), '-');
          final matchKey = normClean.length > 3 ? normClean.substring(0, 3) : normClean;

          if (normAlt.contains(matchKey) || normClean.contains(normAlt.split('(').first.split('（').first.trim())) {
            final isNovel = alt.contains('文庫') ||
                alt.contains('ノベル') ||
                alt.contains('books') ||
                alt.contains('BOOKS') ||
                alt.contains('ＢＯＯＫＳ') ||
                alt.contains('ラノベ');

            final countStr = item.querySelector('.m-book-item__series .ico-txt')?.text.trim() ?? '';
            final countMatch = RegExp(r'(\d+)冊').firstMatch(countStr);
            final count = countMatch != null ? int.parse(countMatch.group(1)!) : 0;

            if (isNovel || seriesUrl == null) {
              seriesUrl = directHref;
              seriesCardCount = count;
              if (isNovel) break;
            }
          }
        }
      }

      // If series list found, parse all volumes from series list page
      if (seriesUrl != null) {
        final seriesRes = await _parseJapanSeriesPage(seriesUrl, cleanTitle, seriesCardCount: seriesCardCount);
        if (seriesRes != null) return seriesRes;
      }

      // Fallback: parse search results directly
      double maxVol = 0.0;
      String bestTitle = '';
      String bestUrl = '';
      int matchedCount = 0;
      String firstMatchedTitle = '';
      String firstMatchedUrl = '';

      for (final item in items) {
        final img = item.querySelector('img');
        final title = normalizeFullWidth(img?.attributes['alt'] ?? '');
        final a = item.querySelector('p.m-book-item__title a, a.m-book-item__title, a.m-thumb__image, .m-book-item__title a') ??
            item.querySelector('a:not(.m-thumb__check)');
        final rawHref = a?.attributes['href'] ?? '';

        if (title.isEmpty || isIrrelevantItem(title, rawHref) || isComicItem(title)) {
          continue;
        }

        final label = item.querySelector('.m-book-item__label, .m-thumb__label-area, .m-book-item__status-tag')?.text.trim() ?? '';
        if (isPreorderItem(title, label: label, text: item.text)) {
          LogService.instance.info('BookWalker JP', '[$cleanTitle] 排除預購商品: $title');
          continue;
        }

        final directHref = cleanUrl(rawHref);
        // Only accept actual book detail links or series links
        if (!directHref.contains('/de') && !directHref.contains('/series/')) {
          continue;
        }

        final normTitle = normalizeFullWidth(title).replaceAll(RegExp(r'[―—–ー−\-]'), '-');
        final normClean = normalizeFullWidth(cleanTitle).replaceAll(RegExp(r'[―—–ー−\-]'), '-');
        final matchKey = normClean.length > 3 ? normClean.substring(0, 3) : normClean;
        if (!normTitle.contains(matchKey)) {
          continue;
        }

        matchedCount++;
        if (firstMatchedTitle.isEmpty) {
          firstMatchedTitle = title;
          firstMatchedUrl = directHref;
        }

        final vol = _extractVolume(title, baseTitle: cleanTitle);
        if (vol > 0.0 && vol < 150.0 && vol > maxVol) {
          maxVol = vol;
          bestTitle = title;
          bestUrl = directHref;
        }
      }

      // Single-volume fallback
      if (maxVol == 0.0 && matchedCount > 0) {
        maxVol = matchedCount == 1 ? 1.0 : matchedCount.toDouble();
        bestTitle = bestTitle.isNotEmpty ? bestTitle : firstMatchedTitle;
        bestUrl = bestUrl.isNotEmpty ? bestUrl : firstMatchedUrl;
      }

      if (maxVol > 0.0) {
        LogService.instance.debug('BookWalker JP', '[$cleanTitle] 解析成功: 最新卷數=$maxVol, 標題=$bestTitle');
        return RemoteBookResult(
          latestVol: maxVol,
          title: bestTitle,
          url: bestUrl,
        );
      }
    } catch (e, s) {
      LogService.instance.warn('BookWalker JP', '搜尋日版失敗: $cleanTitle', error: e);
    }
    return null;
  }

  Future<RemoteBookResult?> _parseJapanSeriesPage(
    String seriesUrl,
    String cleanTitle, {
    int seriesCardCount = 0,
  }) async {
    try {
      final res = await _dio.get(seriesUrl);
      if (res.statusCode != 200 || res.data == null) return null;

      final doc = html_parser.parse(res.data);
      // Strictly query only book items, NEVER bare li!
      final items = doc.querySelectorAll('.m-book-item');

      double maxVol = 0.0;
      String bestTitle = '';
      String bestUrl = cleanUrl(seriesUrl);
      int matchedCount = 0;
      String firstMatchedTitle = '';
      String firstMatchedUrl = '';

      for (final item in items) {
        final title = normalizeFullWidth(
          item.querySelector('img')?.attributes['alt'] ??
          item.querySelector('.a-tile-ttl')?.text ??
          item.querySelector('.m-book-item__title a')?.text.trim() ?? ''
        );
        final a = item.querySelector('p.m-book-item__title a, a.m-book-item__title, a.m-thumb__image, .m-book-item__title a') ??
            item.querySelector('a:not(.m-thumb__check)');
        final rawHref = a?.attributes['href'] ?? '';

        if (title.isEmpty || isIrrelevantItem(title, rawHref) || isComicItem(title)) {
          continue;
        }

        final label = item.querySelector('.m-book-item__label, .m-thumb__label-area, .m-book-item__status-tag')?.text.trim() ?? '';
        if (isPreorderItem(title, label: label, text: item.text)) {
          LogService.instance.info('BookWalker JP', '[$cleanTitle] 排除預購系列作品: $title');
          continue;
        }

        final directHref = cleanUrl(rawHref);
        if (directHref.isNotEmpty && !directHref.contains('/de') && !directHref.contains('/series/')) {
          continue;
        }

        matchedCount++;
        if (firstMatchedTitle.isEmpty) {
          firstMatchedTitle = title;
          firstMatchedUrl = directHref;
        }

        final vol = _extractVolume(title, baseTitle: cleanTitle);
        if (vol > 0.0 && vol < 150.0 && vol > maxVol) {
          maxVol = vol;
          bestTitle = title;
          if (directHref.isNotEmpty) {
            bestUrl = directHref;
          }
        }
      }

      // If books in series have parsed volume numbers (e.g. Ep.14), use maxVol!
      // Only fall back to seriesCardCount or matchedCount if NO volumes were extracted at all
      final finalVol = maxVol > 0.0
          ? maxVol
          : (seriesCardCount > 0 && seriesCardCount < 150
              ? seriesCardCount.toDouble()
              : (matchedCount > 0 ? (matchedCount == 1 ? 1.0 : matchedCount.toDouble()) : 0.0));

      if (finalVol > 0.0) {
        return RemoteBookResult(
          latestVol: finalVol,
          title: bestTitle.isNotEmpty ? bestTitle : (firstMatchedTitle.isNotEmpty ? firstMatchedTitle : cleanTitle),
          url: bestUrl.isNotEmpty ? bestUrl : (firstMatchedUrl.isNotEmpty ? firstMatchedUrl : cleanUrl(seriesUrl)),
        );
      }
    } catch (_) {}
    return null;
  }

  static double _extractVolume(String text, {String baseTitle = ''}) {
    var norm = normalizeFullWidth(text).replaceAll('．', '.');

    // Strip discounts, prices, promo text
    norm = norm.replaceAll(RegExp(r'\d+\s*(?:折|元|點|%|pt|OFF)', caseSensitive: false), '');
    norm = norm.replaceAll(RegExp(r'滿\d+'), '');

    // Strip years and full dates (e.g. 2026年秋, 2026年, 2024-10-12, 2026/05)
    norm = norm.replaceAll(RegExp(r'(?:19|20)\d{2}\s*年(?:\s*(?:春|夏|秋|冬|\d{1,2}月?))?'), '');
    norm = norm.replaceAll(RegExp(r'(?:19|20)\d{2}[-/.]\d{1,2}(?:[-/.]\d{1,2})?'), '');
    norm = norm.replaceAll(RegExp(r'\b(?:19|20)\d{2}\b'), '');

    // Strip bonus/benefit markers like 【電子限定特典付き】
    norm = norm.replaceAll(RegExp(r'【.*?(?:特典|限定|小冊子|フェア).*?】'), '');
    norm = norm.replaceAll(RegExp(r'\[.*?(?:特典|限定|小冊子|フェア).*?\]'), '');
    norm = norm.replaceAll(RegExp(r'\(.*?(?:特典|限定|小冊子|フェア).*?\)'), '');
    norm = norm.replaceAll(RegExp(r'（.*?(?:特典|限定|小冊子|フェア).*?）'), '');

    // Normalize number followed by period punctuation (e.g. "28.魔女の誘惑" -> "28 魔女の誘惑")
    // When dot is NOT followed by a digit, it is punctuation, not a decimal!
    norm = norm.replaceAllMapped(RegExp(r'(\d+)\.(?!\d)'), (m) => '${m[1]} ');

    // Calculate arc accumulation offset (e.g. Classroom of the Elite 實力至上主義的教室)
    double arcOffset = 0.0;
    final isClassroom = baseTitle.contains('実力至上主義') ||
        baseTitle.contains('實力至上主義') ||
        text.contains('実力至上主義') ||
        text.contains('實力至上主義');

    if (isClassroom) {
      if (norm.contains('2年生') || norm.contains('2年級') || norm.contains('二年級')) {
        arcOffset = 11.0; // 11 mainline volumes in 1st year (1-11)
      } else if (norm.contains('3年生') || norm.contains('3年級') || norm.contains('三年級')) {
        arcOffset = 23.0; // 11 (1st year) + 12 (2nd year) = 23
      }
    }

    // Strip baseTitle to prevent numbers in the title (e.g. "86") from matching
    var stripped = norm;
    if (baseTitle.isNotEmpty) {
      final normBase = normalizeFullWidth(baseTitle).replaceAll('．', '.');
      stripped = stripped.replaceAll(normBase, '');
      for (final part in normBase.split(RegExp(r'[\s―\-~]'))) {
        if (part.length >= 2) {
          stripped = stripped.replaceAll(part, '');
        }
      }
    }

    // Strip arc markers (e.g. 2年生編, ２年級篇, 第2部, 2nd season)
    stripped = stripped.replaceAll(RegExp(r'\d+\s*(?:年生編|年生|年級篇|年級|期|部|章)', caseSensitive: false), '');
    stripped = stripped.replaceAllMapped(RegExp(r'(\d+)\.(?!\d)'), (m) => '${m[1]} ');

    // Re-strip any stray years in stripped string
    stripped = stripped.replaceAll(RegExp(r'(?:19|20)\d{2}\s*年?'), '');
    stripped = stripped.replaceAll(RegExp(r'\b(?:19|20)\d{2}\b'), '');

    // Helper validator: light novel volumes are never >= 150
    double sanitizeVol(double v) {
      final finalV = v + arcOffset;
      if (finalV <= 0.0 || finalV >= 150.0) return 0.0;
      return finalV;
    }

    // 0. Single volume marker: (全), （全）, [全], 全一冊, 全1冊
    if (RegExp(r'[\(（\[]全(?:一[卷冊集]|1[卷冊集])?[\)）\]]|(?<!\w)全一[卷冊集]|(?<!\w)全1[卷冊集]').hasMatch(norm)) {
      return 1.0;
    }

    // 1. Explicit volume markers in stripped text: Ep.14 / Ep 14 / 第4.5卷 / Vol.7.5
    final volPrefixRegex = RegExp(
      r'(?:第|\bvol\.?|\bv|\bep\.?|\bepisode\s*)(\d+(?:\.\d+)?)(?:[-~](\d+(?:\.\d+)?))?(?:卷|冊|集|\b)',
      caseSensitive: false,
    );
    final vpMatch = volPrefixRegex.firstMatch(stripped);
    if (vpMatch != null) {
      final v1 = double.tryParse(vpMatch.group(1)!) ?? 0.0;
      final v2 = double.tryParse(vpMatch.group(2) ?? '') ?? 0.0;
      final result = v2 > v1 ? v2 : v1;
      final cleanV = sanitizeVol(result);
      if (cleanV > 0.0) return cleanV;
    }

    // 2. Parentheses in stripped text: (09), (4.5), （7.5）
    final parenRegex = RegExp(r'[\(（](\d+(?:\.\d+)?)[\)）]');
    final pMatch = parenRegex.firstMatch(stripped);
    if (pMatch != null) {
      final cleanV = sanitizeVol(double.tryParse(pMatch.group(1)!) ?? 0.0);
      if (cleanV > 0.0) return cleanV;
    }

    // 3. Roman numerals in stripped text: XXIV, XXIII, VII, etc.
    final romanRegex = RegExp(
      r'(?:^|[\s　―\-_])([IVXLCDM]{1,6})(?:[\s　―\-_]|$)',
      caseSensitive: false,
    );
    final rmMatch = romanRegex.firstMatch(stripped);
    if (rmMatch != null) {
      final rVal = romanToInt(rmMatch.group(1)!);
      if (rVal > 0) return sanitizeVol(rVal.toDouble());
    }

    // 4. Leading number after baseTitle (e.g. "ノーゲーム・ノーライフ 13　ゲーマー兄妹...", "4.5")
    final leadingRegex = RegExp(r'^\s*(\d+(?:\.\d+)?)(?:[^\d\.]|$)');
    final lmMatch = leadingRegex.firstMatch(stripped);
    if (lmMatch != null) {
      final cleanV = sanitizeVol(double.tryParse(lmMatch.group(1)!) ?? 0.0);
      if (cleanV > 0.0) return cleanV;
    }

    // 5. Standalone middle number
    final middleRegex = RegExp(r'(?:^|[\s　―\-_:：編年生篇級])(\d+(?:\.\d+)?)(?:[\s　―\-_:：]|$)', caseSensitive: false);
    final mmMatch = middleRegex.firstMatch(stripped);
    if (mmMatch != null) {
      final cleanV = sanitizeVol(double.tryParse(mmMatch.group(1)!) ?? 0.0);
      if (cleanV > 0.0) return cleanV;
    }

    // 6. Trailing number in stripped text (e.g. 轉生王女...13, 鄰家天使...5.5)
    final trailingRegex = RegExp(r'(?:^|[^\d])(\d+(?:\.\d+)?)\s*(?:―.*)?$');
    final tMatch = trailingRegex.firstMatch(stripped);
    if (tMatch != null) {
      final cleanV = sanitizeVol(double.tryParse(tMatch.group(1)!) ?? 0.0);
      if (cleanV > 0.0) return cleanV;
    }

    return 0.0;
  }

  String _cleanTitle(String title) {
    var s = title.trim();
    s = s.replaceAll(RegExp(r'\[.*?\]'), '');
    s = s.replaceAll(RegExp(r'\(.*?\)'), '');
    s = s.replaceAll('「', '').replaceAll('」', '');
    s = s.replaceAll('―', '-').replaceAll('—', '-');
    return s.trim();
  }
}
