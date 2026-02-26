import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Кнопка «Загрузить ещё» с информацией о пагинации.
///
/// Показывает «Показано X из Y» и кнопку для загрузки следующей порции.
/// Используется внизу списков с серверной пагинацией.
class LoadMoreButton extends StatelessWidget {
  final int currentCount;
  final int totalCount;
  final bool isLoading;
  final VoidCallback onLoadMore;

  const LoadMoreButton({
    super.key,
    required this.currentCount,
    required this.totalCount,
    required this.isLoading,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    if (currentCount >= totalCount) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Column(
        children: [
          Text(
            'Показано $currentCount из $totalCount',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: isLoading ? null : onLoadMore,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.emeraldLight),
                foregroundColor: AppColors.gold,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.gold,
                      ),
                    )
                  : const Text('Загрузить ещё'),
            ),
          ),
        ],
      ),
    );
  }
}
