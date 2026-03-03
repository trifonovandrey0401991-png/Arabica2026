import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../models/poll_model.dart';

/// Renders a poll inside a message bubble.
class PollBubble extends StatelessWidget {
  final PollModel poll;
  final String userPhone;
  final bool isMine;
  final void Function(int optionIndex)? onVote;

  const PollBubble({
    super.key,
    required this.poll,
    required this.userPhone,
    required this.isMine,
    this.onVote,
  });

  @override
  Widget build(BuildContext context) {
    final hasVoted = poll.hasVotedAny(userPhone);

    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Question
          Text(
            poll.question,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.95),
            ),
          ),
          const SizedBox(height: 10),

          // Options
          ...List.generate(poll.options.length, (index) {
            final optionText = poll.options[index];
            final votedThis = poll.hasVoted(index, userPhone);
            final percent = poll.percentFor(index);
            final voteCount = poll.votesFor(index);

            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: GestureDetector(
                onTap: (poll.closed || (hasVoted && !poll.multipleChoice))
                    ? null
                    : () => onVote?.call(index),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: votedThis
                          ? AppColors.turquoise
                          : Colors.white.withOpacity(0.15),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      // Progress bar background
                      if (hasVoted || poll.closed)
                        FractionallySizedBox(
                          widthFactor: percent,
                          child: Container(
                            height: 40,
                            decoration: BoxDecoration(
                              color: votedThis
                                  ? AppColors.turquoise.withOpacity(0.3)
                                  : Colors.white.withOpacity(0.06),
                            ),
                          ),
                        ),
                      // Option text + percentage
                      Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          children: [
                            if (votedThis)
                              const Padding(
                                padding: EdgeInsets.only(right: 6),
                                child: Icon(Icons.check_circle, color: AppColors.turquoise, size: 16),
                              ),
                            Expanded(
                              child: Text(
                                optionText,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white.withOpacity(0.85),
                                  fontWeight: votedThis ? FontWeight.w600 : FontWeight.normal,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (hasVoted || poll.closed)
                              Text(
                                '${(percent * 100).round()}%',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white.withOpacity(0.5),
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
          }),

          // Footer: total votes + closed badge
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                '${poll.totalVotes} голосов',
                style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.4)),
              ),
              if (poll.anonymous) ...[
                const SizedBox(width: 8),
                Text(
                  'анонимный',
                  style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.3)),
                ),
              ],
              if (poll.closed) ...[
                const SizedBox(width: 8),
                Text(
                  'завершён',
                  style: TextStyle(fontSize: 11, color: AppColors.error.withOpacity(0.7)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
