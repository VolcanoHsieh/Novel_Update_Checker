import 'package:novel_update_checker/services/bookwalker_service.dart';

void main() async {
  final service = BookWalkerService();
  final titles = [
    '86-エイティシックス-',
    'ノーゲーム・ノーライフ',
    '探偵はもう、死んでいる。',
    '時々ボソッとロシア語でデレる隣のアーリャさん',
    'ソードアート・オンライン',
    '公女殿下の家庭教師',
    '七つの魔剣が支配する',
    '世界最高の暗殺者、異世界貴族に転生する',
  ];

  for (final t in titles) {
    final res = await service.searchJapan(t);
    if (res != null) {
      print('[$t] -> Vol: ${res.latestVol} | Title: ${res.title} | URL: ${res.url}');
    } else {
      print('[$t] -> NOT FOUND');
    }
  }
}
