import 'package:flutter/material.dart';
import '../models/book_item.dart';

class StatsCards extends StatelessWidget {
  final List<BookItem> books;
  final String activeFilter;
  final ValueChanged<String> onFilterSelected;

  const StatsCards({
    super.key,
    required this.books,
    required this.activeFilter,
    required this.onFilterSelected,
  });

  @override
  Widget build(BuildContext context) {
    int total = books.length;
    int hasUpdates = books.where((b) =>
        b.status == UpdateStatus.twUpdated ||
        b.status == UpdateStatus.jpUpdated ||
        b.status == UpdateStatus.bothUpdated).length;
    int twUpdates = books.where((b) =>
        b.status == UpdateStatus.twUpdated ||
        b.status == UpdateStatus.bothUpdated).length;
    int jpUpdates = books.where((b) =>
        b.status == UpdateStatus.jpUpdated ||
        b.status == UpdateStatus.bothUpdated).length;
    int pending = books.where((b) => b.status == UpdateStatus.unknown).length;
    int notFoundOrError = books.where((b) => b.status == UpdateStatus.notFound || b.status == UpdateStatus.error).length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          _buildCard(
            context,
            title: '全部',
            count: total,
            icon: Icons.menu_book,
            color: Colors.blueGrey,
            filterKey: 'all',
          ),
          const SizedBox(width: 8),
          _buildCard(
            context,
            title: '有更新',
            count: hasUpdates,
            icon: Icons.notifications_active,
            color: Colors.purple,
            filterKey: 'updates',
          ),
          const SizedBox(width: 8),
          _buildCard(
            context,
            title: '台版有更新',
            count: twUpdates,
            icon: Icons.local_fire_department,
            color: Colors.redAccent,
            filterKey: 'tw',
          ),
          const SizedBox(width: 8),
          _buildCard(
            context,
            title: '日版有更新',
            count: jpUpdates,
            icon: Icons.trending_up,
            color: Colors.amber.shade800,
            filterKey: 'jp',
          ),
          const SizedBox(width: 8),
          _buildCard(
            context,
            title: '待確認',
            count: pending,
            icon: Icons.hourglass_top,
            color: Colors.indigo,
            filterKey: 'pending',
          ),
          const SizedBox(width: 8),
          _buildCard(
            context,
            title: '查無資料',
            count: notFoundOrError,
            icon: Icons.help_outline,
            color: Colors.grey,
            filterKey: 'notFound',
          ),
        ],
      ),
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required String title,
    required int count,
    required IconData icon,
    required Color color,
    required String filterKey,
  }) {
    final isSelected = activeFilter == filterKey;
    final theme = Theme.of(context);

    return Expanded(
      child: InkWell(
        onTap: () => onFilterSelected(filterKey),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: 0.12)
                : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? color : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.75),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      count.toString(),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isSelected ? color : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
