import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RTC Audio POC',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const CallPage(),
    );
  }
}

class CallPage extends StatefulWidget {
  const CallPage({super.key});

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  final _serverUrlController = TextEditingController(text: 'ws://YOUR_IP:8080');
  final _roomIdController = TextEditingController(text: 'room1');

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  WebSocketChannel? _channel;

  bool _connected = false;

  @override
  void dispose() {
    _serverUrlController.dispose();
    _roomIdController.dispose();
    _cleanup();
    super.dispose();
  }

  Future<void> _connect() async {
    final serverUrl = _serverUrlController.text.trim();
    final roomId = _roomIdController.text.trim();

    if (serverUrl.isEmpty || roomId.isEmpty) {
      _showSnackBar('Ingresa WebSocket URL y Room ID');
      return;
    }

    _channel = WebSocketChannel.connect(Uri.parse(serverUrl));
    _channel!.stream.listen((message) async {
      final data = jsonDecode(message as String);
      if (data['room'] != roomId) return;

      switch (data['type']) {
        case 'offer':
          await _peerConnection?.setRemoteDescription(
            RTCSessionDescription(data['sdp'], 'offer'),
          );
          final answer = await _peerConnection!.createAnswer();
          await _peerConnection!.setLocalDescription(answer);
          _send({'type': 'answer', 'sdp': answer.sdp, 'room': roomId});
          break;
        case 'answer':
          await _peerConnection?.setRemoteDescription(
            RTCSessionDescription(data['sdp'], 'answer'),
          );
          break;
        case 'candidate':
          final cand = data['candidate'];
          await _peerConnection?.addCandidate(
            RTCIceCandidate(cand['candidate'], cand['sdpMid'], cand['sdpMLineIndex']),
          );
          break;
      }
    }, onError: (error) {
      _showSnackBar('Error WebSocket: $error');
    });

    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });

    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    };

    _peerConnection = await createPeerConnection(config);
    for (final track in _localStream!.getTracks()) {
      _peerConnection!.addTrack(track, _localStream!);
    }

    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        _send({
          'type': 'candidate',
          'candidate': {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
          'room': roomId,
        });
      }
    };

    setState(() => _connected = true);
  }

  Future<void> _startCall() async {
    final roomId = _roomIdController.text.trim();
    if (_peerConnection == null) return;

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    _send({'type': 'offer', 'sdp': offer.sdp, 'room': roomId});
  }

  void _send(Map<String, dynamic> data) {
    _channel?.sink.add(jsonEncode(data));
  }

  Future<void> _cleanup() async {
    await _peerConnection?.close();
    _peerConnection = null;

    await _localStream?.dispose();
    _localStream = null;

    await _channel?.sink.close();
    _channel = null;

    if (mounted) {
      setState(() => _connected = false);
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RTC Audio POC')), 
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _serverUrlController,
              decoration: const InputDecoration(labelText: 'WebSocket URL'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _roomIdController,
              decoration: const InputDecoration(labelText: 'Room ID'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _connected ? null : _connect,
              child: const Text('Conectar'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _connected ? _startCall : null,
              child: const Text('Llamar (crear offer)'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _connected ? _cleanup : null,
              child: const Text('Colgar'),
            ),
            const SizedBox(height: 24),
            const Text(
              'Usa el mismo Room ID en dos dispositivos. '
              'Pulsa Conectar en ambos y luego Llamar en uno de ellos.',
            ),
          ],
        ),
      ),
    );
  }
}