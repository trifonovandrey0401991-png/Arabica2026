import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Виджет поля ввода сообщения — dark emerald стиль
class ChatInputField extends StatelessWidget {
  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final ValueChanged<String>? onChanged;

  static final Color _emerald = Color(0xFF1A4D4D);
  static final Color _night = Color(0xFF051515);

  const ChatInputField({
    super.key,
    required this.controller,
    required this.isSending,
    required this.onSend,
    required this.onAttach,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: _night.withOpacity(0.95),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
      ),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Кнопка прикрепления
            Container(
              margin: EdgeInsets.only(bottom: 4.h),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: IconButton(
                icon: Icon(Icons.attach_file_rounded, color: Colors.white.withOpacity(0.6)),
                onPressed: isSending ? null : onAttach,
                iconSize: 22,
                constraints: BoxConstraints(minWidth: 44, minHeight: 44),
              ),
            ),
            SizedBox(width: 10),
            // Поле ввода
            Expanded(
              child: Container(
                constraints: BoxConstraints(maxHeight: 120),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(22.r),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                ),
                child: TextField(
                  controller: controller,
                  enabled: !isSending,
                  maxLines: 4,
                  minLines: 1,
                  maxLength: 1000,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(
                    fontSize: 15.sp,
                    height: 1.4,
                    color: Colors.white.withOpacity(0.9),
                  ),
                  decoration: InputDecoration(
                    hintText: 'Сообщение...',
                    hintStyle: TextStyle(
                      color: Colors.white.withOpacity(0.3),
                      fontSize: 15.sp,
                    ),
                    counterText: '',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 18.w,
                      vertical: 12.h,
                    ),
                  ),
                  onChanged: onChanged,
                  onSubmitted: (_) => onSend(),
                ),
              ),
            ),
            SizedBox(width: 10),
            // Кнопка отправки
            Container(
              margin: EdgeInsets.only(bottom: 4.h),
              child: GestureDetector(
                onTap: isSending ? null : onSend,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: _emerald,
                    borderRadius: BorderRadius.circular(23.r),
                    border: Border.all(color: Colors.white.withOpacity(0.15)),
                  ),
                  child: Center(
                    child: isSending
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            Icons.send_rounded,
                            color: Colors.white.withOpacity(0.9),
                            size: 22,
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
