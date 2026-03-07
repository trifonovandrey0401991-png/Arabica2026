import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../models/message_model.dart';

/// Bar shown below AppBar when there are pinned messages.
/// Tap scrolls to the current pinned message.
/// Up/down arrows navigate between multiple pins.
class PinnedMessageBar extends StatelessWidget {
  final List<MessengerMessage> messages;
  final int currentIndex;
  final VoidCallback onTap;
  final VoidCallback? onUnpin;
  final VoidCallback? onNext;
  final VoidCallback? onPrev;

  const PinnedMessageBar({
    super.key,
    required this.messages,
    this.currentIndex = 0,
    required this.onTap,
    this.onUnpin,
    this.onNext,
    this.onPrev,
  });

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) return const SizedBox.shrink();
    final message = messages[currentIndex];
    final hasMultiple = messages.length > 1;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.emerald.withOpacity(0.15),
          border: Border(
            bottom: BorderSide(color: AppColors.turquoise.withOpacity(0.3)),
          ),
        ),
        child: Row(
          children: [
            // Vertical indicator with segments for multiple pins
            if (hasMultiple)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(messages.length.clamp(0, 5), (i) {
                  final isActive = i == currentIndex;
                  return Container(
                    width: 3,
                    height: 28 / messages.length.clamp(1, 5),
                    margin: const EdgeInsets.symmetric(vertical: 0.5),
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.turquoise
                          : AppColors.turquoise.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  );
                }),
              )
            else
              Container(
                width: 3,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.turquoise,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            const SizedBox(width: 8),
            // Navigation arrows for multiple pins
            if (hasMultiple)
              GestureDetector(
                onTap: onNext,
                child: Icon(Icons.keyboard_arrow_up, size: 18,
                    color: AppColors.turquoise.withOpacity(0.7)),
              ),
            if (!hasMultiple)
              Icon(Icons.push_pin, size: 14,
                  color: AppColors.turquoise.withOpacity(0.7)),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    hasMultiple
                        ? 'Закреплено ${currentIndex + 1} из ${messages.length}'
                        : 'Закреплено',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.turquoise.withOpacity(0.8),
                    ),
                  ),
                  Text(
                    message.preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
            if (onUnpin != null)
              GestureDetector(
                onTap: onUnpin,
                child: Icon(Icons.close, size: 16,
                    color: Colors.white.withOpacity(0.4)),
              ),
          ],
        ),
      ),
    );
  }
}
