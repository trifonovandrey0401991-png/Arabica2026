/// Model for a poll attached to a message.
class PollModel {
  final String id;
  final String conversationId;
  final String messageId;
  final String question;
  final List<String> options;
  final Map<String, List<String>> votes; // optionIndex → [phone1, phone2]
  final bool multipleChoice;
  final bool anonymous;
  final bool closed;

  PollModel({
    required this.id,
    required this.conversationId,
    required this.messageId,
    required this.question,
    required this.options,
    this.votes = const {},
    this.multipleChoice = false,
    this.anonymous = false,
    this.closed = false,
  });

  factory PollModel.fromJson(Map<String, dynamic> json) {
    // Parse options
    List<String> options = [];
    if (json['options'] is List) {
      options = (json['options'] as List).map((e) => e.toString()).toList();
    }

    // Parse votes: {"0": ["phone1"], "1": ["phone2"]}
    Map<String, List<String>> votes = {};
    if (json['votes'] is Map) {
      final raw = json['votes'] as Map;
      for (final entry in raw.entries) {
        final key = entry.key.toString();
        if (entry.value is List) {
          votes[key] = (entry.value as List).map((e) => e.toString()).toList();
        }
      }
    }

    return PollModel(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String? ?? '',
      messageId: json['message_id'] as String? ?? '',
      question: json['question'] as String? ?? '',
      options: options,
      votes: votes,
      multipleChoice: json['multiple_choice'] == true,
      anonymous: json['anonymous'] == true,
      closed: json['closed'] == true,
    );
  }

  /// Total number of votes across all options.
  int get totalVotes {
    int total = 0;
    for (final voters in votes.values) {
      total += voters.length;
    }
    return total;
  }

  /// Number of votes for a specific option index.
  int votesFor(int index) {
    return votes[index.toString()]?.length ?? 0;
  }

  /// Percentage of votes for a specific option (0.0 to 1.0).
  double percentFor(int index) {
    if (totalVotes == 0) return 0.0;
    return votesFor(index) / totalVotes;
  }

  /// Whether a specific phone has voted for a specific option.
  bool hasVoted(int index, String phone) {
    return votes[index.toString()]?.contains(phone) ?? false;
  }

  /// Whether a phone has voted at all.
  bool hasVotedAny(String phone) {
    for (final voters in votes.values) {
      if (voters.contains(phone)) return true;
    }
    return false;
  }
}
