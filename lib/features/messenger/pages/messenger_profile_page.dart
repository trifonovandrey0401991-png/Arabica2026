import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import '../services/messenger_service.dart';
import 'messenger_notification_settings_page.dart';

/// Результат редактирования профиля
class ProfileResult {
  final String? displayName;
  final String? avatarUrl;
  ProfileResult({this.displayName, this.avatarUrl});
}

/// Bottom sheet для редактирования профиля мессенджера
class MessengerProfilePage extends StatefulWidget {
  final String userPhone;
  final String userName;
  final bool embeddedMode;
  final void Function(ProfileResult)? onProfileChanged;

  const MessengerProfilePage({
    super.key,
    required this.userPhone,
    required this.userName,
    this.embeddedMode = false,
    this.onProfileChanged,
  });

  @override
  State<MessengerProfilePage> createState() => _MessengerProfilePageState();
}

class _MessengerProfilePageState extends State<MessengerProfilePage> {
  final _nameController = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;
  String? _avatarUrl;
  File? _newAvatarFile;
  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await MessengerService.getProfile(widget.userPhone);
      if (mounted) {
        setState(() {
          if (profile != null) {
            _nameController.text = profile['display_name'] as String? ?? '';
            _avatarUrl = profile['avatar_url'] as String?;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAvatar() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Icon(Icons.camera_alt, color: AppColors.turquoise.withOpacity(0.8)),
                title: Text('Камера', style: TextStyle(color: Colors.white.withOpacity(0.9))),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: Icon(Icons.photo_library, color: AppColors.turquoise.withOpacity(0.8)),
                title: Text('Галерея', style: TextStyle(color: Colors.white.withOpacity(0.9))),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 75,
        maxWidth: 800,
        maxHeight: 800,
      );
      if (picked != null && mounted) {
        setState(() => _newAvatarFile = File(picked.path));
      }
    } catch (e) {
      Logger.error('Failed to pick avatar: $e');
    }
  }

  Future<void> _save() async {
    if (mounted) setState(() => _isSaving = true);

    try {
      String? uploadedAvatarUrl;

      // Upload new avatar if picked
      if (_newAvatarFile != null) {
        uploadedAvatarUrl = await MessengerService.uploadMedia(_newAvatarFile!);
      }

      final displayName = _nameController.text.trim();

      final result = await MessengerService.updateProfile(
        phone: widget.userPhone,
        displayName: displayName.isNotEmpty ? displayName : null,
        avatarUrl: uploadedAvatarUrl,
      );

      if (result != null && mounted) {
        // Update SharedPreferences if name changed
        if (displayName.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_name', displayName);
        }

        if (!mounted) return;

        final profileResult = ProfileResult(
          displayName: displayName.isNotEmpty ? displayName : null,
          avatarUrl: uploadedAvatarUrl ?? _avatarUrl,
        );

        if (widget.embeddedMode) {
          // In embedded mode, notify parent via callback + show snackbar
          widget.onProfileChanged?.call(profileResult);
          if (mounted) {
            setState(() => _isSaving = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Профиль сохранён'),
                backgroundColor: AppColors.emerald,
              ),
            );
          }
        } else {
          Navigator.pop(context, profileResult);
        }
      } else if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка сохранения профиля')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: !widget.embeddedMode,
        title: Text(
          'Профиль',
          style: TextStyle(color: Colors.white.withOpacity(0.95)),
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.emerald.withOpacity(0.3),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.turquoise, strokeWidth: 2.5))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const SizedBox(height: 16),

                  // Avatar
                  GestureDetector(
                    onTap: _pickAvatar,
                    child: Stack(
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: (_newAvatarFile == null && _avatarUrl == null)
                                ? const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [AppColors.turquoise, AppColors.emerald],
                                  )
                                : null,
                            border: Border.all(color: Colors.white.withOpacity(0.2), width: 2),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _buildAvatarContent(),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.turquoise,
                              border: Border.all(color: AppColors.night, width: 2),
                            ),
                            child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Name field
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: TextField(
                      controller: _nameController,
                      style: TextStyle(color: Colors.white.withOpacity(0.9)),
                      decoration: InputDecoration(
                        labelText: 'Отображаемое имя',
                        labelStyle: TextStyle(color: AppColors.turquoise.withOpacity(0.7)),
                        hintText: widget.userName,
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        prefixIcon: Icon(Icons.person_outline, color: AppColors.turquoise.withOpacity(0.5)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Если оставить пустым — будет использоваться имя при регистрации',
                      style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.3)),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Phone (read-only)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withOpacity(0.06)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.phone_outlined, color: Colors.white.withOpacity(0.3), size: 20),
                        const SizedBox(width: 12),
                        Text(
                          widget.userPhone,
                          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 15),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Save button
                  Container(
                    width: double.infinity,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.turquoise, AppColors.emerald],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.turquoise.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text(
                              'Сохранить',
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                    ),
                  ),

                  const SizedBox(height: 32),
                  Divider(color: Colors.white.withOpacity(0.08)),
                  const SizedBox(height: 8),

                  // Notifications settings
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.turquoise.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.notifications_outlined, color: AppColors.turquoise, size: 22),
                      ),
                      title: Text(
                        'Уведомления',
                        style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(
                        'Настройки звука',
                        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13),
                      ),
                      trailing: Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3)),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const MessengerNotificationSettingsPage()),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildAvatarContent() {
    final letter = widget.userName.isNotEmpty ? widget.userName[0].toUpperCase() : '?';

    // New file picked — show it
    if (_newAvatarFile != null) {
      return Image.file(_newAvatarFile!, fit: BoxFit.cover, width: 100, height: 100);
    }

    // Existing avatar from server
    if (_avatarUrl != null && _avatarUrl!.isNotEmpty) {
      final url = _avatarUrl!.startsWith('http')
          ? _avatarUrl!
          : '${ApiConstants.serverUrl}$_avatarUrl';
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        width: 100,
        height: 100,
        placeholder: (_, __) => Center(
          child: Text(letter, style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold)),
        ),
        errorWidget: (_, __, ___) => Center(
          child: Text(letter, style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold)),
        ),
      );
    }

    // No avatar — show letter
    return Center(
      child: Text(letter, style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold)),
    );
  }
}
