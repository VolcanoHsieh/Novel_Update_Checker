import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/app_config.dart';
import '../models/book_item.dart';

class ScannerService {
  /// Known top-level category folder names
  static final Set<String> categoryFolderNames = {
    '完結', '完结', '已完結', '已完结',
    '連載中', '连载中', '連載', '连载',
    '未完', '未完結', '未完结',
    '暫停', '停更', '精選', '精选',
  };

  /// Subordinate / side-story folder names that belong to their parent series folder
  static final Set<String> subordinateFolderNames = {
    '外傳', '外传', '短篇', '短編集', '短篇集', '短篇合集', '短篇+短篇集',
    '特典', '特典小說', 'ss', 'side story', 'extra', 'sp',
    '特別篇', '特別篇章', '番外', '番外篇',
    '設定集', '公式書', '導讀', 'fanbook',
    '本篇', '正傳', '正传', '本編', '正文', '本傳',
    '文庫', '文庫版',
    'web', 'web版', '同人', '學園物語', '学园物语', '學園', '学园',
    'progressive', 'after the end', 'after_the_end',
  };

  /// Check if a directory name looks like a Category folder
  static bool isCategoryFolder(String name) {
    return categoryFolderNames.contains(name.trim().toLowerCase());
  }

  /// Check if a directory name looks like a subordinate/side story folder
  static bool isSubordinateFolder(String name) {
    final lower = name.trim().toLowerCase();
    if (subordinateFolderNames.contains(lower)) return true;
    if (RegExp(r'^(外傳|外传|短篇|特典|番外|特別篇|設定集|web版?|正文|同人|學園)', caseSensitive: false).hasMatch(lower)) return true;
    // Volume folder e.g. 第01卷, Vol.01, 01
    if (RegExp(r'^(?:第\s*\d+\s*[卷冊集]|vol\.?\s*\d+|\d{1,3})$', caseSensitive: false).hasMatch(lower)) return true;
    return false;
  }

  /// Resolve the series path, series title, category, and whether file is in a subfolder
  static ({String seriesPath, String seriesTitle, String category, bool isSubFolder}) resolveSeriesInfo(
    String filePath,
    String rootPath,
  ) {
    final relPath = p.relative(filePath, from: rootPath);
    final segments = p.split(relPath);

    // If file is directly in root
    if (segments.length <= 1) {
      final title = cleanBookTitle(p.basenameWithoutExtension(filePath));
      return (seriesPath: filePath, seriesTitle: title, category: '', isSubFolder: false);
    }

    String category = '';
    int seriesIndex = 0;

    // Check if segment[0] is category (e.g. 完結, 連載中)
    if (isCategoryFolder(segments[0])) {
      category = segments[0];
      seriesIndex = 1;
    }

    // If segment at seriesIndex is directly the file itself (e.g. root/完結/太虛至尊.txt)
    if (seriesIndex >= segments.length - 1) {
      final title = cleanBookTitle(p.basenameWithoutExtension(filePath));
      return (seriesPath: filePath, seriesTitle: title, category: category, isSubFolder: false);
    }

    // The folder at seriesIndex is the true series folder
    final seriesFolderName = segments[seriesIndex];
    final seriesPath = p.joinAll([rootPath, ...segments.sublist(0, seriesIndex + 1)]);

    // Check if file is inside a deeper subfolder (e.g. 正文, Web版, Progressive, etc.)
    final isSubFolder = segments.length > seriesIndex + 2;

    return (
      seriesPath: seriesPath,
      seriesTitle: cleanBookTitle(seriesFolderName),
      category: category,
      isSubFolder: isSubFolder,
    );
  }

  /// Scan directory recursively and return discovered BookItems.
  Future<List<BookItem>> scanDirectory(
    String rootPath,
    AppConfig config, {
    void Function(String currentPath, int count)? onProgress,
  }) async {
    final rootDir = Directory(rootPath);
    if (!await rootDir.exists()) {
      return [];
    }

    final RegExp patternRegex = config.compilePatternRegex();
    final supportedExts = config.supportedExtensions.map((e) => e.toLowerCase()).toSet();

    // Grouping by resolved series directory path
    final Map<String, List<({File file, bool isSubFolder, String category, String seriesTitle})>> seriesToFiles = {};
    int scannedFiles = 0;

    await for (final entity in rootDir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;

      final ext = p.extension(entity.path).toLowerCase();
      if (!supportedExts.contains(ext)) continue;

      scannedFiles++;
      if (scannedFiles % 10 == 0) {
        onProgress?.call(entity.path, scannedFiles);
      }

      // Resolve series info
      final info = resolveSeriesInfo(entity.path, rootPath);
      seriesToFiles.putIfAbsent(info.seriesPath, () => []).add((
        file: entity,
        isSubFolder: info.isSubFolder,
        category: info.category,
        seriesTitle: info.seriesTitle,
      ));
    }

    final List<BookItem> books = [];

    // Process each series directory
    for (final entry in seriesToFiles.entries) {
      final dirPath = entry.key;
      final fileEntries = entry.value;

      if (fileEntries.isEmpty) continue;

      final seriesTitle = fileEntries.first.seriesTitle;
      final category = fileEntries.first.category;

      // Check if standalone file in root or category folder
      final isStandaloneFile = fileEntries.length == 1 && fileEntries.first.file.path == dirPath;

      if (isStandaloneFile) {
        final file = fileEntries.first.file;
        final fileName = p.basenameWithoutExtension(file.path);
        final (vol, title, isExtra) = parseVolumeAndTitle(fileName, patternRegex, seriesName: fileName);
        final bookTitle = title.isNotEmpty ? title : fileName;

        books.add(BookItem(
          title: cleanBookTitle(bookTitle),
          folderPath: file.path,
          localMaxVol: vol > 0.0 ? vol : 1.0,
          localVolumes: vol > 0.0 ? [vol] : [1.0],
          localFilesCount: 1,
          category: category,
          cachedTwVol: vol > 0.0 ? vol : 1.0,
          isCompleted: category.contains('完結') || category.contains('完结'),
        ));
        continue;
      }

      // Collect mainline volumes and side stories
      final List<double> mainlineVolumes = [];
      final List<double> extraVolumes = [];

      for (final item in fileEntries) {
        final fileName = p.basenameWithoutExtension(item.file.path);
        final (vol, _, isExtra) = parseVolumeAndTitle(fileName, patternRegex, seriesName: seriesTitle);

        // Check if inside subordinate folder (e.g. 同人, 學園物語, 外傳, Web版)
        final dirName = p.basename(item.file.parent.path);
        final inSideFolder = isSubordinateFolder(dirName) && !dirName.contains('正文') && !dirName.contains('本傳') && !dirName.contains('本篇');

        if (vol > 0.0) {
          if (inSideFolder || isExtra) {
            extraVolumes.add(vol);
          } else {
            mainlineVolumes.add(vol);
          }
        }
      }

      // Deduplicate volumes
      final uniqueMainline = mainlineVolumes.toSet().toList()..sort();
      final uniqueExtra = extraVolumes.toSet().toList()..sort();

      double maxVol = 0.0;
      if (uniqueMainline.isNotEmpty) {
        maxVol = uniqueMainline.last;
      } else if (uniqueExtra.isNotEmpty) {
        maxVol = uniqueExtra.last;
      } else {
        maxVol = fileEntries.length == 1 ? 1.0 : fileEntries.length.toDouble();
      }

      books.add(BookItem(
        title: seriesTitle,
        folderPath: dirPath,
        localMaxVol: maxVol,
        localVolumes: uniqueMainline.isNotEmpty ? uniqueMainline : uniqueExtra,
        localFilesCount: fileEntries.length,
        category: category,
        cachedTwVol: maxVol,
        isCompleted: category.contains('完結') || category.contains('完结'),
      ));
    }

    // Sort books alphabetically by title
    books.sort((a, b) => a.title.compareTo(b.title));
    return books;
  }

  /// Parse volume number and title from filename
  static (double vol, String title, bool isExtra) parseVolumeAndTitle(
    String fileName,
    RegExp patternRegex, {
    String seriesName = '',
  }) {
    double maxVol = 0.0;
    String cleanTitle = '';

    // Check if filename indicates a side story / extra / spin-off
    bool isExtra = RegExp(
      r'(?:短篇|外傳|外传|特典|番外|特別篇|特別編|side\s*story|extra|ss|sp|學園|学园|同人|web版)',
      caseSensitive: false,
    ).hasMatch(fileName);

    // 1. Try custom pattern regex from user config
    final match = patternRegex.firstMatch(fileName);
    if (match != null) {
      if (match.groupCount >= 1 && match.group(1) != null) {
        final v1 = double.tryParse(match.group(1)!) ?? 0.0;
        double v2 = 0.0;
        if (match.groupCount >= 2 && match.group(2) != null) {
          v2 = double.tryParse(match.group(2)!) ?? 0.0;
        }
        maxVol = v2 > v1 ? v2 : v1;
      }
      if (match.groupCount >= 3 && match.group(3) != null) {
        cleanTitle = match.group(3)!.trim();
      }
      if (maxVol > 0.0) {
        return (maxVol, cleanTitle, isExtra);
      }
    }

    // 2. Bracket format: [-01-], [-01-05-], [-短篇01-], [-外傳02-], [-EX01-], [-07.5-], [-04上-]
    final bracketRegex = RegExp(
      r'\[-(?:(短篇|外傳|外传|特典|番外|特別篇|EX|SP)\s*)?(\d+(?:\.\d+)?)(?:[上下中])?(?:-(\d+(?:\.\d+)?))?-\]\s*(.*)',
      caseSensitive: false,
    );
    final bMatch = bracketRegex.firstMatch(fileName);
    if (bMatch != null) {
      if (bMatch.group(1) != null && bMatch.group(1)!.isNotEmpty) {
        isExtra = true;
      }
      final v1 = double.tryParse(bMatch.group(2) ?? '') ?? 0.0;
      final v2 = double.tryParse(bMatch.group(3) ?? '') ?? 0.0;
      maxVol = v2 > v1 ? v2 : v1;
      cleanTitle = (bMatch.group(4) ?? '').trim();
      return (maxVol, cleanTitle, isExtra);
    }

    // Strip seriesName to prevent numbers in title (like "86") from matching
    var stripped = fileName;
    if (seriesName.isNotEmpty) {
      stripped = stripped.replaceAll(seriesName, '');
      // Strip digits prefix if matched series starts with number
      final digits = RegExp(r'^\d+').stringMatch(seriesName);
      if (digits != null && digits.isNotEmpty) {
        stripped = stripped.replaceAll(RegExp('^$digits\\s*[-―_]?'), '');
      }
    }

    // 3. Explicit volume markers: 第X卷 / Vol.X / Ep.X / 第4.5卷
    final volRegex = RegExp(
      r'(?:第|\bvol\.?|\bv|\bep\.?|\bepisode\s*)(\d+(?:\.\d+)?)(?:[上下中])?(?:[-~](\d+(?:\.\d+)?))?(?:卷|冊|集|\b)',
      caseSensitive: false,
    );
    final vMatch = volRegex.firstMatch(stripped);
    if (vMatch != null) {
      final v1 = double.tryParse(vMatch.group(1) ?? '') ?? 0.0;
      final v2 = double.tryParse(vMatch.group(2) ?? '') ?? 0.0;
      maxVol = v2 > v1 ? v2 : v1;
      return (maxVol, cleanTitle, isExtra);
    }

    // 4. Trailing number at the end of the filename (e.g. "作品名 05")
    final trailingRegex = RegExp(r'(?:^|[^\d])(\d+(?:\.\d+)?)\s*(?:\.[a-zA-Z0-9]+)?$');
    final tMatch = trailingRegex.firstMatch(stripped);
    if (tMatch != null) {
      maxVol = double.tryParse(tMatch.group(1) ?? '') ?? 0.0;
      return (maxVol, cleanTitle, isExtra);
    }

    return (maxVol, cleanTitle, isExtra);
  }

  /// Clean extraneous punctuation and tags from book title
  static String cleanBookTitle(String title) {
    var result = title.trim();
    // Remove tags like [短篇], [輕小說], (完), [完]
    result = result.replaceAll(RegExp(r'\[(短篇|外傳|外传|輕小說|文庫|完)\]'), '');
    result = result.replaceAll(RegExp(r'\((完|連載中|连载中)\)'), '');
    // Remove leading [-01-] if present
    result = result.replaceAll(RegExp(r'^\[-(?:短篇|外傳|外传|特典|番外|特別篇|EX|SP)?\s*\d+(?:\.\d+)?(?:[上下中])?(?:-\d+)?-\]\s*'), '');
    return result.trim();
  }
}
