import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'app_properties.dart';

// Plataformas móviles que soportan setSpeakerphoneOn
bool get _isMobilePlatform =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// Estado de registro SIP.
enum RegStatus { none, connecting, registered, unregistered, failed }

/// Estado de la llamada activa.
enum CallStatus { none, ringing, calling, active, held, ended }

/// Servicio singleton que gestiona la pila SIP y las llamadas de audio.
class SipService extends ChangeNotifier implements SipUaHelperListener {
  SipService._();
  static final SipService instance = SipService._();

  final SIPUAHelper _helper = SIPUAHelper();

  // ── Estado observable ────────────────────────────────────────────────────
  RegStatus regStatus = RegStatus.none;
  String regStatusText = '';

  CallStatus callStatus = CallStatus.none;
  Call? activeCall;
  String? remoteIdentity;
  bool isMuted = false;
  bool isSpeaker = false;
  bool isOnHold = false;

  // Stream remoto para reproducir audio
  MediaStream? remoteStream;

  // ── Inicialización ────────────────────────────────────────────────────────

  /// Registra en el servidor SIP usando la configuración proporcionada.
  Future<void> register({
    required String uri,
    required String authUser,
    required String password,
    required String wsUrl,
    String? displayName,
    List<Map<String, String>>? iceServers,
    bool allowBadCertificate = false,
  }) async {
    // ── Log de configuración de registro ─────────────────────────────────
    debugPrint(
      '[WEBRTC REGISTER CONFIG]\n'
      '  uri                  : $uri\n'
      '  authUser             : $authUser\n'
      '  password             : ${password.isNotEmpty ? '***' : '(vacío)'}\n'
      '  wsUrl                : $wsUrl\n'
      '  displayName          : ${displayName ?? authUser}\n'
      '  allowBadCert         : $allowBadCertificate\n'
      '  register_expires     : ${AppProperties.registerExpires}s\n'
      '  registrationExpires  : ${AppProperties.registrationExpires}s (referencia)\n'
      '  iceTransportPolicy   : ${AppProperties.iceTransportPolicy}\n'
      '  iceServers           : ${iceServers?.map((s) => s.toString()).join(', ') ?? 'null'}',
    );
    _helper.removeSipUaHelperListener(this);
    _helper.addSipUaHelperListener(this);

    final wsSettings = WebSocketSettings()
      ..allowBadCertificate = allowBadCertificate;

    final settings = UaSettings()
      ..webSocketUrl = wsUrl
      ..webSocketSettings = wsSettings
      ..transportType = TransportType.WS
      ..uri = uri
      ..authorizationUser = authUser
      ..password = password
      ..displayName = displayName ?? authUser
      ..userAgent = 'FlutterSoftphone/1.0'
      ..register = true
      ..register_expires = AppProperties.registerExpires
      ..iceTransportPolicy = IceTransportPolicy.RELAY
      ..iceServers = iceServers ??
          [
            {'urls': 'stun:stun.l.google.com:19302'}
          ];

    regStatus = RegStatus.connecting;
    regStatusText = 'Conectando…';
    notifyListeners();

    await _helper.start(settings);
  }

  /// Desregistra del servidor.
  Future<void> unregister() async {
    if (_helper.registered) {
      await _helper.unregister();
    }
  }

  // ── Llamadas ──────────────────────────────────────────────────────────────

  /// Inicia una llamada saliente de solo audio.
  Future<bool> call(String target) async {
    if (!_helper.registered) return false;
    return _helper.call(target, voiceOnly: true);
  }

  /// Acepta una llamada entrante.
  void answerCall() {
    if (activeCall == null) return;
    activeCall!.answer(_helper.buildCallOptions(true));
  }

  /// Rechaza o cuelga la llamada activa.
  void hangUp() {
    if (activeCall == null) return;
    activeCall!.hangup();
  }

  /// Alterna mute de audio.
  void toggleMute() {
    if (activeCall == null) return;
    if (isMuted) {
      activeCall!.unmute(true, false);
    } else {
      activeCall!.mute(true, false);
    }
  }

  /// Alterna hold / unhold de la llamada activa.
  void toggleHold() {
    if (activeCall == null) return;
    if (isOnHold) {
      activeCall!.unhold();
    } else {
      activeCall!.hold();
    }
  }

  /// Alterna altavoz / auricular (solo Android e iOS).
  Future<void> toggleSpeaker() async {
    isSpeaker = !isSpeaker;
    if (_isMobilePlatform) {
      try {
        await webrtc.Helper.setSpeakerphoneOn(isSpeaker);
      } catch (e) {
        debugPrint('[SIP] setSpeakerphoneOn error: $e');
      }
    }
    notifyListeners();
  }

  // ── SipUaHelperListener ───────────────────────────────────────────────────

  @override
  void transportStateChanged(TransportState state) {
    debugPrint('[SIP] Transport: ${state.state}');
  }

  @override
  void registrationStateChanged(RegistrationState state) {
    debugPrint('[SIP] Registration: ${state.state}');
    switch (state.state) {
      case RegistrationStateEnum.REGISTERED:
        regStatus = RegStatus.registered;
        regStatusText = 'Registrado';
        break;
      case RegistrationStateEnum.UNREGISTERED:
        regStatus = RegStatus.unregistered;
        regStatusText = 'No registrado';
        break;
      case RegistrationStateEnum.REGISTRATION_FAILED:
        regStatus = RegStatus.failed;
        regStatusText = 'Error: ${state.cause?.cause ?? "fallo de registro"}';
        break;
      default:
        regStatus = RegStatus.none;
        regStatusText = '';
    }
    notifyListeners();
  }

  @override
  void callStateChanged(Call call, CallState state) {
    debugPrint('[SIP] Call state: ${state.state}');
    switch (state.state) {
      case CallStateEnum.CALL_INITIATION:
        activeCall = call;
        remoteIdentity = call.remote_identity ?? call.remote_display_name;
        callStatus = call.direction == Direction.incoming
            ? CallStatus.ringing
            : CallStatus.calling;
        isMuted = false;
        break;

      case CallStateEnum.PROGRESS:
      case CallStateEnum.CONNECTING:
        callStatus = CallStatus.calling;
        break;

      case CallStateEnum.ACCEPTED:
      case CallStateEnum.CONFIRMED:
        callStatus = CallStatus.active;
        break;

      case CallStateEnum.STREAM:
        // Guardamos el stream remoto para reproducción
        if (state.originator == Originator.remote && state.stream != null) {
          remoteStream = state.stream;
        }
        break;

      case CallStateEnum.MUTED:
        isMuted = true;
        break;

      case CallStateEnum.UNMUTED:
        isMuted = false;
        break;

      case CallStateEnum.HOLD:
        isOnHold = true;
        callStatus = CallStatus.held;
        break;

      case CallStateEnum.UNHOLD:
        isOnHold = false;
        callStatus = CallStatus.active;
        break;

      case CallStateEnum.FAILED:
      case CallStateEnum.ENDED:
        activeCall = null;
        remoteIdentity = null;
        remoteStream = null;
        callStatus = CallStatus.ended;
        isMuted = false;
        isOnHold = false;
        if (isSpeaker) {
          isSpeaker = false;
          if (_isMobilePlatform) {
            webrtc.Helper.setSpeakerphoneOn(false).ignore();
          }
        }
        break;

      default:
        break;
    }
    notifyListeners();

    // Restablece estado `ended` a `none` en el próximo frame para que
    // la UI tenga tiempo de mostrar el mensaje de llamada terminada.
    if (callStatus == CallStatus.ended) {
      Future.delayed(const Duration(seconds: 2), () {
        callStatus = CallStatus.none;
        notifyListeners();
      });
    }
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {}

  @override
  void onNewNotify(Notify ntf) {}

  @override
  void onNewReinvite(ReInvite event) {}
}

