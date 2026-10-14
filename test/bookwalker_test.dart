import 'package:novel_update_checker/services/bookwalker_service.dart';

void main() async {
  final service = BookWalkerService();
  final titles = [
    '精霊幻想記',
    'ようこそ実力至上主義の教室へ',
  ];

  for (final t in titles) {
    print('Searching $t ...');
    final res = await service.searchJapan(t);
    if (res != null) {
      print('[$t] -> Vol: ${res.latestVol} | Title: ${res.title} | URL: ${res.url}');
    } else {
      print('[$t] -> NOT FOUND');
    }
  }
}
