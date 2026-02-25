import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  inCall,
  error,
}

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

  ConnectionStatus _status = ConnectionStatus.disconnected;
  final List<String> _logs = [];

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

    _setStatus(ConnectionStatus.connecting, 'Conectando a $serverUrl');

    _channel = WebSocketChannel.connect(Uri.parse(serverUrl));
    _channel!.stream.listen((message) async {
      final data = jsonDecode(message as String);
      if (data['room'] != roomId) return;

      _addLog('WS: ${data['type']}');

      switch (data['type']) {
        case 'offer':
          await _peerConnection?.setRemoteDescription(
            RTCSessionDescription(data['sdp'], 'offer'),
          );
          final answer = await _peerConnection!.createAnswer();
          await _peerConnection!.setLocalDescription(answer);
          _send({'type': 'answer', 'sdp': answer.sdp, 'room': roomId});
          _setStatus(ConnectionStatus.inCall, 'Recibida offer, enviando answer');
          break;
        case 'answer':
          await _peerConnection?.setRemoteDescription(
            RTCSessionDescription(data['sdp'], 'answer'),
          );
          _setStatus(ConnectionStatus.inCall, 'Answer recibido');
          break;
        case 'candidate':
          final cand = data['candidate'];
          await _peerConnection?.addCandidate(
            RTCIceCandidate(cand['candidate'], cand['sdpMid'], cand['sdpMLineIndex']),
          );
          break;
      }
    }, onError: (error) {
      _setStatus(ConnectionStatus.error, 'Error WebSocket: $error');
      _showSnackBar('Error WebSocket: $error');
    }, onDone: () {
      _addLog('WS: conexión cerrada');
      if (mounted) {
        _setStatus(ConnectionStatus.disconnected, 'WebSocket cerrado');
      }
    });

    _addLog('Solicitando micrófono');
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

    _peerConnection!.onIceConnectionState = (state) {
      _addLog('ICE: $state');
    };

    _peerConnection!.onConnectionState = (state) {
      _addLog('PC: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _setStatus(ConnectionStatus.inCall, 'Conectado');
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _setStatus(ConnectionStatus.error, 'Conexión fallida');
      }
    };

    _peerConnection!.onSignalingState = (state) {
      _addLog('Signaling: $state');
    };

    _setStatus(ConnectionStatus.connected, 'Listo para iniciar llamada');
  }

  Future<void> _startCall() async {
    final roomId = _roomIdController.text.trim();
    if (_peerConnection == null) return;

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    _send({'type': 'offer', 'sdp': offer.sdp, 'room': roomId});
    _setStatus(ConnectionStatus.inCall, 'Offer enviado');
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
      _setStatus(ConnectionStatus.disconnected, 'Desconectado');
    }
  }

  void _addLog(String message) {
    final timestamp = DateTime.now().toIso8601String();
    if (!mounted) return;
    setState(() {
      _logs.insert(0, '[$timestamp] $message');
    });
  }

  void _clearLogs() {
    if (!mounted) return;
    setState(_logs.clear);
  }

  void _setStatus(ConnectionStatus status, String message) {
    if (!mounted) return;
    setState(() {
      _status = status;
      _logs.insert(0, '[${DateTime.now().toIso8601String()}] $message');
    });
  }

  String get _statusLabel {
    switch (_status) {
      case ConnectionStatus.disconnected:
        return 'Desconectado';
      case ConnectionStatus.connecting:
        return 'Conectando';
      case ConnectionStatus.connected:
        return 'Conectado';
      case ConnectionStatus.inCall:
        return 'En llamada';
      case ConnectionStatus.error:
        return 'Error';
    }
  }

  Color get _statusColor {
    switch (_status) {
      case ConnectionStatus.disconnected:
        return Colors.grey;
      case ConnectionStatus.connecting:
        return Colors.orange;
      case ConnectionStatus.connected:
        return Colors.green;
      case ConnectionStatus.inCall:
        return Colors.blue;
      case ConnectionStatus.error:
        return Colors.red;
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
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Estado:'),
                const SizedBox(width: 8),
                Chip(
                  label: Text(_statusLabel),
                  backgroundColor: _statusColor.withOpacity(0.15),
                  labelStyle: TextStyle(color: _statusColor),
                  side: BorderSide(color: _statusColor.withOpacity(0.4)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _status == ConnectionStatus.connecting ||
                      _status == ConnectionStatus.connected ||
                      _status == ConnectionStatus.inCall
                  ? null
                  : _connect,
              child: const Text('Conectar'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _status == ConnectionStatus.connected ||
                      _status == ConnectionStatus.inCall
                  ? _startCall
                  : null,
              child: const Text('Llamar (crear offer)'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _status == ConnectionStatus.disconnected ? null : _cleanup,
              child: const Text('Colgar'),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Logs'),
                TextButton.icon(
                  onPressed: _logs.isEmpty ? null : _clearLogs,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Limpiar'),
                ),
              ],
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _logs.isEmpty
                    ? const Center(child: Text('Sin eventos aún'))
                    : ListView.builder(
                        reverse: true,
                        itemCount: _logs.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              _logs[index],
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: 12),
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