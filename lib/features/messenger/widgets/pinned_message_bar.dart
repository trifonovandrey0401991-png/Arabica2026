import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../models/message_model.dart';

/// Bar shown below AppBar when there's a pinned message.
/// Tap scrolls to the pinned message.
class PinnedMessageBar extends StatelessWidget {
  final MessengerMessage message;
  final VoidCallback onTap;
  final VoidCallback? onUnpin;

  const PinnedMessageBar({
    super.key,
    required this.message,
    required this.onTap,
    this.onUnpin,
  });

  @override
  Widget build(BuildContext context) {
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
            Container(
              width: 3,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.turquoise,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.push_pin, size: 14, color: AppColors.turquoise.withOpacity(0.7)),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Закреплено',
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
                child: Icon(Icons.close, size: 16, color: Colors.white.withOpacity(0.4)),
              ),
          ],
        ),
      ),
    );
  }
}
