import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import '../../../core/theme/app_colors.dart';
import '../services/call_service.dart';

/// Full-screen call page.
/// mode: 'outgoing' | 'incoming' | 'connected'
class CallPage extends StatefulWidget {
  final CallInfo callInfo;

  const CallPage({super.key, required this.callInfo});

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  late CallInfo _info;
  StreamSubscription? _stateSub;
  CallState _state = CallService.instance.state;
  bool _isMuted = false;
  int _secondsElapsed = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _info = widget.callInfo;
    _state = CallService.instance.state;

    // Start ringback for outgoing calls (CallKit handles incoming ringtone)
    if (_state == CallState.outgoing) _startRingback();

    _stateSub = CallService.instance.onStateChanged.listen((s) {
      if (!mounted) return;
      final prevState = _state;
      setState(() {
        _state = s;
        _isMuted = CallService.instance.isMuted;
      });
      // Manage sounds on state change (CallKit handles incoming ringtone)
      if (s == CallState.outgoing) _startRingback();
      if (prevState == CallState.outgoing && s != CallState.outgoing) _stopRingback();

      if (s == CallState.connected && _timer == null) {
        _startTimer();
      }
      if (s == CallState.ended || s == CallState.idle) {
        _timer?.cancel();
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) Navigator.of(context).pop();
        });
      }
    });

    // If already connected when page opens, start timer
    if (_state == CallState.connected) _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _secondsElapsed++);
    });
  }

  // ─── Outgoing call: play a ring-back tone (short beeps) ───
  bool _isRingback = false;
  Timer? _ringbackTimer;

  void _startRingback() {
    if (_isRingback) return;
    _isRingback = true;
    // Play a short notification beep every 3 seconds to imitate ring-back tone
    _playRingbackBeep();
    _ringbackTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_isRingback) _playRingbackBeep();
    });
  }

  void _playRingbackBeep() {
    FlutterRingtonePlayer().playNotification(volume: 0.3, looping: false);
  }

  void _stopRingback() {
    if (!_isRingback) return;
    _isRingback = false;
    _ringbackTimer?.cancel();
    _ringbackTimer = null;
    FlutterRingtonePlayer().stop();
  }

  @override
  void dispose() {
    _stopRingback();
    _stateSub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  String get _statusText {
    switch (_state) {
      case CallState.outgoing:  return 'Вызов...';
      case CallState.incoming:  return 'Входящий звонок';
      case CallState.connected: return _formatDuration(_secondsElapsed);
      case CallState.ended:     return 'Звонок завершён';
      case CallState.idle:      return '';
    }
  }

  String _formatDuration(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF051515),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),

            // Avatar
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [AppColors.turquoise, AppColors.emerald],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.turquoise.withOpacity(0.35),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  _info.remoteName.isNotEmpty ? _info.remoteName[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Name
            Text(
              _info.remoteName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 8),

            // Status / timer
            Text(
              _statusText,
              style: TextStyle(
                color: _state == CallState.connected
                    ? AppColors.turquoise
                    : Colors.white.withOpacity(0.5),
                fontSize: 16,
              ),
            ),

            const Spacer(flex: 3),

            // Buttons
            if (_state == CallState.incoming)
              _buildIncomingButtons()
            else
              _buildActiveButtons(),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildIncomingButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Decline
        _CircleButton(
          icon: Icons.call_end,
          color: Colors.red,
          label: 'Отклонить',
          onTap: () => CallService.instance.rejectCall(),
        ),
        // Answer
        _CircleButton(
          icon: Icons.call,
          color: Colors.green,
          label: 'Ответить',
          onTap: () => CallService.instance.answerCall(),
        ),
      ],
    );
  }

  Widget _buildActiveButtons() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Mute
            _CircleButton(
              icon: _isMuted ? Icons.mic_off : Icons.mic,
              color: _isMuted ? Colors.white24 : Colors.white12,
              label: _isMuted ? 'Вкл. микр.' : 'Откл. микр.',
              onTap: () {
                CallService.instance.toggleMute();
                setState(() => _isMuted = CallService.instance.isMuted);
              },
            ),
            // Hang up
            _CircleButton(
              icon: Icons.call_end,
              color: Colors.red,
              label: 'Завершить',
              onTap: CallService.instance.hangUp,
            ),
            // Minimize
            _CircleButton(
              icon: Icons.keyboard_arrow_down,
              color: Colors.white12,
              label: 'Свернуть',
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _CircleButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
        ),
      ],
    );
  }
}
