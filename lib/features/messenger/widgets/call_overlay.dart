import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/firebase_service.dart';
import '../pages/call_page.dart';
import '../services/call_service.dart';

/// Floating mini-bar displayed on top of all screens during an active call.
/// Insert via [CallOverlayManager.show] from main.dart's MaterialApp builder.
class CallOverlayBar extends StatefulWidget {
  const CallOverlayBar({super.key});

  @override
  State<CallOverlayBar> createState() => _CallOverlayBarState();
}

class _CallOverlayBarState extends State<CallOverlayBar> {
  int _secondsElapsed = 0;
  Timer? _timer;
  StreamSubscription? _stateSub;
  CallState _callState = CallService.instance.state;

  @override
  void initState() {
    super.initState();
    _callState = CallService.instance.state;

    _stateSub = CallService.instance.onStateChanged.listen((s) {
      if (!mounted) return;
      setState(() => _callState = s);
      if (s == CallState.connected && _timer == null) {
        _startTimer();
      }
      if (s == CallState.idle || s == CallState.ended) {
        _timer?.cancel();
        _timer = null;
        _secondsElapsed = 0;
      }
    });

    if (_callState == CallState.connected) _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _secondsElapsed++);
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  String get _statusLabel {
    switch (_callState) {
      case CallState.outgoing:  return 'Вызов...';
      case CallState.incoming:  return 'Входящий звонок';
      case CallState.connected: return _formatDuration(_secondsElapsed);
      default:                  return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final call = CallService.instance.currentCall;
    if (call == null) return const SizedBox.shrink();

    return Positioned(
      top: MediaQuery.of(context).padding.top + 4,
      left: 12,
      right: 12,
      child: GestureDetector(
        onTap: () {
          // Tap to re-open full call screen (use global navigatorKey — overlay is outside Navigator tree)
          final nav = FirebaseService.navigatorKey.currentState;
          if (nav != null) {
            nav.push(MaterialPageRoute(
              builder: (_) => CallPage(callInfo: call),
            ));
          }
        },
        child: Material(
          color: Colors.transparent,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.emerald, AppColors.turquoise],
              ),
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: AppColors.turquoise.withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.call, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        call.remoteName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _statusLabel,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.75),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                // End call button
                GestureDetector(
                  onTap: () => CallService.instance.hangUp(),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red,
                    ),
                    child: const Icon(Icons.call_end, color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
