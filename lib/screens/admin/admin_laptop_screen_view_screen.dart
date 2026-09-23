// admin_laptop_screen_view_screen.dart — Allin1 Laptop Live Screen View
//
// WebRTC VIEWER side. Reads the SDP offer Nizam's laptop published via
// backend-admin/screen_share/host.html (opened manually on the laptop -
// this app never starts screen capture, only requests to VIEW it), answers
// it, exchanges ICE candidates, and renders the resulting peer-to-peer
// video track. Video never touches Firestore or any server - only the
// connection setup (SDP/ICE) does, via `laptop_screen_share/{SESSION_ID}`
// (see firestore.rules for the admin-only gate on that collection).
//
// This mirrors backend-admin/screen_share/viewer_test.html's EXACT
// Firestore contract (field names, subcollection names, session id) - keep
// both in sync if either changes.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:google_fonts/google_fonts.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _card = Color(0xFF141420);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _border = Color(0x267B6FE0);
const Color _amber = Color(0xFFFFB020);
const Color _purple = Color(0xFFB21FFF);

const String _sessionId = 'nizam_laptop';

class AdminLaptopScreenViewScreen extends StatefulWidget {
  const AdminLaptopScreenViewScreen({super.key});

  @override
  State<AdminLaptopScreenViewScreen> createState() =>
      _AdminLaptopScreenViewScreenState();
}

class _AdminLaptopScreenViewScreenState
    extends State<AdminLaptopScreenViewScreen> {
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  String _status = 'Not connected.';
  bool _connecting = false;
  bool _connected = false;

  DocumentReference<Map<String, dynamic>> get _sessionRef => FirebaseFirestore
      .instance
      .collection('laptop_screen_share')
      .doc(_sessionId);

  @override
  void initState() {
    super.initState();
    _remoteRenderer.initialize();
  }

  @override
  void dispose() {
    _teardown();
    _remoteRenderer.dispose();
    super.dispose();
  }

  Future<void> _teardown() async {
    await _pc?.close();
    _pc = null;
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _status = 'Checking if the laptop is sharing...';
    });

    try {
      final snap = await _sessionRef.get();
      final data = snap.data();
      final offer = data?['offer'] as Map<String, dynamic>?;
      if (offer == null) {
        setState(() {
          _connecting = false;
          _status = 'Laptop is not sharing right now.\n'
              'Open host.html on the laptop and tap "Start Screen Share" first.';
        });
        return;
      }

      final pc = await createPeerConnection({
        'iceServers': [
          {
            'urls': [
              'stun:stun.l.google.com:19302',
              'stun:stun1.l.google.com:19302',
            ],
          },
        ],
      });
      _pc = pc;

      pc.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          _remoteRenderer.srcObject = event.streams.first;
          if (mounted) setState(() => _connected = true);
        }
      };

      final answerCandidates = _sessionRef.collection('answerCandidates');
      final offerCandidates = _sessionRef.collection('offerCandidates');

      pc.onIceCandidate = (candidate) {
        answerCandidates.add(Map<String, dynamic>.from(candidate.toMap() as Map));
      };

      await pc.setRemoteDescription(
        RTCSessionDescription(offer['sdp'] as String, offer['type'] as String),
      );
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);

      await _sessionRef.update({
        'answer': {'type': answer.type, 'sdp': answer.sdp},
      });

      offerCandidates.snapshots().listen((snapshot) {
        for (final change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            final c = change.doc.data();
            if (c == null) continue;
            pc.addCandidate(
              RTCIceCandidate(
                c['candidate'] as String?,
                c['sdpMid'] as String?,
                c['sdpMLineIndex'] as int?,
              ),
            );
          }
        }
      });

      setState(() {
        _connecting = false;
        _status = 'Answer sent - waiting for the video track...';
      });
    } catch (e) {
      setState(() {
        _connecting = false;
        _status = 'Connection failed: $e';
      });
    }
  }

  Future<void> _disconnect() async {
    await _teardown();
    setState(() {
      _connected = false;
      _status = 'Disconnected.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
        title: Text(
          'Laptop Screen View',
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                clipBehavior: Clip.antiAlias,
                child: _connected
                    ? RTCVideoView(_remoteRenderer)
                    : Center(
                        child: Icon(
                          Icons.laptop_mac_outlined,
                          color: _muted.withValues(alpha: 0.4),
                          size: 48,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _border),
              ),
              child: Text(
                _status,
                style: GoogleFonts.outfit(color: _muted, fontSize: 12),
              ),
            ),
            const SizedBox(height: 16),
            if (!_connected)
              ElevatedButton.icon(
                onPressed: _connecting ? null : _connect,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _purple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12,),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: _connecting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white,),
                      )
                    : const Icon(Icons.wifi_tethering),
                label: Text(_connecting ? 'Connecting...' : 'Connect'),
              )
            else
              ElevatedButton.icon(
                onPressed: _disconnect,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _amber,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12,),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.close),
                label: const Text('Disconnect'),
              ),
          ],
        ),
      ),
    );
  }
}
