import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class MessageInputBar extends StatefulWidget {
  final Function(String text) onSendText;
  final VoidCallback? onAttachmentTap;
  final VoidCallback? onMediaPickerTap;
  final VoidCallback? onVoiceStart;
  final VoidCallback? onVoiceSend;
  final VoidCallback? onVoiceCancel;
  final VoidCallback? onVideoNote;
  final Function(String)? onTyping;
  final String? replyToText;
  final VoidCallback? onCancelReply;
  final bool isRecording;
  final int recordingSeconds;
  final TextEditingController? textController;
  final bool isEditing;
  final VoidCallback? onCancelEdit;

  const MessageInputBar({
    super.key,
    required this.onSendText,
    this.onAttachmentTap,
    this.onMediaPickerTap,
    this.onVoiceStart,
    this.onVoiceSend,
    this.onVoiceCancel,
    this.onVideoNote,
    this.onTyping,
    this.replyToText,
    this.onCancelReply,
    this.isRecording = false,
    this.recordingSeconds = 0,
    this.textController,
    this.isEditing = false,
    this.onCancelEdit,
  });

  @override
  State<MessageInputBar> createState() => _MessageInputBarState();
}

class _MessageInputBarState extends State<MessageInputBar> {
  TextEditingController? _ownController;
  bool _hasText = false;
  bool _cameraMode = false; // long-press mic → camera icon for video notes

  TextEditingController get _controller =>
      widget.textController ?? (_ownController ??= TextEditingController());

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(MessageInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.textController != widget.textController) {
      oldWidget.textController?.removeListener(_onTextChanged);
      _controller.addListener(_onTextChanged);
    }
  }

  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
    if (hasText) widget.onTyping?.call(_controller.text);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _ownController?.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSendText(text);
    _controller.clear();
    setState(() => _hasText = false);
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Edit mode preview
        if (widget.isEditing && !widget.isRecording)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
            ),
            child: Row(
              children: [
                Container(width: 3, height: 30, decoration: BoxDecoration(
                  color: AppColors.gold,
                  borderRadius: BorderRadius.circular(2),
                )),
                const SizedBox(width: 8),
                Icon(Icons.edit, size: 16, color: AppColors.gold.withOpacity(0.7)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Редактирование',
                    style: TextStyle(fontSize: 13, color: AppColors.gold.withOpacity(0.8)),
                  ),
                ),
                GestureDetector(
                  onTap: widget.onCancelEdit,
                  child: Icon(Icons.close, size: 18, color: Colors.white.withOpacity(0.4)),
                ),
              ],
            ),
          ),
        // Reply preview
        if (widget.replyToText != null && !widget.isRecording && !widget.isEditing)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
            ),
            child: Row(
              children: [
                Container(width: 3, height: 30, decoration: BoxDecoration(
                  color: AppColors.turquoise,
                  borderRadius: BorderRadius.circular(2),
                )),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.replyToText!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.5)),
                  ),
                ),
                GestureDetector(
                  onTap: widget.onCancelReply,
                  child: Icon(Icons.close, size: 18, color: Colors.white.withOpacity(0.4)),
                ),
              ],
            ),
          ),

        // Input bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.night,
            border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
          ),
          child: SafeArea(
            child: widget.isRecording ? _buildRecordingRow() : _buildNormalRow(),
          ),
        ),
      ],
    );
  }

  /// Обычный режим: [+] [текст] [media/mic] или [+] [текст] [send]
  Widget _buildNormalRow() {
    return Row(
      children: [
        // "+" button — attachments
        _buildPlusButton(),
        const SizedBox(width: 6),

        // Text input
        Expanded(
          child: Container(
            constraints: const BoxConstraints(maxHeight: 120),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: TextField(
              controller: _controller,
              maxLines: null,
              textInputAction: TextInputAction.newline,
              enableSuggestions: true,
              autocorrect: true,
              spellCheckConfiguration: const SpellCheckConfiguration(),
              style: TextStyle(fontSize: 15, color: Colors.white.withOpacity(0.9), height: 1.4),
              decoration: InputDecoration(
                hintText: 'Сообщение...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                isDense: true,
              ),
            ),
          ),
        ),

        const SizedBox(width: 6),

        // Right side: send or media+mic
        if (_hasText)
          widget.isEditing ? _buildEditConfirmButton() : _buildSendButton()
        else ...[
          _buildIconButton(Icons.emoji_emotions_outlined, widget.onMediaPickerTap),
          const SizedBox(width: 2),
          _buildMicButton(),
        ],
      ],
    );
  }

  Widget _buildPlusButton() {
    return GestureDetector(
      onTap: widget.onAttachmentTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.turquoise.withOpacity(0.15),
          border: Border.all(color: AppColors.turquoise.withOpacity(0.3)),
        ),
        child: const Icon(Icons.add, color: AppColors.turquoise, size: 22),
      ),
    );
  }

  /// Режим записи: [X отмена] [индикатор записи] [✓ отправить]
  Widget _buildRecordingRow() {
    return Row(
      children: [
        // Кнопка отмены
        GestureDetector(
          onTap: widget.onVoiceCancel,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.08),
              border: Border.all(color: Colors.white.withOpacity(0.15)),
            ),
            child: Icon(Icons.close, color: Colors.white.withOpacity(0.6), size: 22),
          ),
        ),

        const SizedBox(width: 8),

        // Индикатор записи
        Expanded(
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.1),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.error.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const _PulsingDot(),
                const SizedBox(width: 10),
                Text(
                  'Запись',
                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
                ),
                const Spacer(),
                Text(
                  _formatDuration(widget.recordingSeconds),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(width: 8),

        // Кнопка отправки
        GestureDetector(
          onTap: widget.onVoiceSend,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [AppColors.turquoise, AppColors.emerald],
              ),
              boxShadow: [
                BoxShadow(color: AppColors.turquoise.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
          ),
        ),
      ],
    );
  }

  Widget _buildSendButton() {
    return GestureDetector(
      onTap: _handleSend,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [AppColors.turquoise, AppColors.emerald],
          ),
          boxShadow: [
            BoxShadow(color: AppColors.turquoise.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _buildEditConfirmButton() {
    return GestureDetector(
      onTap: _handleSend,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [AppColors.gold, AppColors.gold],
          ),
          boxShadow: [
            BoxShadow(color: AppColors.gold.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: const Icon(Icons.check_rounded, color: Colors.white, size: 22),
      ),
    );
  }

  Widget _buildMicButton() {
    return GestureDetector(
      onTap: () {
        if (_cameraMode) {
          widget.onVideoNote?.call();
        } else {
          widget.onVoiceStart?.call();
        }
      },
      onLongPress: () {
        setState(() => _cameraMode = !_cameraMode);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _cameraMode ? AppColors.turquoise : AppColors.emerald,
          border: Border.all(color: Colors.white.withOpacity(0.15)),
        ),
        child: Icon(
          _cameraMode ? Icons.videocam_rounded : Icons.mic_rounded,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildIconButton(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.06),
        ),
        child: Icon(icon, color: Colors.white.withOpacity(0.45), size: 20),
      ),
    );
  }
}

/// Пульсирующая красная точка для индикатора записи
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.error.withOpacity(0.5 + _controller.value * 0.5),
        ),
      ),
    );
  }
}
