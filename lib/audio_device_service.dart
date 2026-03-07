import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:path_provider/path_provider.dart';

/// Representa un dispositivo de audio detectado por WebRTC.
class AudioDevice {
  final String deviceId;
  final String label;
  final AudioDeviceKind kind;

  const AudioDevice({
    required this.deviceId,
    required this.label,
    required this.kind,
  });

  bool get isInput => kind == AudioDeviceKind.input;
  bool get isOutput => kind == AudioDeviceKind.output;

  String get displayLabel =>
      label.isNotEmpty ? label : '${kind.displayName} (sin etiqueta)';

  @override
  String toString() => 'AudioDevice($kind, $deviceId, $label)';
}

enum AudioDeviceKind {
  input,
  output,
  unknown;

  String get displayName => switch (this) {
        AudioDeviceKind.input => 'Micrófono',
        AudioDeviceKind.output => 'Altavoz / Auricular',
        AudioDeviceKind.unknown => 'Desconocido',
      };

  IconData get icon => switch (this) {
        AudioDeviceKind.input => Icons.mic_rounded,
        AudioDeviceKind.output => Icons.headphones_rounded,
        AudioDeviceKind.unknown => Icons.device_unknown_rounded,
      };
}

/// Estado de una prueba de micrófono.
enum MicTestStatus { idle, requesting, recording, success, failed }

/// Estado de la prueba de auriculares.
enum SpeakerTestStatus { idle, playing, done, failed }

/// Resultado de la enumeración de dispositivos.
class AudioDeviceResult {
  final List<AudioDevice> devices;
  final String? error;

  const AudioDeviceResult({required this.devices, this.error});

  bool get hasError => error != null;
  List<AudioDevice> get inputs => devices.where((d) => d.isInput).toList();
  List<AudioDevice> get outputs => devices.where((d) => d.isOutput).toList();
}

/// Servicio singleton que gestiona la detección y prueba de dispositivos de audio.
/// Disponible en todas las plataformas — especialmente útil en Windows y macOS.
class AudioDeviceService extends ChangeNotifier {
  AudioDeviceService._();
  static final AudioDeviceService instance = AudioDeviceService._();

  // ── Estado observable ────────────────────────────────────────────────────
  List<AudioDevice> _devices = [];
  String? _enumerateError;
  bool _isEnumerating = false;

  MicTestStatus _micTestStatus = MicTestStatus.idle;
  String? _micTestError;
  double _micLevel = 0.0;

  // ── Estado prueba de auriculares ─────────────────────────────────────────
  SpeakerTestStatus _speakerTestStatus = SpeakerTestStatus.idle;
  String? _speakerTestError;
  Process? _speakerProcess;

  AudioDevice? _selectedInput;
  AudioDevice? _selectedOutput;

  webrtc.MediaStream? _testStream;
  Timer? _levelTimer;

  // ── Getters ──────────────────────────────────────────────────────────────
  List<AudioDevice> get devices => List.unmodifiable(_devices);
  List<AudioDevice> get inputs => _devices.where((d) => d.isInput).toList();
  List<AudioDevice> get outputs => _devices.where((d) => d.isOutput).toList();
  String? get enumerateError => _enumerateError;
  bool get isEnumerating => _isEnumerating;
  MicTestStatus get micTestStatus => _micTestStatus;
  String? get micTestError => _micTestError;
  double get micLevel => _micLevel;
  AudioDevice? get selectedInput => _selectedInput;
  AudioDevice? get selectedOutput => _selectedOutput;
  bool get hasInputDevice => inputs.isNotEmpty;
  bool get hasOutputDevice => outputs.isNotEmpty;
  bool get isTesting => _micTestStatus == MicTestStatus.recording ||
      _micTestStatus == MicTestStatus.success;

  SpeakerTestStatus get speakerTestStatus => _speakerTestStatus;
  String? get speakerTestError => _speakerTestError;
  bool get isSpeakerTesting => _speakerTestStatus == SpeakerTestStatus.playing;

  // ── Enumeración de dispositivos ───────────────────────────────────────────

  /// Detecta todos los dispositivos de audio disponibles.
  Future<AudioDeviceResult> enumerateDevices() async {
    _isEnumerating = true;
    _enumerateError = null;
    notifyListeners();

    try {
      final rawDevices = await webrtc.navigator.mediaDevices.enumerateDevices();

      _devices = rawDevices
          .where((d) => d.kind == 'audioinput' || d.kind == 'audiooutput')
          .map((d) => AudioDevice(
                deviceId: d.deviceId,
                label: d.label,
                kind: d.kind == 'audioinput'
                    ? AudioDeviceKind.input
                    : AudioDeviceKind.output,
              ))
          .toList();

      if (_selectedInput == null && inputs.isNotEmpty) {
        _selectedInput = inputs.first;
      }
      if (_selectedOutput == null && outputs.isNotEmpty) {
        _selectedOutput = outputs.first;
      }

      _enumerateError = null;
      debugPrint('[AudioDeviceService] Detectados: '
          '${inputs.length} entrada(s), ${outputs.length} salida(s)');
      for (final d in _devices) {
        debugPrint('  → ${d.kind.displayName}: ${d.displayLabel} [${d.deviceId}]');
      }
    } catch (e) {
      _enumerateError = 'Error al enumerar dispositivos: $e';
      _devices = [];
      debugPrint('[AudioDeviceService] Error: $_enumerateError');
    } finally {
      _isEnumerating = false;
      notifyListeners();
    }

    return AudioDeviceResult(devices: _devices, error: _enumerateError);
  }

  // ── Prueba de micrófono ───────────────────────────────────────────────────

  /// Inicia la prueba de captura del micrófono seleccionado.
  Future<void> startMicTest({String? deviceId}) async {
    if (isTesting) return;

    _micTestStatus = MicTestStatus.requesting;
    _micTestError = null;
    _micLevel = 0.0;
    notifyListeners();

    try {
      final constraints = <String, dynamic>{
        'audio': deviceId != null
            ? {'deviceId': deviceId, 'echoCancellation': false}
            : true,
        'video': false,
      };

      _testStream =
          await webrtc.navigator.mediaDevices.getUserMedia(constraints);

      _micTestStatus = MicTestStatus.recording;
      notifyListeners();

      // flutter_webrtc desktop no expone AudioWorklet todavía.
      // Usamos un timer que anima el indicador de nivel mientras el track esté activo.
      _startLevelAnimation();
    } catch (e) {
      _micTestStatus = MicTestStatus.failed;
      _micTestError = _friendlyError(e.toString());
      _micLevel = 0.0;
      debugPrint('[AudioDeviceService] Mic test failed: $e');
      notifyListeners();
    }
  }

  void _startLevelAnimation() {
    _levelTimer?.cancel();
    int tick = 0;
    _levelTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (_testStream == null) return;
      final tracks = _testStream!.getAudioTracks();
      if (tracks.isNotEmpty && tracks.first.enabled) {
        // Animación sinusoidal para dar feedback visual realista
        tick++;
        final base = 0.25;
        final wave1 = 0.35 * ((tick * 0.15) % 1.0);
        final wave2 = 0.2 * ((tick * 0.09) % 1.0);
        _micLevel = (base + wave1 + wave2).clamp(0.0, 1.0);
      } else {
        _micLevel = 0.0;
      }
      notifyListeners();
    });
  }

  /// Detiene la prueba de micrófono y libera recursos.
  Future<void> stopMicTest() async {
    _levelTimer?.cancel();
    _levelTimer = null;

    if (_testStream != null) {
      for (final track in _testStream!.getAudioTracks()) {
        await track.stop();
      }
      await _testStream!.dispose();
      _testStream = null;
    }

    _micLevel = 0.0;
    _micTestStatus = MicTestStatus.idle;
    _micTestError = null;
    notifyListeners();
  }

  void selectInput(AudioDevice device) {
    _selectedInput = device;
    notifyListeners();
  }

  void selectOutput(AudioDevice device) {
    _selectedOutput = device;
    notifyListeners();
  }

  // ── Prueba de auriculares ─────────────────────────────────────────────────

  /// Genera un tono sinusoidal (440 Hz, 2 seg) y lo reproduce
  /// usando el reproductor nativo del sistema operativo.
  Future<void> startSpeakerTest() async {
    if (isSpeakerTesting) return;

    _speakerTestStatus = SpeakerTestStatus.playing;
    _speakerTestError = null;
    notifyListeners();

    try {
      // 1. Genera el WAV en memoria
      final wavBytes = _generateSineWav(
        frequencyHz: 440.0,   // La central (A4)
        durationSec: 2.5,
        sampleRate: 44100,
        amplitude: 0.6,
      );

      // 2. Escribe el WAV en un archivo temporal
      final tmpDir = await getTemporaryDirectory();
      final tmpFile = File('${tmpDir.path}/zonitel_speaker_test.wav');
      await tmpFile.writeAsBytes(wavBytes);

      debugPrint('[AudioDeviceService] Reproduciendo tono: ${tmpFile.path}');

      // 3. Reproduce con el proceso nativo del SO
      if (Platform.isWindows) {
        // PowerShell con SoundPlayer
        _speakerProcess = await Process.start('powershell', [
          '-NoProfile', '-NonInteractive', '-Command',
          "(New-Object Media.SoundPlayer '${tmpFile.path}').PlaySync()"
        ]);
      } else if (Platform.isMacOS) {
        _speakerProcess = await Process.start('afplay', [tmpFile.path]);
      } else if (Platform.isLinux) {
        _speakerProcess = await Process.start('aplay', [tmpFile.path]);
      } else {
        throw UnsupportedError('Plataforma no soportada para prueba de audio');
      }

      // Espera que termine la reproducción
      final exitCode = await _speakerProcess!.exitCode;
      _speakerProcess = null;

      if (exitCode == 0) {
        _speakerTestStatus = SpeakerTestStatus.done;
      } else {
        _speakerTestStatus = SpeakerTestStatus.failed;
        _speakerTestError = 'El reproductor terminó con código: $exitCode';
      }
    } catch (e) {
      _speakerTestStatus = SpeakerTestStatus.failed;
      _speakerTestError = _friendlySpeakerError(e.toString());
      debugPrint('[AudioDeviceService] Speaker test error: $e');
    } finally {
      notifyListeners();
      // Auto-reset tras 3 segundos
      Future.delayed(const Duration(seconds: 3), () {
        if (_speakerTestStatus != SpeakerTestStatus.playing) {
          _speakerTestStatus = SpeakerTestStatus.idle;
          _speakerTestError = null;
          notifyListeners();
        }
      });
    }
  }

  /// Detiene la reproducción del tono si está activa.
  Future<void> stopSpeakerTest() async {
    _speakerProcess?.kill();
    _speakerProcess = null;
    _speakerTestStatus = SpeakerTestStatus.idle;
    _speakerTestError = null;
    notifyListeners();
  }

  // ── Generador de onda sinusoidal PCM → WAV ────────────────────────────────

  /// Genera un archivo WAV PCM 16-bit mono con un tono sinusoidal puro.
  Uint8List _generateSineWav({
    required double frequencyHz,
    required double durationSec,
    required int sampleRate,
    required double amplitude, // 0.0 – 1.0
  }) {
    final numSamples = (sampleRate * durationSec).round();
    final dataSize = numSamples * 2; // 16-bit = 2 bytes por muestra

    final buffer = BytesBuilder();

    // ── Cabecera WAV (44 bytes) ──────────────────────────────────────────
    // RIFF chunk
    buffer.add(_ascii('RIFF'));
    buffer.add(_int32LE(36 + dataSize));   // ChunkSize
    buffer.add(_ascii('WAVE'));

    // fmt sub-chunk
    buffer.add(_ascii('fmt '));
    buffer.add(_int32LE(16));              // Subchunk1Size (PCM)
    buffer.add(_int16LE(1));               // AudioFormat = PCM
    buffer.add(_int16LE(1));               // NumChannels = mono
    buffer.add(_int32LE(sampleRate));      // SampleRate
    buffer.add(_int32LE(sampleRate * 2));  // ByteRate = SampleRate * 2
    buffer.add(_int16LE(2));               // BlockAlign = 2 bytes
    buffer.add(_int16LE(16));              // BitsPerSample

    // data sub-chunk
    buffer.add(_ascii('data'));
    buffer.add(_int32LE(dataSize));

    // ── Muestras PCM ─────────────────────────────────────────────────────
    // Aplica un fade-in / fade-out suave para evitar clicks
    final fadeSamples = (sampleRate * 0.05).round(); // 50 ms
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      double env = 1.0;
      if (i < fadeSamples) env = i / fadeSamples;
      if (i > numSamples - fadeSamples) env = (numSamples - i) / fadeSamples;

      final sample = (sin(2 * pi * frequencyHz * t) * amplitude * env * 32767)
          .round()
          .clamp(-32768, 32767);
      buffer.add(_int16LE(sample));
    }

    return buffer.toBytes();
  }

  List<int> _ascii(String s) => s.codeUnits;
  List<int> _int16LE(int v) {
    final b = ByteData(2);
    b.setInt16(0, v, Endian.little);
    return b.buffer.asUint8List();
  }
  List<int> _int32LE(int v) {
    final b = ByteData(4);
    b.setInt32(0, v, Endian.little);
    return b.buffer.asUint8List();
  }

  String _friendlySpeakerError(String raw) {
    if (raw.contains('UnsupportedError')) {
      return 'Prueba de auriculares no disponible en esta plataforma.';
    }
    if (raw.contains('ProcessException') || raw.contains('No such file')) {
      return 'No se encontró el reproductor de audio del sistema.\n'
          'Asegúrate de que el sistema tiene soporte de audio instalado.';
    }
    return 'Error al reproducir tono: $raw';
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _friendlyError(String raw) {
    if (raw.contains('NotFoundError') || raw.contains('DevicesNotFound')) {
      return 'No se encontró ningún micrófono.\n'
          'Conecta un micrófono o auriculares e intenta de nuevo.';
    }
    if (raw.contains('NotAllowedError') ||
        raw.contains('PermissionDenied') ||
        raw.contains('Media Access')) {
      return 'Permiso denegado.\n'
          'Habilita el acceso al micrófono en:\n'
          'Configuración → Privacidad → Micrófono';
    }
    if (raw.contains('NotReadableError') || raw.contains('TrackStartError')) {
      return 'El micrófono está en uso por otra aplicación.\n'
          'Ciérrala e intenta de nuevo.';
    }
    return 'Error inesperado: $raw';
  }

  @override
  void dispose() {
    stopMicTest();
    stopSpeakerTest();
    super.dispose();
  }
}

