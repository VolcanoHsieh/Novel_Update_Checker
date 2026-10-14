import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/book_item.dart';
import 'edit_dialog.dart';

class BookTable extends StatefulWidget {
  final List<BookItem> books;
  final ValueChanged<BookItem> onBookUpdated;
  final ValueChanged<BookItem> onSingleCheck;

  const BookTable({
    super.key,
    required this.books,
    required this.onBookUpdated,
    required this.onSingleCheck,
  });

  @override
  State<BookTable> createState() => _BookTableState();
}

class _BookTableState extends State<BookTable> {
  int _sortColumnIndex = 0;
  bool _sortAscending = true;

  void _sort<T>(Comparable<T> Function(BookItem b) getField, int columnIndex, bool ascending) {
    widget.books.sort((a, b) {
      if (!ascending) {
        final BookItem c = a;
        a = b;
        b = c;
      }
      final Comparable<T> aValue = getField(a);
      final Comparable<T> bValue = getField(b);
      return Comparable.compare(aValue, bValue);
    });
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
    });
  }

  Future<void> _openFolder(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.run('explorer.exe', [path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [path]);
      }
    } catch (_) {}
  }

  Future<void> _openUrl(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.books.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.library_books_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              '尚無符合篩選條件的書籍',
              style: TextStyle(fontSize: 15, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final theme = Theme.of(context);
    final dateFormat = DateFormat('MM/dd HH:mm');

    return Scrollbar(
      thumbVisibility: true,
      trackVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            sortColumnIndex: _sortColumnIndex,
            sortAscending: _sortAscending,
            headingRowColor: WidgetStateProperty.all(
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            ),
            columnSpacing: 18,
            horizontalMargin: 16,
            columns: [
              DataColumn(
                label: const Text('狀態', style: TextStyle(fontWeight: FontWeight.bold)),
                onSort: (index, asc) => _sort((b) => b.status.index, index, asc),
              ),
              DataColumn(
                label: const Text('書名 / 日文原名', style: TextStyle(fontWeight: FontWeight.bold)),
                onSort: (index, asc) => _sort((b) => b.title, index, asc),
              ),
              DataColumn(
                label: const Text('本地進度', style: TextStyle(fontWeight: FontWeight.bold)),
                numeric: true,
                onSort: (index, asc) => _sort((b) => b.localMaxVol, index, asc),
              ),
              DataColumn(
                label: const Text('台版最新 (Cache基準)', style: TextStyle(fontWeight: FontWeight.bold)),
                numeric: true,
                onSort: (index, asc) => _sort((b) => b.twLatestVol ?? 0.0, index, asc),
              ),
              DataColumn(
                label: const Text('日版最新', style: TextStyle(fontWeight: FontWeight.bold)),
                numeric: true,
                onSort: (index, asc) => _sort((b) => b.jpLatestVol ?? 0.0, index, asc),
              ),
              DataColumn(
                label: const Text('分類', style: TextStyle(fontWeight: FontWeight.bold)),
                onSort: (index, asc) => _sort((b) => b.category, index, asc),
              ),
              DataColumn(
                label: const Text('最後檢查', style: TextStyle(fontWeight: FontWeight.bold)),
                onSort: (index, asc) => _sort((b) => b.lastChecked?.millisecondsSinceEpoch ?? 0, index, asc),
              ),
              const DataColumn(
                label: Text('操作', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
            rows: widget.books.map((book) {
              final isTwUpdated = book.twLatestVol != null && book.twLatestVol! > book.twBaseline;
              final isJpUpdated = book.jpLatestVol != null && book.jpLatestVol! > book.jpBaseline;

              return DataRow(
                key: ValueKey(book.folderPath),
                cells: [
                  // 1. Status
                  DataCell(_buildStatusChip(book)),

                  // 2. Title & JP Title
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  book.title,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (book.manualOverride) ...[
                                const SizedBox(width: 4),
                                const Icon(Icons.lock_outline, size: 12, color: Colors.blueGrey),
                              ],
                            ],
                          ),
                          if (book.jpTitle != null && book.jpTitle!.isNotEmpty)
                            Text(
                              book.jpTitle!,
                              style: TextStyle(fontSize: 11, color: theme.hintColor),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ),

                  // 3. Local Max Volume
                  DataCell(
                    Text(
                      '第 ${BookItem.formatVol(book.localMaxVol)} 卷 (${book.localFilesCount}檔)',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),

                  // 4. TW Latest (evaluated against cache baseline!)
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          book.twLatestVol != null ? '第 ${BookItem.formatVol(book.twLatestVol!)} 卷' : '-',
                          style: TextStyle(
                            color: isTwUpdated ? Colors.redAccent : null,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (book.cachedTwVol != null && book.cachedTwVol != book.twLatestVol) ...[
                          const SizedBox(width: 4),
                          Text(
                            '(基:${BookItem.formatVol(book.cachedTwVol)})',
                            style: TextStyle(fontSize: 11, color: theme.hintColor),
                          ),
                        ],
                        if (isTwUpdated) ...[
                          const SizedBox(width: 2),
                          IconButton(
                            icon: const Icon(Icons.check_circle_outline, size: 15, color: Colors.green),
                            tooltip: '標記台版已跟進 (將基準設為第 ${BookItem.formatVol(book.twLatestVol!)} 卷)',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              book.cachedTwVol = book.twLatestVol;
                              book.refreshStatus();
                              widget.onBookUpdated(book);
                              setState(() {});
                            },
                          ),
                        ],
                        if (book.twUrl != null) ...[
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.open_in_new, size: 14, color: Colors.blue),
                            tooltip: '開啟 BookWalker 台版商品頁',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => _openUrl(book.twUrl),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // 5. JP Latest
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          book.jpLatestVol != null ? '第 ${BookItem.formatVol(book.jpLatestVol!)} 卷' : '-',
                          style: TextStyle(
                            color: isJpUpdated ? Colors.amber.shade800 : null,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (book.jpUrl != null) ...[
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.open_in_new, size: 14, color: Colors.orange),
                            tooltip: '開啟 BookWalker 日版商品頁',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => _openUrl(book.jpUrl),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // 6. Category
                  DataCell(
                    Text(
                      book.category.isNotEmpty ? book.category : '-',
                      style: TextStyle(fontSize: 12, color: theme.hintColor),
                    ),
                  ),

                  // 7. Last Checked
                  DataCell(
                    Text(
                      book.lastChecked != null ? dateFormat.format(book.lastChecked!) : '未檢查',
                      style: TextStyle(fontSize: 12, color: theme.hintColor),
                    ),
                  ),

                  // 8. Actions
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.refresh, size: 18),
                          tooltip: '線上重新檢查此書',
                          onPressed: () => widget.onSingleCheck(book),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          tooltip: '手動校對 / 編輯',
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (ctx) => EditDialog(
                                book: book,
                                onSave: (updated) {
                                  widget.onBookUpdated(updated);
                                  setState(() {});
                                },
                                onRequery: () => widget.onSingleCheck(book),
                              ),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.folder_open_outlined, size: 18),
                          tooltip: '在檔案總管開啟此資料夾',
                          onPressed: () => _openFolder(book.folderPath),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(BookItem book) {
    if (book.isIgnored) {
      return _chip('已忽略', Colors.grey, Colors.black54);
    }

    switch (book.status) {
      case UpdateStatus.checking:
        return const SizedBox(
          width: 76,
          child: Row(
            children: [
              SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 6),
              Text('查詢中', style: TextStyle(fontSize: 12)),
            ],
          ),
        );
      case UpdateStatus.bothUpdated:
        return _chip(
          '台+${BookItem.formatDiff(book.twLatestVol! - book.twBaseline)} 日+${BookItem.formatDiff(book.jpLatestVol! - book.jpBaseline)}',
          Colors.purple,
          Colors.purple.shade700,
        );
      case UpdateStatus.twUpdated:
        return _chip('台版+${BookItem.formatDiff(book.twLatestVol! - book.twBaseline)}', Colors.redAccent, Colors.red.shade900);
      case UpdateStatus.jpUpdated:
        return _chip('日版+${BookItem.formatDiff(book.jpLatestVol! - book.jpBaseline)}', Colors.amber.shade800, Colors.amber.shade900);
      case UpdateStatus.upToDate:
        return _chip('最新', Colors.green, Colors.green.shade900);
      case UpdateStatus.notFound:
        return _chip('查無資料', Colors.blueGrey, Colors.blueGrey.shade800);
      case UpdateStatus.error:
        return _chip('查詢失敗', Colors.red, Colors.red.shade900);
      case UpdateStatus.unknown:
        return _chip('待確認', Colors.indigo, Colors.indigo.shade800);
    }
  }

  Widget _chip(String label, Color bg, Color text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bg.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: text,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
