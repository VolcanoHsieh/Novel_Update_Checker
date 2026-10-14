import 'package:dio/dio.dart';

class BangumiSubject {
  final int id;
  final String name; // Japanese title
  final String nameCn; // Chinese title
  final int? volsCount;
  final String? airDate;
  final String url;
  final String platform;

  BangumiSubject({
    required this.id,
    required this.name,
    required this.nameCn,
    this.volsCount,
    this.airDate,
    required this.url,
    this.platform = '小说',
  });
}

class BangumiService {
  final Dio _dio;

  BangumiService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              headers: {
                'User-Agent':
                    'NovelUpdateChecker/1.0 (Windows; https://github.com/novel-checker)',
              },
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
            ));

  /// Normalize symbols and unescape HTML entities
  static String normalize(String s) {
    var res = s.trim();
    // HTML entities unescape
    res = res.replaceAll('&amp;', '&')
             .replaceAll('&quot;', '"')
             .replaceAll('&#039;', "'")
             .replaceAll('&lt;', '<')
             .replaceAll('&gt;', '>');
    // Full width normalization
    res = res.replaceAll('＆', '&')
             .replaceAll('：', ':')
             .replaceAll('～', '~')
             .replaceAll('―', '-')
             .replaceAll('—', '-')
             .replaceAll('（', '(')
             .replaceAll('）', ')')
             .replaceAll('「', '')
             .replaceAll('」', '');
    return res;
  }

  /// Common Traditional to Simplified Chinese character replacements for light novel search
  static const Map<String, String> _t2sMap = {
    '撫': '抚', '養': '养', '懷': '怀', '抱': '抱', '劍': '剑', '儂': '侬',
    '轉': '转', '生': '生', '雙': '双', '戀': '恋', '愛': '爱', '學': '学',
    '園': '园', '術': '术', '師': '师', '戰': '战', '區': '区', '實': '实',
    '力': '力', '至': '至', '上': '上', '主': '主', '義': '义', '教': '教',
    '室': '室', '魔': '魔', '王': '王', '勇': '勇', '者': '者', '隊': '队',
    '伍': '伍', '異': '异', '世': '世', '界': '界', '發': '发', '小': '小',
    '兒': '儿', '時': '时', '玩': '玩', '伴': '伴', '惡': '恶', '劣': '劣',
    '體': '体', '驗': '验', '奪': '夺', '走': '走', '聖': '圣', '顯': '显',
    '現': '现', '賢': '贤', '孫': '孙', '點': '点', '滿': '满', '防': '防',
    '禦': '御', '無': '无', '職': '职', '這': '这', '與': '与', '場': '场',
    '後': '后', '宮': '宫', '國': '国', '門': '门', '開': '开', '關': '关',
    '騎': '骑', '士': '士', '法': '法', '雜': '杂', '誌': '志', '話': '话',
  };

  static String toSimplified(String text) {
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      final ch = text[i];
      buffer.write(_t2sMap[ch] ?? ch);
    }
    return buffer.toString();
  }

  /// Try to fetch official Japanese title using Wikipedia Chinese-to-Japanese langlinks
  Future<String?> fetchWikipediaJpTitle(String chineseTitle) async {
    final clean = normalize(chineseTitle);
    final variations = <String>{
      clean,
      clean.replaceAll('&', '與'),
      clean.replaceAll('&', '和'),
      clean.replaceAll('與', '&'),
      clean.replaceAll('和', '&'),
      clean.replaceAll('-', ' '),
      clean.replaceAll('-', ''),
      clean.replaceAll('―', ''),
      clean.replaceAll('—', ''),
      toSimplified(clean),
      toSimplified(clean.replaceAll('-', ' ')),
    };

    // 1. Direct page query with variations
    for (final v in variations) {
      try {
        final res = await _dio.get('https://zh.wikipedia.org/w/api.php', queryParameters: {
          'action': 'query',
          'titles': v,
          'prop': 'langlinks',
          'lllang': 'ja',
          'format': 'json',
          'redirects': '1',
        });

        final pages = res.data['query']?['pages'] as Map<String, dynamic>?;
        if (pages != null && !pages.containsKey('-1')) {
          final firstPage = pages.values.first;
          final langlinks = firstPage['langlinks'] as List<dynamic>?;
          if (langlinks != null && langlinks.isNotEmpty) {
            final jaTitle = langlinks.first['*'] as String?;
            if (jaTitle != null && jaTitle.isNotEmpty) {
              return jaTitle.split(RegExp(r'\s*[\(（]')).first.trim();
            }
          }
        }
      } catch (_) {}
    }

    // 2. Wikipedia search fallback
    try {
      final sRes = await _dio.get('https://zh.wikipedia.org/w/api.php', queryParameters: {
        'action': 'query',
        'list': 'search',
        'srsearch': clean,
        'format': 'json',
        'srlimit': '3',
      });
      final searchList = sRes.data['query']?['search'] as List<dynamic>?;
      if (searchList != null && searchList.isNotEmpty) {
        for (final item in searchList) {
          final articleTitle = item['title'] as String? ?? '';
          if (articleTitle.isEmpty) continue;

          // Only consider articles with relevant title overlap
          if (_calcSimilarity(clean, articleTitle) < 30) continue;

          final llRes = await _dio.get('https://zh.wikipedia.org/w/api.php', queryParameters: {
            'action': 'query',
            'titles': articleTitle,
            'prop': 'langlinks',
            'lllang': 'ja',
            'format': 'json',
          });
          final pages = llRes.data['query']?['pages'] as Map<String, dynamic>?;
          final p = pages?.values.first;
          final ll = p?['langlinks'] as List<dynamic>?;
          if (ll != null && ll.isNotEmpty) {
            final jaTitle = ll.first['*'] as String?;
            if (jaTitle != null && jaTitle.isNotEmpty) {
              return jaTitle.split(RegExp(r'\s*[\(（]')).first.trim();
            }
          }
        }
      }
    } catch (_) {}

    return null;
  }

  /// Search Bangumi for novel subjects matching title
  Future<BangumiSubject?> searchNovel(String title) async {
    final clean = normalize(title);

    // 1. Try Wikipedia FIRST (high authority, official titles like ナイツ&マジック)
    final wikiJp = await fetchWikipediaJpTitle(clean);
    if (wikiJp != null && wikiJp.isNotEmpty) {
      // Find Bangumi ID and volumes using the official Japanese title if possible
      final bgmWithJp = await _executeBangumiSearch(wikiJp);
      return BangumiSubject(
        id: bgmWithJp?.id ?? 0,
        name: wikiJp,
        nameCn: clean,
        volsCount: bgmWithJp?.volsCount,
        airDate: bgmWithJp?.airDate,
        url: bgmWithJp?.url ?? 'https://ja.wikipedia.org/wiki/${Uri.encodeComponent(wikiJp)}',
      );
    }

    // 2. Try Bangumi search with variations
    final variations = <String>{
      clean,
      clean.replaceAll('&', '與'),
      clean.replaceAll('&', '和'),
      clean.replaceAll('與', '&'),
      clean.replaceAll('和', '&'),
      clean.replaceAll('-', ' '),
      clean.replaceAll('-', ''),
      toSimplified(clean),
      toSimplified(clean.replaceAll('-', ' ')),
    };

    if (clean.contains('兒時玩伴') || clean.contains('儿时玩伴') || clean.contains('發小') || clean.contains('发小')) {
      variations.add(clean.replaceAll(RegExp(r'兒時玩伴|儿时玩伴'), '发小'));
      variations.add(toSimplified(clean.replaceAll(RegExp(r'兒時玩伴|儿时玩伴'), '发小')));
      variations.add(clean.replaceAll(RegExp(r'發小|发小'), '青梅竹馬'));
      variations.add(toSimplified(clean.replaceAll(RegExp(r'發小|发小'), '青梅竹马')));
      variations.add(clean.replaceAll(RegExp(r'男生的?發小|男生的?发小'), '男孩子的青梅竹马'));
      variations.add(toSimplified(clean.replaceAll(RegExp(r'男生的?發小|男生的?发小'), '男孩子的青梅竹马')));
    }

    for (final q in variations) {
      final res = await _executeBangumiSearch(q);
      if (res != null) return res;
    }

    return null;
  }

  Future<BangumiSubject?> _executeBangumiSearch(String query) async {
    try {
      final response = await _dio.get(
        'https://api.bgm.tv/search/subject/${Uri.encodeComponent(query)}',
        queryParameters: {
          'type': 1, // Book / Novel
          'responseGroup': 'large',
        },
      );

      if (response.statusCode != 200 || response.data == null) {
        return null;
      }

      final list = response.data['list'] as List<dynamic>?;
      if (list == null || list.isEmpty) {
        return null;
      }

      BangumiSubject? bestMatch;
      int bestScore = 0;
      final normQuery = normalize(query);
      final hasVolNumber = RegExp(r'\d+').hasMatch(normQuery);

      for (final item in list) {
        final id = item['id'] as int? ?? 0;
        final rawName = item['name'] as String? ?? '';
        final rawNameCn = item['name_cn'] as String? ?? '';
        final name = normalize(rawName);
        final nameCn = normalize(rawNameCn);
        final volsCount = item['vols_count'] as int?;
        final airDate = item['air_date'] as String?;
        final url = item['url'] as String? ?? 'https://bgm.tv/subject/$id';
        final platform = item['platform'] as String? ?? '';

        // Filter out manga, anthologies, art books, and animation fanbooks
        if (platform == '漫画' ||
            platform == '画集' ||
            name.contains('ANIMATION') ||
            name.contains('公式ファンブック') ||
            name.contains('アンソロジー') ||
            name.contains('コミック') ||
            name.contains('コミックス') ||
            nameCn.contains('漫画') ||
            name.contains('漫画')) {
          continue;
        }

        // Base similarity
        final scoreName = _calcSimilarity(normQuery, name);
        final scoreCn = _calcSimilarity(normQuery, nameCn);
        var score = scoreName > scoreCn ? scoreName : scoreCn;

        // Exact match boosts
        final qSimplified = toSimplified(normQuery);
        final cnSimplified = toSimplified(nameCn);
        if (cnSimplified == qSimplified || name == normQuery) {
          score += 150;
        } else if (cnSimplified.startsWith(qSimplified) || qSimplified.startsWith(cnSimplified)) {
          score += 50;
        }

        // Subtitle / volume pollution penalty:
        // E.g., if item has volume numbers like "17" or "04" while query does not
        if (!hasVolNumber && RegExp(r'(?:^|[^\d])\d{1,3}(?:[^\d]|$)').hasMatch(name)) {
          score -= 80;
        }

        // Penalty for SS / Extra / Fan spin-offs
        if ((name.contains('SS') || name.contains('Extra') || name.contains('SP') || name.contains('外伝')) &&
            !normQuery.contains('SS') &&
            !normQuery.contains('外傳') &&
            !normQuery.contains('外传') &&
            !normQuery.contains('短篇')) {
          score -= 40;
        }

        if (score > bestScore) {
          bestScore = score;
          bestMatch = BangumiSubject(
            id: id,
            name: name.isNotEmpty ? name : nameCn,
            nameCn: nameCn.isNotEmpty ? nameCn : name,
            volsCount: volsCount,
            airDate: airDate,
            url: url,
          );
        }
      }

      if (bestScore >= 25) {
        return bestMatch;
      }
    } catch (_) {}
    return null;
  }

  int _calcSimilarity(String query, String target) {
    if (target.isEmpty) return 0;
    if (query == target) return 100;
    if (target.contains(query) || query.contains(target)) return 80;

    final qChars = query.replaceAll(RegExp(r'[\s―\-_~「」&:：&]'), '').split('').toSet();
    final tChars = target.replaceAll(RegExp(r'[\s―\-_~「」&:：&]'), '').split('').toSet();

    int common = 0;
    for (final c in qChars) {
      if (tChars.contains(c)) common++;
    }

    if (common == 0) return 0;

    int score = (common / qChars.length * 50).round();
    if (target.startsWith(query) || query.startsWith(target)) score += 20;
    return score;
  }
}
