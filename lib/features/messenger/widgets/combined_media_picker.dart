import 'package:flutter/material.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import '../../../core/theme/app_colors.dart';
import 'sticker_picker.dart';
import 'gif_picker.dart';

/// Combined panel with 3 tabs: Emoji, Stickers, GIF.
class CombinedMediaPicker extends StatefulWidget {
  final TextEditingController textController;
  final Function(String stickerUrl) onStickerSelected;
  final Function(String gifUrl) onGifSelected;

  const CombinedMediaPicker({
    super.key,
    required this.textController,
    required this.onStickerSelected,
    required this.onGifSelected,
  });

  @override
  State<CombinedMediaPicker> createState() => _CombinedMediaPickerState();
}

class _CombinedMediaPickerState extends State<CombinedMediaPicker> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 320,
      color: AppColors.night,
      child: Column(
        children: [
          // Tab bar
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorColor: AppColors.turquoise,
              indicatorWeight: 2,
              labelColor: AppColors.turquoise,
              unselectedLabelColor: Colors.white.withOpacity(0.4),
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 13),
              dividerHeight: 0,
              tabs: const [
                Tab(icon: Icon(Icons.emoji_emotions_outlined, size: 20)),
                Tab(icon: Icon(Icons.sticky_note_2_outlined, size: 20)),
                Tab(text: 'GIF'),
              ],
            ),
          ),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Emoji tab
                EmojiPicker(
                  textEditingController: widget.textController,
                  onEmojiSelected: (category, emoji) {},
                  config: Config(
                    columns: 8,
                    emojiSizeMax: 28,
                    bgColor: AppColors.night,
                    iconColorSelected: AppColors.turquoise,
                    indicatorColor: AppColors.turquoise,
                    iconColor: Colors.white.withOpacity(0.3),
                    backspaceColor: Colors.white.withOpacity(0.5),
                    skinToneDialogBgColor: const Color(0xFF0A2A2A),
                    skinToneIndicatorColor: AppColors.turquoise,
                  ),
                ),

                // Stickers tab
                StickerPicker(onStickerSelected: widget.onStickerSelected),

                // GIF tab
                GifPicker(onGifSelected: widget.onGifSelected),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
