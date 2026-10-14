import 'package:flutter/material.dart';
import '../models/book_item.dart';
import '../services/bangumi_service.dart';

class EditDialog extends StatefulWidget {
  final BookItem book;
  final ValueChanged<BookItem> onSave;
  final VoidCallback onRequery;

  const EditDialog({
    super.key,
    required this.book,
    required this.onSave,
    required this.onRequery,
  });

  @override
  State<EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<EditDialog> {
  late TextEditingController _titleCtrl;
  late TextEditingController _jpTitleCtrl;
  late TextEditingController _localVolCtrl;
  late TextEditingController _cachedTwVolCtrl;
  late TextEditingController _twVolCtrl;
  late TextEditingController _twUrlCtrl;
  late TextEditingController _jpVolCtrl;
  late TextEditingController _jpUrlCtrl;
  late bool _isCompleted;
  late bool _isIgnored;
  bool _isAutoDetecting = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.book.title);
    _jpTitleCtrl = TextEditingController(text: widget.book.jpTitle ?? '');
    _localVolCtrl = TextEditingController(text: BookItem.formatVol(widget.book.localMaxVol));
    _cachedTwVolCtrl = TextEditingController(text: BookItem.formatVol(widget.book.cachedTwVol ?? widget.book.localMaxVol));
    _twVolCtrl = TextEditingController(text: widget.book.twLatestVol != null ? BookItem.formatVol(widget.book.twLatestVol!) : '');
    _twUrlCtrl = TextEditingController(text: widget.book.twUrl ?? '');
    _jpVolCtrl = TextEditingController(text: widget.book.jpLatestVol != null ? BookItem.formatVol(widget.book.jpLatestVol!) : '');
    _jpUrlCtrl = TextEditingController(text: widget.book.jpUrl ?? '');
    _isCompleted = widget.book.isCompleted;
    _isIgnored = widget.book.isIgnored;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _jpTitleCtrl.dispose();
    _localVolCtrl.dispose();
    _cachedTwVolCtrl.dispose();
    _twVolCtrl.dispose();
    _twUrlCtrl.dispose();
    _jpVolCtrl.dispose();
    _jpUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _autoDetectJapaneseTitle() async {
    setState(() => _isAutoDetecting = true);
    final bgmSvc = BangumiService();
    final res = await bgmSvc.searchNovel(_titleCtrl.text.trim());
    setState(() => _isAutoDetecting = false);

    if (res != null && res.name.isNotEmpty) {
      setState(() {
        _jpTitleCtrl.text = res.name;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已識別日文原名：${res.name}')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('線上未找到匹配的日文書名，請手動輸入')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.edit_note, color: Colors.blueAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '書籍資訊校對 - ${widget.book.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: '中文書名',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.book),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _jpTitleCtrl,
                      decoration: const InputDecoration(
                        labelText: '日文原名 (校正後將鎖定，刷新不被覆蓋)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.translate),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    icon: _isAutoDetecting
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_fix_high, size: 16),
                    label: const Text('自動識別'),
                    onPressed: _isAutoDetecting ? null : _autoDetectJapaneseTitle,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _localVolCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '本地已擁有最高卷數',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.folder),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _cachedTwVolCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '台版追更基準 (Cache記錄)',
                        helperText: '「台版有更新」以此卷數為準',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.storage),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.done_all, size: 18),
                          tooltip: '將基準設為台版最新卷數',
                          onPressed: () {
                            if (_twVolCtrl.text.isNotEmpty) {
                              _cachedTwVolCtrl.text = _twVolCtrl.text;
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _twVolCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '台版線上最新卷數',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _jpVolCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '日版線上最新卷數',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _twUrlCtrl,
                decoration: const InputDecoration(
                  labelText: '台版書籍頁面網址',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.link),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _jpUrlCtrl,
                decoration: const InputDecoration(
                  labelText: '日版書籍頁面網址',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.link),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Checkbox(
                    value: _isCompleted,
                    onChanged: (val) => setState(() => _isCompleted = val ?? false),
                  ),
                  const Text('已完結'),
                  const SizedBox(width: 20),
                  Checkbox(
                    value: _isIgnored,
                    onChanged: (val) => setState(() => _isIgnored = val ?? false),
                  ),
                  const Text('忽略此書 (不追更)'),
                ],
              ),
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        OutlinedButton.icon(
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('重新線上查詢此書'),
          onPressed: () {
            // Apply current manual title & URLs first
            if (_jpTitleCtrl.text.trim().isNotEmpty) {
              widget.book.jpTitle = _jpTitleCtrl.text.trim();
              widget.book.manualOverride = true;
            }
            if (_twUrlCtrl.text.trim().isNotEmpty) {
              widget.book.twUrl = _twUrlCtrl.text.trim();
              widget.book.manualOverride = true;
            }
            if (_jpUrlCtrl.text.trim().isNotEmpty) {
              widget.book.jpUrl = _jpUrlCtrl.text.trim();
              widget.book.manualOverride = true;
            }
            Navigator.of(context).pop();
            widget.onRequery();
          },
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                widget.book.jpTitle = _jpTitleCtrl.text.trim();
                widget.book.localMaxVol = double.tryParse(_localVolCtrl.text.trim()) ?? widget.book.localMaxVol;
                widget.book.cachedTwVol = double.tryParse(_cachedTwVolCtrl.text.trim());
                widget.book.twLatestVol = double.tryParse(_twVolCtrl.text.trim());
                widget.book.twUrl = _twUrlCtrl.text.trim().isNotEmpty ? _twUrlCtrl.text.trim() : null;
                widget.book.jpLatestVol = double.tryParse(_jpVolCtrl.text.trim());
                widget.book.jpUrl = _jpUrlCtrl.text.trim().isNotEmpty ? _jpUrlCtrl.text.trim() : null;
                widget.book.isCompleted = _isCompleted;
                widget.book.isIgnored = _isIgnored;
                widget.book.manualOverride = true; // Lock manual edits
                widget.book.refreshStatus();

                widget.onSave(widget.book);
                Navigator.of(context).pop();
              },
              child: const Text('儲存修改'),
            ),
          ],
        ),
      ],
    );
  }
}
