import 'dart:async';
import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/utils/logger.dart';
import 'messenger_ws_service.dart';

// ──────────────────────────────────────────────────────────────
// Call State
// ──────────────────────────────────────────────────────────────

enum CallState { idle, outgoing, incoming, connected, ended }

class CallInfo {
  final String callId;
  final String remotePhone;
  final String remoteName;
  final bool isOutgoing;
  final DateTime startedAt;

  CallInfo({
    required this.callId,
    required this.remotePhone,
    required this.remoteName,
    required this.isOutgoing,
    required this.startedAt,
  });
}

// ──────────────────────────────────────────────────────────────
// CallService — manages WebRTC peer connection and call lifecycle
// ──────────────────────────────────────────────────────────────

class CallService {
  CallService._();
  static final CallService instance = CallService._();

  // STUN servers — Google's free public servers
  static const _rtcConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  RTCPeerConnection? _pc;
  MediaStream? _localStream;

  CallState _state = CallState.idle;
  CallInfo? _currentCall;
  String? _myPhone;
  String? _myName;
  String? _conversationId;

  // Buffered ICE candidates received before peer connection was ready
  final List<MsgrCallIceCandidate> _pendingCandidates = [];

  // Offer SDP received with incoming call (stored for use in answerCall)
  String? _pendingOfferSdp;

  // Subscriptions to WS events
  StreamSubscription? _subIncoming;
  StreamSubscription? _subAnswered;
  StreamSubscription? _subRejected;
  StreamSubscription? _subIce;
  StreamSubscription? _subHangup;

  // Timer for unanswered outgoing calls (ring timeout)
  Timer? _ringTimer;

  // Timer for ICE disconnect grace period
  Timer? _iceDisconnectTimer;

  // Flag to suppress actionCallEnded triggered by our own endAllCalls()
  bool _dismissingCallKit = false;

  // ─── Public state ───
  CallState get state => _state;
  CallInfo? get currentCall => _currentCall;
  bool get isActive => _state != CallState.idle && _state != CallState.ended;
  bool get isMuted => _isMuted;
  bool _isMuted = false;

  // State change notifier — UI subscribes to this
  final _stateController = StreamController<CallState>.broadcast();
  Stream<CallState> get onStateChanged => _stateController.stream;

  // CallKit event subscription
  StreamSubscription? _callkitSub;

  // ─── Initialisation ───

  void init(String myPhone, String myName) {
    _myPhone = myPhone;
    _myName  = myName;
    Logger.debug('📞 CallService.init: phone=$myPhone, name=$myName');
    _subscribeToWsEvents();
    _subscribeToCallKitEvents();
    // Request full-screen intent permission for Android 14+
    FlutterCallkitIncoming.requestFullIntentPermission();
  }

  void _subscribeToWsEvents() {
    // Cancel existing subscriptions to avoid leaks on repeated init() calls
    _subIncoming?.cancel();
    _subAnswered?.cancel();
    _subRejected?.cancel();
    _subIce?.cancel();
    _subHangup?.cancel();

    final ws = MessengerWsService.instance;

    _subIncoming = ws.onCallIncoming.listen((e) {
      Logger.debug('📞 CallService: received call_incoming event, callId=${e.callId}, state=$_state');
      _pendingOfferSdp = e.offerSdp;
      _onCallIncoming(e);
    });
    _subAnswered = ws.onCallAnswered.listen(_onCallAnswered);
    _subRejected = ws.onCallRejected.listen(_onCallRejected);
    _subIce      = ws.onCallIceCandidate.listen(_onCallIceCandidate);
    _subHangup   = ws.onCallHangup.listen(_onCallHangup);
  }

  void _subscribeToCallKitEvents() {
    _callkitSub?.cancel();
    _callkitSub = FlutterCallkitIncoming.onEvent.listen((CallEvent? event) {
      if (event == null) return;
      Logger.debug('📞 CallKit event: ${event.event}');
      switch (event.event) {
        case Event.actionCallAccept:
          // User pressed "Answer" on system call screen
          _onCallKitAccept(event);
          break;
        case Event.actionCallDecline:
          // User pressed "Decline" on system call screen
          _onCallKitDecline(event);
          break;
        case Event.actionCallEnded:
          // Ignore if WE dismissed CallKit (endAllCalls in answerCall/cleanup)
          if (_dismissingCallKit) {
            _dismissingCallKit = false;
            break;
          }
          // Call ended from system UI by user
          if (_state == CallState.connected || _state == CallState.outgoing) {
            hangUp();
          }
          break;
        case Event.actionCallTimeout:
          // Missed call (ring timeout)
          if (_state == CallState.incoming) {
            rejectCall();
          }
          break;
        default:
          break;
      }
    });
  }

  void _onCallKitAccept(CallEvent event) async {
    final extra = event.body['extra'] as Map<String, dynamic>?;
    if (_state == CallState.incoming && _currentCall != null) {
      // Already set up via WS — just answer
      await ensureWsConnected();
      answerCall();
    } else if (extra != null && _myPhone != null) {
      // App was in background but alive — restore call, wait for WS, then answer
      final callId = extra['callId'] as String? ?? '';
      final callerPhone = extra['callerPhone'] as String? ?? '';
      final callerName = extra['callerName'] as String? ?? '';
      final offerSdp = extra['offerSdp'] as String? ?? '';
      if (callId.isNotEmpty && callerPhone.isNotEmpty && offerSdp.isNotEmpty) {
        // Reconnect WS first (was likely frozen in background)
        MessengerWsService.instance.reconnectIfNeeded();
        handleFcmIncomingCall(
          callId: callId,
          callerPhone: callerPhone,
          callerName: callerName,
          offerSdp: offerSdp,
        );
        // Wait for WS to be ready before answering
        await ensureWsConnected();
        // Small delay so _GlobalCallListener can show CallPage
        await Future.delayed(const Duration(milliseconds: 500));
        answerCall();
      }
    } else if (extra != null) {
      // Cold start — CallService not initialized yet, save for after PIN entry
      Logger.debug('📞 CallKit Accept: cold start, saving pending acceptance');
      _savePendingAcceptedCall(extra);
    }
  }

  /// Wait for WS to be connected (up to 5 seconds)
  Future<bool> ensureWsConnected() async {
    final ws = MessengerWsService.instance;
    if (ws.isConnected) return true;
    ws.reconnectIfNeeded();
    // Poll for connection up to 5 seconds
    for (int i = 0; i < 25; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (ws.isConnected) return true;
    }
    Logger.error('📞 CallService: WS not connected after 5s timeout');
    return false;
  }

  void _savePendingAcceptedCall(Map<String, dynamic> extra) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_incoming_call', jsonEncode(extra));
      await prefs.setBool('pending_call_accepted', true);
    } catch (_) {}
  }

  void _onCallKitDecline(CallEvent event) {
    if (_state == CallState.incoming && _currentCall != null) {
      rejectCall();
    } else {
      // App was in background — restore minimal info and reject
      final extra = event.body['extra'] as Map<String, dynamic>?;
      if (extra != null) {
        final callId = extra['callId'] as String? ?? '';
        final callerPhone = extra['callerPhone'] as String? ?? '';
        if (callId.isNotEmpty && callerPhone.isNotEmpty) {
          MessengerWsService.instance.sendCallReject(
            callerPhone: callerPhone,
            callId: callId,
          );
        }
      }
    }
    // Dismiss CallKit UI (suppress actionCallEnded event)
    _dismissingCallKit = true;
    FlutterCallkitIncoming.endAllCalls();
  }

  /// Show native CallKit incoming call screen
  Future<void> _showCallKitIncoming(String callId, String callerName, String callerPhone, String offerSdp) async {
    try {
      final params = CallKitParams(
        id: callId,
        nameCaller: callerName.isNotEmpty ? callerName : callerPhone,
        appName: 'Арабика',
        handle: callerPhone,
        type: 0,
        textAccept: 'Ответить',
        textDecline: 'Отклонить',
        duration: 45000,
        extra: <String, dynamic>{
          'callId': callId,
          'callerPhone': callerPhone,
          'callerName': callerName,
          'offerSdp': offerSdp,
        },
        android: const AndroidParams(
          isCustomNotification: true,
          isShowLogo: false,
          ringtonePath: 'system_ringtone_default',
          backgroundColor: '#1A4D4D',
          actionColor: '#4CAF50',
          textColor: '#ffffff',
          incomingCallNotificationChannelName: 'Входящий звонок',
          missedCallNotificationChannelName: 'Пропущенный звонок',
          isShowCallID: false,
        ),
        missedCallNotification: const NotificationParams(
          showNotification: true,
          isShowCallback: true,
          subtitle: 'Пропущенный звонок',
          callbackText: 'Перезвонить',
        ),
      );
      await FlutterCallkitIncoming.showCallkitIncoming(params);
    } catch (e) {
      Logger.error('📞 CallKit showIncoming error', e);
    }
  }

  // ─── Outgoing call ───

  Future<bool> startCall({
    required String targetPhone,
    required String targetName,
    required String conversationId,
  }) async {
    if (_state != CallState.idle) return false;

    Logger.debug('📞 CallService: starting call to $targetPhone');
    _conversationId = conversationId;

    try {
      _localStream = await navigator.mediaDevices
          .getUserMedia({'audio': true, 'video': false});

      _pc = await createPeerConnection(_rtcConfig);
      _setupPeerConnection(targetPhone);

      _localStream!.getAudioTracks().forEach((t) => _pc!.addTrack(t, _localStream!));

      final offer = await _pc!.createOffer({'offerToReceiveAudio': true});
      await _pc!.setLocalDescription(offer);

      final callId = 'call_${DateTime.now().millisecondsSinceEpoch}';
      _currentCall = CallInfo(
        callId: callId,
        remotePhone: targetPhone,
        remoteName: targetName,
        isOutgoing: true,
        startedAt: DateTime.now(),
      );

      _setState(CallState.outgoing);

      // Send offer via WebSocket
      MessengerWsService.instance.sendCallOffer(
        targetPhone: targetPhone,
        callId: callId,
        offerSdp: offer.sdp!,
        callerName: _myName ?? _myPhone ?? '',
      );

      // Also notify via REST (wakes up offline callee via FCM)
      try {
        await BaseHttpService.postRaw(
          endpoint: '/api/messenger/call/notify',
          body: {
            'callId': callId,
            'callerPhone': _myPhone,
            'targetPhone': targetPhone,
            'callerName': _myName ?? '',
            'offerSdp': offer.sdp!,
          },
        );
      } catch (_) {} // FCM failure is non-fatal — WS may have delivered it

      // Ring timeout: 45 seconds
      _ringTimer = Timer(const Duration(seconds: 45), () {
        if (_state == CallState.outgoing) {
          Logger.debug('📞 CallService: no answer, ending call');
          _recordCall('missed');
          _cleanup();
          _setState(CallState.ended);
          Future.delayed(const Duration(seconds: 1), () => _setState(CallState.idle));
        }
      });

      return true;
    } catch (e) {
      Logger.error('📞 CallService: startCall error', e);
      _cleanup();
      _setState(CallState.idle);
      return false;
    }
  }

  // ─── Incoming call ───

  void _onCallIncoming(MsgrCallIncoming event) {
    if (_state != CallState.idle) {
      // Same call arriving via duplicate WS connection — ignore
      if (_currentCall?.callId == event.callId) return;
      // Different call while already in one — auto-reject
      MessengerWsService.instance.sendCallReject(
        callerPhone: event.callerPhone,
        callId: event.callId,
      );
      return;
    }

    Logger.debug('📞 CallService: incoming call from ${event.callerPhone}');
    _currentCall = CallInfo(
      callId: event.callId,
      remotePhone: event.callerPhone,
      remoteName: event.callerName,
      isOutgoing: false,
      startedAt: DateTime.now(),
    );
    _pendingCandidates.clear();
    _setState(CallState.incoming);

    // Show native incoming call screen (works even when app is minimized)
    _showCallKitIncoming(event.callId, event.callerName, event.callerPhone, event.offerSdp);
  }

  Future<void> answerCall() async {
    if (_state != CallState.incoming || _currentCall == null) return;
    Logger.debug('📞 CallService: answering call');

    try {
      _localStream = await navigator.mediaDevices
          .getUserMedia({'audio': true, 'video': false});

      _pc = await createPeerConnection(_rtcConfig);
      _setupPeerConnection(_currentCall!.remotePhone);

      _localStream!.getAudioTracks().forEach((t) => _pc!.addTrack(t, _localStream!));

      // The offer SDP was delivered in MsgrCallIncoming — we stored the event
      // Re-fetch it from the stream isn't possible, so we store it on incoming.
      // NOTE: we need to keep the offer SDP — update CallInfo or store separately.
      // We need to re-design slightly: store offerSdp in CallInfo.
      // For now, use the stored _pendingOfferSdp.
      if (_pendingOfferSdp == null) return;

      await _pc!.setRemoteDescription(RTCSessionDescription(_pendingOfferSdp!, 'offer'));

      // Apply buffered ICE candidates
      for (final c in _pendingCandidates) {
        await _pc!.addCandidate(_mapToIceCandidate(c.candidate));
      }
      _pendingCandidates.clear();

      final answer = await _pc!.createAnswer({});
      await _pc!.setLocalDescription(answer);

      // Send call_answer with retry — critical message, must not be lost
      final sent = await MessengerWsService.instance.sendWithRetry({
        'type': 'call_answer',
        'callerPhone': _currentCall!.remotePhone,
        'callId': _currentCall!.callId,
        'answerSdp': answer.sdp!,
      });

      if (!sent) {
        Logger.error('📞 CallService: failed to send call_answer after retries');
        rejectCall();
        return;
      }

      // Dismiss CallKit incoming screen (suppress actionCallEnded event)
      _dismissingCallKit = true;
      FlutterCallkitIncoming.endAllCalls();

      _setState(CallState.connected);
    } catch (e) {
      Logger.error('📞 CallService: answerCall error', e);
      rejectCall();
    }
  }

  void rejectCall() {
    if (_currentCall == null) return;
    Logger.debug('📞 CallService: rejecting call');
    MessengerWsService.instance.sendCallReject(
      callerPhone: _currentCall!.remotePhone,
      callId: _currentCall!.callId,
    );
    _recordCall('rejected');
    _setState(CallState.ended);
    _cleanup();
    Future.delayed(const Duration(seconds: 1), () => _setState(CallState.idle));
  }

  // ─── During call ───

  void _onCallAnswered(MsgrCallAnswered event) {
    if (_state != CallState.outgoing || _pc == null) return;
    Logger.debug('📞 CallService: call answered');

    _pc!.setRemoteDescription(
      RTCSessionDescription(event.answerSdp, 'answer'),
    ).then((_) async {
      // Apply buffered ICE candidates
      for (final c in _pendingCandidates) {
        await _pc!.addCandidate(_mapToIceCandidate(c.candidate));
      }
      _pendingCandidates.clear();
      _ringTimer?.cancel();
      _setState(CallState.connected);
    });
  }

  void _onCallRejected(MsgrCallRejected event) {
    if (_state != CallState.outgoing) return;
    Logger.debug('📞 CallService: call rejected');
    _ringTimer?.cancel();
    _recordCall('rejected');
    _setState(CallState.ended);
    _cleanup();
    Future.delayed(const Duration(seconds: 1), () => _setState(CallState.idle));
  }

  void _onCallIceCandidate(MsgrCallIceCandidate event) {
    if (_pc == null || event.candidate.isEmpty) return;
    final candidate = _mapToIceCandidate(event.candidate);
    if (_state == CallState.connected ||
        (_state == CallState.outgoing && _pc!.signalingState != RTCSignalingState.RTCSignalingStateHaveLocalOffer)) {
      _pc!.addCandidate(candidate);
    } else {
      _pendingCandidates.add(event);
    }
  }

  void _onCallHangup(MsgrCallHangup event) {
    if (_state == CallState.idle || _state == CallState.ended) return;
    Logger.debug('📞 CallService: remote hung up');
    _ringTimer?.cancel();
    if (_state == CallState.connected) _recordCall('completed');
    _setState(CallState.ended);
    _cleanup();
    Future.delayed(const Duration(seconds: 1), () => _setState(CallState.idle));
  }

  void hangUp() {
    if (_currentCall == null) return;
    Logger.debug('📞 CallService: hanging up');
    MessengerWsService.instance.sendCallHangup(
      targetPhone: _currentCall!.remotePhone,
      callId: _currentCall!.callId,
    );
    _ringTimer?.cancel();
    if (_state == CallState.connected) _recordCall('completed');
    _setState(CallState.ended);
    _cleanup();
    Future.delayed(const Duration(seconds: 1), () => _setState(CallState.idle));
  }

  void toggleMute() {
    _isMuted = !_isMuted;
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !_isMuted);
    _stateController.add(_state); // notify UI to rebuild mute button
  }

  // ─── WebRTC internals ───

  void _setupPeerConnection(String remotePhone) {
    _pc!.onIceCandidate = (RTCIceCandidate? candidate) {
      if (candidate == null || candidate.candidate == null) return;
      MessengerWsService.instance.sendCallIceCandidate(
        targetPhone: remotePhone,
        callId: _currentCall?.callId ?? '',
        candidate: {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      );
    };

    _pc!.onIceConnectionState = (state) {
      Logger.debug('📞 ICE state: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        // ICE completely failed — no recovery possible
        if (_state == CallState.connected && _currentCall != null) {
          hangUp();
        }
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        // ICE temporarily disconnected — give it 8 seconds to recover
        // (common during cold start when ICE candidates are still being exchanged)
        _iceDisconnectTimer?.cancel();
        _iceDisconnectTimer = Timer(const Duration(seconds: 8), () {
          if (_state == CallState.connected && _currentCall != null && _pc != null) {
            // Check if still disconnected after timeout
            _pc!.getStats().then((_) {
              // If we get here, PC is alive but ICE may still be disconnected
              Logger.debug('📞 ICE disconnect timeout — hanging up');
              hangUp();
            }).catchError((_) {
              hangUp();
            });
          }
        });
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
                 state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        // ICE recovered or connected — cancel disconnect timer
        _iceDisconnectTimer?.cancel();
        _iceDisconnectTimer = null;
      }
    };
  }

  RTCIceCandidate _mapToIceCandidate(Map<String, dynamic> map) {
    return RTCIceCandidate(
      map['candidate'] as String?,
      map['sdpMid'] as String?,
      map['sdpMLineIndex'] as int?,
    );
  }

  // ─── Call recording (saves to DB) ───

  void _recordCall(String status) {
    if (_currentCall == null || _conversationId == null) return;
    final duration = DateTime.now().difference(_currentCall!.startedAt).inSeconds;
    BaseHttpService.postRaw(
      endpoint: '/api/messenger/call/record',
      body: {
        'conversationId': _conversationId,
        'calleePhone': _currentCall!.remotePhone,
        'durationSeconds': duration,
        'status': status,
      },
    ).catchError((_) => null);
  }

  // ─── FCM-launched call restore ───

  /// Called when the app was launched from an FCM incoming_call notification.
  /// Sets up incoming call state from FCM data so the user can answer via CallPage.
  void handleFcmIncomingCall({
    required String callId,
    required String callerPhone,
    required String callerName,
    required String offerSdp,
    String? conversationId,
  }) {
    if (_state != CallState.idle) return;
    Logger.debug('📞 CallService: restoring incoming call from FCM, callId=$callId');
    _currentCall = CallInfo(
      callId: callId,
      remotePhone: callerPhone,
      remoteName: callerName,
      isOutgoing: false,
      startedAt: DateTime.now(),
    );
    _pendingOfferSdp = offerSdp;
    _conversationId = conversationId;
    _pendingCandidates.clear();
    _setState(CallState.incoming);
  }

  // ─── Cleanup ───

  void _cleanup() {
    _iceDisconnectTimer?.cancel();
    _iceDisconnectTimer = null;
    try { _pc?.close(); } catch (e) { Logger.error('📞 _cleanup: pc.close error', e); }
    _pc = null;
    try { _localStream?.dispose(); } catch (e) { Logger.error('📞 _cleanup: stream.dispose error', e); }
    _localStream = null;
    _pendingCandidates.clear();
    _pendingOfferSdp = null;
    _currentCall = null;
    _conversationId = null;
    _isMuted = false;
    // Dismiss any active CallKit UI (suppress actionCallEnded event)
    _dismissingCallKit = true;
    FlutterCallkitIncoming.endAllCalls();
  }

  void _setState(CallState s) {
    _state = s;
    _stateController.add(s);
  }

  void dispose() {
    _callkitSub?.cancel();
    _subIncoming?.cancel();
    _subAnswered?.cancel();
    _subRejected?.cancel();
    _subIce?.cancel();
    _subHangup?.cancel();
    _ringTimer?.cancel();
    _cleanup();
    _stateController.close();
  }
}
