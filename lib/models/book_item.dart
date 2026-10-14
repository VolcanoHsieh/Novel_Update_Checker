
enum UpdateStatus {
  unknown,
  checking,
  upToDate,
  twUpdated,
  jpUpdated,
  bothUpdated,
  notFound,
  error,
}

class BookItem {
  final String title;
  final String folderPath;
  double localMaxVol;
  List<double> localVolumes;
  int localFilesCount;
  String category;

  String? jpTitle;
  int? bangumiId;

  // Taiwan BookWalker progress
  double? cachedTwVol; // Taiwan baseline recorded in cache
  double? twLatestVol; // Taiwan latest release online
  String? twLatestTitle;
  String? twUrl;
  String? twPublishDate;

  // Japan BookWalker progress
  double? cachedJpVol; // Japan baseline recorded in cache
  double? jpLatestVol; // Japan latest release online
  String? jpLatestTitle;
  String? jpUrl;
  String? jpPublishDate;

  UpdateStatus status;
  String? statusMessage;
  DateTime? lastChecked;

  bool isCompleted;
  bool isIgnored;
  bool manualOverride;

  BookItem({
    required this.title,
    required this.folderPath,
    this.localMaxVol = 0.0,
    List<double>? localVolumes,
    this.localFilesCount = 0,
    this.category = '',
    this.jpTitle,
    this.bangumiId,
    this.cachedTwVol,
    this.twLatestVol,
    this.twLatestTitle,
    this.twUrl,
    this.twPublishDate,
    this.cachedJpVol,
    this.jpLatestVol,
    this.jpLatestTitle,
    this.jpUrl,
    this.jpPublishDate,
    this.status = UpdateStatus.unknown,
    this.statusMessage = '待確認',
    this.lastChecked,
    this.isCompleted = false,
    this.isIgnored = false,
    this.manualOverride = false,
  }) : localVolumes = localVolumes ?? [];

  /// Helper to format volume number (e.g. 14 or 4.5)
  static String formatVol(double? vol) {
    if (vol == null) return '-';
    if (vol % 1 == 0) {
      return vol.toInt().toString();
    } else {
      return vol.toString();
    }
  }

  /// Helper to format volume diff (e.g. +1 or +0.5)
  static String formatDiff(double diff) {
    if (diff % 1 == 0) {
      return diff.toInt().toString();
    } else {
      return diff.toString();
    }
  }

  /// Get baseline for Taiwan updates: prioritize cache over local file count
  double get twBaseline => cachedTwVol ?? localMaxVol;

  /// Get baseline for Japan updates: prioritize cache over local file count
  double get jpBaseline => cachedJpVol ?? localMaxVol;

  /// Calculate status based on current local and remote volume numbers
  void refreshStatus() {
    if (isIgnored) {
      status = UpdateStatus.unknown;
      statusMessage = '已忽略';
      return;
    }

    if (lastChecked == null) {
      status = UpdateStatus.unknown;
      statusMessage = '待確認';
      return;
    }

    final hasTwNew = twLatestVol != null && twLatestVol! > twBaseline;
    final hasJpNew = jpLatestVol != null && jpLatestVol! > jpBaseline;

    if (hasTwNew && hasJpNew) {
      status = UpdateStatus.bothUpdated;
      statusMessage = '台日皆有更新 (台 +${formatDiff(twLatestVol! - twBaseline)}, 日 +${formatDiff(jpLatestVol! - jpBaseline)})';
    } else if (hasTwNew) {
      status = UpdateStatus.twUpdated;
      statusMessage = '台版有更新 (+${formatDiff(twLatestVol! - twBaseline)} 集)';
    } else if (hasJpNew) {
      status = UpdateStatus.jpUpdated;
      statusMessage = '日版有新進度 (+${formatDiff(jpLatestVol! - jpBaseline)} 集)';
    } else if (twLatestVol != null || jpLatestVol != null) {
      status = UpdateStatus.upToDate;
      statusMessage = '已是最新';
    } else {
      status = UpdateStatus.notFound;
      statusMessage = '查無資料';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'folderPath': folderPath,
      'localMaxVol': localMaxVol,
      'localVolumes': localVolumes,
      'localFilesCount': localFilesCount,
      'category': category,
      'jpTitle': jpTitle,
      'bangumiId': bangumiId,
      'cachedTwVol': cachedTwVol,
      'twLatestVol': twLatestVol,
      'twLatestTitle': twLatestTitle,
      'twUrl': twUrl,
      'twPublishDate': twPublishDate,
      'cachedJpVol': cachedJpVol,
      'jpLatestVol': jpLatestVol,
      'jpLatestTitle': jpLatestTitle,
      'jpUrl': jpUrl,
      'jpPublishDate': jpPublishDate,
      'status': status.name,
      'statusMessage': statusMessage,
      'lastChecked': lastChecked?.toIso8601String(),
      'isCompleted': isCompleted,
      'isIgnored': isIgnored,
      'manualOverride': manualOverride,
    };
  }

  factory BookItem.fromJson(Map<String, dynamic> json) {
    UpdateStatus parseStatus(String? name) {
      if (name == null) return UpdateStatus.unknown;
      return UpdateStatus.values.firstWhere(
        (e) => e.name == name,
        orElse: () => UpdateStatus.unknown,
      );
    }

    var jpVol = (json['jpLatestVol'] as num?)?.toDouble();
    var jpLatestTitle = json['jpLatestTitle'] as String?;
    var jpUrl = json['jpUrl'] as String?;

    // Self-healing: if corrupted promo banner or absurd volume (> 150) was cached
    if (jpVol != null && jpVol >= 150.0) {
      jpVol = null;
      jpLatestTitle = null;
      jpUrl = null;
    }
    if (jpUrl != null && (jpUrl.contains('/select/') || jpUrl.contains('/campaign/'))) {
      jpVol = null;
      jpLatestTitle = null;
      jpUrl = null;
    }

    final book = BookItem(
      title: json['title'] as String? ?? '',
      folderPath: json['folderPath'] as String? ?? '',
      localMaxVol: (json['localMaxVol'] as num?)?.toDouble() ?? 0.0,
      localVolumes: (json['localVolumes'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          [],
      localFilesCount: json['localFilesCount'] as int? ?? 0,
      category: json['category'] as String? ?? '',
      jpTitle: json['jpTitle'] as String?,
      bangumiId: json['bangumiId'] as int?,
      cachedTwVol: (json['cachedTwVol'] as num?)?.toDouble(),
      twLatestVol: (json['twLatestVol'] as num?)?.toDouble(),
      twLatestTitle: json['twLatestTitle'] as String?,
      twUrl: json['twUrl'] as String?,
      twPublishDate: json['twPublishDate'] as String?,
      cachedJpVol: (json['cachedJpVol'] as num?)?.toDouble(),
      jpLatestVol: jpVol,
      jpLatestTitle: jpLatestTitle,
      jpUrl: jpUrl,
      jpPublishDate: json['jpPublishDate'] as String?,
      status: parseStatus(json['status'] as String?),
      statusMessage: json['statusMessage'] as String? ?? '待確認',
      lastChecked: json['lastChecked'] != null
          ? DateTime.tryParse(json['lastChecked'] as String)
          : null,
      isCompleted: json['isCompleted'] as bool? ?? false,
      isIgnored: json['isIgnored'] as bool? ?? false,
      manualOverride: json['manualOverride'] as bool? ?? false,
    );

    if (jpVol == null && (json['jpLatestVol'] as num?)?.toDouble() != null) {
      book.refreshStatus();
    }
    return book;
  }
}
