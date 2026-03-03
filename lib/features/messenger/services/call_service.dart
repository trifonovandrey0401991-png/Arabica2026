import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
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

  // ─── Public state ───
  CallState get state => _state;
  CallInfo? get currentCall => _currentCall;
  bool get isActive => _state != CallState.idle && _state != CallState.ended;
  bool get isMuted => _isMuted;
  bool _isMuted = false;

  // State change notifier — UI subscribes to this
  final _stateController = StreamController<CallState>.broadcast();
  Stream<CallState> get onStateChanged => _stateController.stream;

  // ─── Initialisation ───

  void init(String myPhone, String myName) {
    _myPhone = myPhone;
    _myName  = myName;
    _subscribeToWsEvents();
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
      _pendingOfferSdp = e.offerSdp;
      _onCallIncoming(e);
    });
    _subAnswered = ws.onCallAnswered.listen(_onCallAnswered);
    _subRejected = ws.onCallRejected.listen(_onCallRejected);
    _subIce      = ws.onCallIceCandidate.listen(_onCallIceCandidate);
    _subHangup   = ws.onCallHangup.listen(_onCallHangup);
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
      // Already in a call — auto-reject
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

      MessengerWsService.instance.sendCallAnswer(
        callerPhone: _currentCall!.remotePhone,
        callId: _currentCall!.callId,
        answerSdp: answer.sdp!,
      );

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
    _cleanup();
    _setState(CallState.ended);
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
    _cleanup();
    _setState(CallState.ended);
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
    _cleanup();
    _setState(CallState.ended);
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
    _cleanup();
    _setState(CallState.ended);
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
      if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        if (_state == CallState.connected) {
          hangUp();
        }
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
    ).catchError((_) {});
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
    _pc?.close();
    _pc = null;
    _localStream?.dispose();
    _localStream = null;
    _pendingCandidates.clear();
    _pendingOfferSdp = null;
    _currentCall = null;
    _conversationId = null;
    _isMuted = false;
  }

  void _setState(CallState s) {
    _state = s;
    _stateController.add(s);
  }

  void dispose() {
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
