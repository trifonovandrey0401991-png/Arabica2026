import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';

/// Keys for SharedPreferences — global mute settings.
class MessengerMuteKeys {
  static const muteChats = 'messenger_mute_chats';
  static const muteGroups = 'messenger_mute_groups';
  static const muteChannels = 'messenger_mute_channels';

  /// Check if a conversation type is globally muted.
  static Future<bool> isTypeMuted(String conversationId) async {
    final prefs = await SharedPreferences.getInstance();
    if (conversationId.startsWith('private_')) {
      return prefs.getBool(muteChats) ?? false;
    }
    if (conversationId.startsWith('group_')) {
      return prefs.getBool(muteGroups) ?? false;
    }
    if (conversationId.startsWith('channel_')) {
      return prefs.getBool(muteChannels) ?? false;
    }
    return false;
  }
}

/// Notification settings page — 3 global mute toggles.
class MessengerNotificationSettingsPage extends StatefulWidget {
  const MessengerNotificationSettingsPage({super.key});

  @override
  State<MessengerNotificationSettingsPage> createState() => _MessengerNotificationSettingsPageState();
}

class _MessengerNotificationSettingsPageState extends State<MessengerNotificationSettingsPage> {
  bool _muteChats = false;
  bool _muteGroups = false;
  bool _muteChannels = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _muteChats = prefs.getBool(MessengerMuteKeys.muteChats) ?? false;
        _muteGroups = prefs.getBool(MessengerMuteKeys.muteGroups) ?? false;
        _muteChannels = prefs.getBool(MessengerMuteKeys.muteChannels) ?? false;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(
          'Уведомления',
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
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.only(bottom: 16, top: 8),
                  child: Text(
                    'Звук уведомлений',
                    style: TextStyle(
                      color: AppColors.turquoise.withOpacity(0.9),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),

                // Description
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Text(
                    'Уведомления будут приходить, но без звука и вибрации',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 13,
                    ),
                  ),
                ),

                // Chats toggle
                _buildMuteCard(
                  icon: Icons.chat_bubble_outline,
                  title: 'Личные чаты',
                  subtitle: 'Все приватные сообщения',
                  value: _muteChats,
                  onChanged: (v) {
                    setState(() => _muteChats = v);
                    _saveSetting(MessengerMuteKeys.muteChats, v);
                  },
                ),

                const SizedBox(height: 8),

                // Groups toggle
                _buildMuteCard(
                  icon: Icons.group_outlined,
                  title: 'Группы',
                  subtitle: 'Все групповые чаты',
                  value: _muteGroups,
                  onChanged: (v) {
                    setState(() => _muteGroups = v);
                    _saveSetting(MessengerMuteKeys.muteGroups, v);
                  },
                ),

                const SizedBox(height: 8),

                // Channels toggle
                _buildMuteCard(
                  icon: Icons.campaign_outlined,
                  title: 'Каналы',
                  subtitle: 'Все каналы',
                  value: _muteChannels,
                  onChanged: (v) {
                    setState(() => _muteChannels = v);
                    _saveSetting(MessengerMuteKeys.muteChannels, v);
                  },
                ),

                const SizedBox(height: 24),

                // Info
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 18, color: Colors.white.withOpacity(0.3)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Когда звук отключён, уведомления всё равно появляются в шторке, но без звука и вибрации. '
                          'Чтобы отключить звук для конкретного чата — зажмите его в списке.',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.35),
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildMuteCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
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
            color: value
                ? AppColors.turquoise.withOpacity(0.15)
                : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: value
                ? AppColors.turquoise
                : Colors.white.withOpacity(0.4),
            size: 22,
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          value ? 'Без звука' : subtitle,
          style: TextStyle(
            color: value
                ? AppColors.turquoise.withOpacity(0.7)
                : Colors.white.withOpacity(0.4),
            fontSize: 13,
          ),
        ),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.turquoise,
          activeTrackColor: AppColors.turquoise.withOpacity(0.3),
          inactiveThumbColor: Colors.white.withOpacity(0.5),
          inactiveTrackColor: Colors.white.withOpacity(0.1),
        ),
      ),
    );
  }
}
