
class AppConfig {
  String rootFolder;
  String customPattern;
  bool useRegex;
  String customRegex;
  bool checkTw;
  bool checkJp;
  int requestDelayMs;
  List<String> supportedExtensions;
  int cacheExpireDays;

  AppConfig({
    this.rootFolder = '',
    this.customPattern = '[-{vol}-] {title}',
    this.useRegex = false,
    this.customRegex = r'\[-(\d+)(?:-(\d+))?-\]\s*(.*)',
    this.checkTw = true,
    this.checkJp = true,
    this.requestDelayMs = 800,
    List<String>? supportedExtensions,
    this.cacheExpireDays = 7,
  }) : supportedExtensions = supportedExtensions ??
            ['.epub', '.txt', '.mobi', '.pdf', '.zip', '.rar', '.azw3'];

  /// Convert a user-friendly template like `[-{vol}-] {title}` into a RegExp.
  /// Handles {vol} with optional range support e.g. 01 or 01-05.
  RegExp compilePatternRegex() {
    if (useRegex && customRegex.isNotEmpty) {
      try {
        return RegExp(customRegex, caseSensitive: false);
      } catch (_) {
        // Fallback to default
      }
    }

    // Escape special regex characters in pattern, but keep placeholder tokens
    String p = RegExp.escape(customPattern);

    // Replace escaped tokens with capture groups
    // {vol} can match 01 or 01-05
    p = p.replaceAll(
      RegExp.escape('{vol}'),
      r'(\d+)(?:-(\d+))?',
    );
    p = p.replaceAll(RegExp.escape('{title}'), r'(.*?)');
    p = p.replaceAll(RegExp.escape('{author}'), r'(.*?)');

    try {
      return RegExp(p, caseSensitive: false);
    } catch (_) {
      // Default fallback
      return RegExp(r'\[-(\d+)(?:-(\d+))?-\]', caseSensitive: false);
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'rootFolder': rootFolder,
      'customPattern': customPattern,
      'useRegex': useRegex,
      'customRegex': customRegex,
      'checkTw': checkTw,
      'checkJp': checkJp,
      'requestDelayMs': requestDelayMs,
      'supportedExtensions': supportedExtensions,
      'cacheExpireDays': cacheExpireDays,
    };
  }

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      rootFolder: json['rootFolder'] as String? ?? '',
      customPattern: json['customPattern'] as String? ?? '[-{vol}-] {title}',
      useRegex: json['useRegex'] as bool? ?? false,
      customRegex: json['customRegex'] as String? ?? r'\[-(\d+)(?:-(\d+))?-\]\s*(.*)',
      checkTw: json['checkTw'] as bool? ?? true,
      checkJp: json['checkJp'] as bool? ?? true,
      requestDelayMs: json['requestDelayMs'] as int? ?? 800,
      supportedExtensions: (json['supportedExtensions'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          ['.epub', '.txt', '.mobi', '.pdf', '.zip', '.rar', '.azw3'],
      cacheExpireDays: json['cacheExpireDays'] as int? ?? 7,
    );
  }
}
