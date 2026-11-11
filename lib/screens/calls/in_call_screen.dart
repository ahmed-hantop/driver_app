import 'dart:async';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import '../../models/chat_models.dart';
import '../../services/call_service.dart';
import '../../services/callkit_service.dart';

class InCallScreen extends StatefulWidget {
  /// Pre-answered path: the call was already answered and we have the LiveKit
  /// connection details.
  final IncomingCallData? callData;

  /// Answering path (from a CallKit "accept"): we only have the call id and
  /// need to hit the answer API to obtain the LiveKit token, then connect.
  final int? answerCallLogId;

  final String callerName;
  final String callType;

  InCallScreen({super.key, required IncomingCallData callData})
      : callData = callData,
        answerCallLogId = null,
        callerName = callData.callerName,
        callType = callData.callType;

  const InCallScreen.answering({
    super.key,
    required this.answerCallLogId,
    required this.callerName,
    required this.callType,
  }) : callData = null;

  @override
  State<InCallScreen> createState() => _InCallScreenState();
}

class _InCallScreenState extends State<InCallScreen> {
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  VideoTrack? _remoteVideoTrack;
  LocalVideoTrack? _localVideoTrack;
  // Cached once resolved so Retry reconnects with the same token instead of
  // re-calling /answer (which 404s — the call is already 'answered' by then).
  IncomingCallData? _resolvedCall;

  bool _muted = false;
  bool _cameraOff = false;
  bool _speakerOn = true;
  int _seconds = 0;
  Timer? _durationTimer;
  Timer? _pollTimer;
  bool _ending = false;
  bool _answering = false;
  bool _connecting = true;
  String? _error;

  int get _callLogId => widget.callData?.callLogId ?? widget.answerCallLogId!;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _pollTimer?.cancel();
    _listener?.dispose();
    _room?.disconnect();
    _room?.dispose();
    super.dispose();
  }

  void _retry() {
    if (!mounted || _connecting || _answering || _ending) return;
    setState(() {
      _error = null;
      _connecting = true;
      _answering = false;
    });
    _connect();
  }

  Future<void> _connect() async {
    final isVideo = widget.callType == 'video';

    // Resolve the LiveKit connection details. In "answering" mode this hits the
    // answer API first (the CallKit UI already served as the ringing screen).
    IncomingCallData call;
    try {
      if (_resolvedCall != null) {
        call = _resolvedCall!;
      } else if (widget.callData != null) {
        call = widget.callData!;
      } else {
        if (mounted) setState(() => _answering = true);
        call = await CallService().answerCall(widget.answerCallLogId!);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _answering = false;
          _connecting = false;
          _error = e.toString();
        });
      }
      await CallkitService.instance.endCall(_callLogId);
      return;
    }

    _resolvedCall = call;
    if (mounted) setState(() => _answering = false);

    Room? connectingRoom;
    EventsListener<RoomEvent>? connectingListener;
    try {
      final room = Room();
      connectingRoom = room;
      final listener = room.createListener()
        ..on<TrackSubscribedEvent>((e) {
          if (e.track is VideoTrack && mounted) {
            setState(() => _remoteVideoTrack = e.track as VideoTrack);
          }
        })
        ..on<TrackUnsubscribedEvent>((e) {
          if (e.track is VideoTrack && mounted) {
            setState(() => _remoteVideoTrack = null);
          }
        })
        ..on<RoomDisconnectedEvent>((_) {
          // Ignore a disconnect from a room that never completed connection;
          // Retry owns that transient failure and must keep the call alive.
          if (mounted && identical(_room, room) && !_ending) {
            _endCall(remotely: true);
          }
        });
      connectingListener = listener;

      await room.connect(
        call.livekitUrl,
        call.token,
        roomOptions: RoomOptions(
          defaultAudioPublishOptions: const AudioPublishOptions(
            name: 'microphone',
          ),
          defaultVideoPublishOptions: const VideoPublishOptions(),
        ),
      );

      await room.localParticipant?.setMicrophoneEnabled(true);

      LocalVideoTrack? localVideoTrack;
      if (isVideo) {
        await room.localParticipant?.setCameraEnabled(true);
        final pubs = room.localParticipant?.videoTrackPublications;
        if (pubs != null && pubs.isNotEmpty) {
          localVideoTrack = pubs.first.track;
        }
      }

      // Pick up tracks already published before we connected
      for (final p in room.remoteParticipants.values) {
        for (final pub in p.trackPublications.values) {
          if (pub.subscribed && pub.track is VideoTrack) {
            _remoteVideoTrack = pub.track as VideoTrack;
          }
        }
      }

      await Hardware.instance.setSpeakerphoneOn(true);

      // Promote the OS-level CallKit call to "connected" (starts its timer).
      await CallkitService.instance.setConnected(_callLogId);

      if (mounted) {
        setState(() {
          _room = room;
          _listener = listener;
          _connecting = false;
          _localVideoTrack = localVideoTrack;
        });
        _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() => _seconds++);
        });
        // Poll every 5s to detect if admin ended the call from DMS
        _pollTimer = Timer.periodic(
          const Duration(seconds: 5),
          (_) => _checkRemoteEnded(),
        );
      }
    } catch (e) {
      // A failed media negotiation is recoverable.  Do not end the server-side
      // call or dismiss Android's native call UI here: doing that made Retry
      // retry a call already marked ended.  Release only the failed local
      // connection and keep the accepted call available for another attempt.
      connectingListener?.dispose();
      try {
        await connectingRoom?.disconnect();
      } catch (_) {}
      try {
        connectingRoom?.dispose();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = 'Unable to connect media. Check the network and retry.';
        });
      }
    }
  }

  Future<void> _checkRemoteEnded() async {
    if (!mounted || _ending || _connecting) return;
    final status = await CallService().checkCallStatus(_callLogId);
    if (status != null && status != 'answered') {
      if (mounted && !_ending) _endCall(remotely: true);
    }
  }

  String get _durationLabel {
    final m = _seconds ~/ 60;
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _endCall({bool remotely = false}) async {
    if (_ending) return;
    setState(() => _ending = true);
    _durationTimer?.cancel();
    try {
      await _room?.disconnect();
      if (!remotely) await CallService().endCall(_callLogId);
    } catch (_) {}
    // Dismiss the native CallKit UI/session in every case.
    await CallkitService.instance.endCall(_callLogId);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _toggleMute() async {
    final next = !_muted;
    await _room?.localParticipant?.setMicrophoneEnabled(!next);
    if (mounted) setState(() => _muted = next);
  }

  Future<void> _toggleCamera() async {
    final next = !_cameraOff;
    await _room?.localParticipant?.setCameraEnabled(!next);
    LocalVideoTrack? localTrack;
    if (!next) {
      final pubs = _room?.localParticipant?.videoTrackPublications;
      if (pubs != null && pubs.isNotEmpty) localTrack = pubs.first.track;
    }
    if (mounted)
      setState(() {
        _cameraOff = next;
        _localVideoTrack = next ? null : localTrack;
      });
  }

  Future<void> _toggleSpeaker() async {
    final next = !_speakerOn;
    await Hardware.instance.setSpeakerphoneOn(next);
    if (mounted) setState(() => _speakerOn = next);
  }

  String get _statusLabel {
    if (_error != null) return 'Connection failed';
    if (_answering) return 'Answering…';
    if (_connecting) return 'Connecting…';
    return _durationLabel;
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.callType == 'video';
    final showTimer = !_answering && !_connecting && _error == null;
    return Scaffold(
      backgroundColor: const Color(0xFF1A237E),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 40),

            // Caller info
            Text(
              widget.callerName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _statusLabel,
              style: TextStyle(
                color: _error != null
                    ? Colors.redAccent
                    : Colors.white.withValues(alpha: 0.7),
                fontSize: showTimer ? 18 : 16,
                fontFamily: showTimer ? 'monospace' : null,
              ),
            ),
            // Surface the real underlying error (network / LiveKit) so a failed
            // call is diagnosable instead of a blank "Connection failed".
            if (_error != null) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _error!.length > 160 ? '${_error!.substring(0, 160)}…' : _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _retry,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                ),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
              ),
            ],

            const Spacer(),

            // Local camera preview (driver sees themselves)
            if (isVideo) ...[
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                height: 260,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.hardEdge,
                child: _localVideoTrack != null && !_cameraOff
                    ? VideoTrackRenderer(_localVideoTrack!)
                    : Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _cameraOff ? Icons.videocam_off : Icons.videocam,
                              color: Colors.white38,
                              size: 60,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _cameraOff ? 'Camera off' : 'Starting camera...',
                              style: const TextStyle(color: Colors.white54),
                            ),
                          ],
                        ),
                      ),
              ),
            ],

            const Spacer(),

            // Controls
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _control(
                        icon: _muted ? Icons.mic_off : Icons.mic,
                        label: _muted ? 'Unmute' : 'Mute',
                        active: _muted,
                        onTap: _toggleMute,
                      ),
                      _control(
                        icon: _speakerOn ? Icons.volume_up : Icons.volume_off,
                        label: 'Speaker',
                        active: _speakerOn,
                        onTap: _toggleSpeaker,
                      ),
                      if (isVideo)
                        _control(
                          icon: _cameraOff
                              ? Icons.videocam_off
                              : Icons.videocam,
                          label: _cameraOff ? 'Camera off' : 'Camera',
                          active: !_cameraOff,
                          onTap: _toggleCamera,
                        ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // End call button
                  GestureDetector(
                    onTap: (_ending || _connecting || _answering)
                        ? null
                        : () => _endCall(),
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: (_ending || _connecting || _answering)
                          ? const Padding(
                              padding: EdgeInsets.all(22),
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 3,
                              ),
                            )
                          : const Icon(
                              Icons.call_end,
                              color: Colors.white,
                              size: 32,
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'End Call',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _control({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: active
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Icon(
              icon,
              color: active ? Colors.white : Colors.white54,
              size: 24,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
