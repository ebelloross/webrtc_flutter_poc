import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'app_config.dart';
import 'sip_service.dart';
import 'settings_page.dart';
import 'splash_screen.dart';
import 'incoming_call_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Captura errores globales de Flutter (incluye InvalidStateError de WebRTC)
  FlutterError.onError = (FlutterErrorDetails details) {
    final msg = details.exception.toString();
    // Filtra errores conocidos de WebRTC en Windows para no crashear la app
    if (msg.contains('InvalidStateError') ||
        msg.contains('getUserMediaFailed') ||
        msg.contains('Missing extension byte')) {
      debugPrint('[WebRTC][Windows] Error capturado: $msg');
      return;
    }
    FlutterError.presentError(details);
  };

  // Captura errores en zonas asíncronas no manejadas
  PlatformDispatcher.instance.onError = (error, stack) {
    final msg = error.toString();
    if (msg.contains('InvalidStateError') ||
        msg.contains('getUserMediaFailed') ||
        msg.contains('Missing extension byte')) {
      debugPrint('[WebRTC][Windows] Async error capturado: $msg');
      return true; // marca como manejado
    }
    return false;
  };

  final config = AppConfig();
  await config.load();
  runApp(MyApp(config: config));
}

// ── App ────────────────────────────────────────────────────────────────────

class MyApp extends StatelessWidget {
  final AppConfig config;
  const MyApp({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zonitel CALL POC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      routes: {
        '/': (_) => SplashScreen(config: config),
        '/home': (_) => HomePage(config: config),
        '/settings': (_) => SettingsPage(config: config),
      },
    );
  }
}

// ── HomePage ───────────────────────────────────────────────────────────────

class HomePage extends StatefulWidget {
  final AppConfig config;
  const HomePage({super.key, required this.config});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _numberCtrl = TextEditingController();
  final SipService _sip = SipService.instance;
  bool _incomingCallScreenOpen = false;

  @override
  void initState() {
    super.initState();
    _sip.addListener(_onSipChanged);
  }

  @override
  void dispose() {
    _sip.removeListener(_onSipChanged);
    _numberCtrl.dispose();
    super.dispose();
  }

  void _onSipChanged() {
    if (!mounted) return;
    setState(() {});

    // Llamada entrante → mostrar pantalla full screen
    if (_sip.callStatus == CallStatus.ringing && !_incomingCallScreenOpen) {
      _showIncomingCallScreen();
    }
  }

  // ── Acciones ─────────────────────────────────────────────────────────────

  Future<void> _startCall() async {
    final callee = _numberCtrl.text.trim();
    if (callee.isEmpty) {
      _snack('Ingresa un número para llamar');
      return;
    }
    if (_sip.regStatus != RegStatus.registered) {
      _snack('Debes registrarte primero en Configuración');
      return;
    }
    // Verifica dispositivo de audio antes de llamar
    final audioError = await _sip.checkAudioDevice();
    if (audioError != null) {
      if (mounted) _showNoMicDialog(audioError);
      return;
    }
    final ok = await _sip.call(callee);
    if (!ok && mounted) _snack('No se pudo iniciar la llamada');
  }

  void _showNoMicDialog(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.mic_off_rounded, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Sin micrófono'),
          ],
        ),
        content: Text(message, style: const TextStyle(height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  void _hangUp() => _sip.hangUp();
  void _toggleMute() => _sip.toggleMute();
  void _toggleHold() => _sip.toggleHold();
  Future<void> _toggleSpeaker() => _sip.toggleSpeaker();

  void _showIncomingCallScreen() {
    _incomingCallScreenOpen = true;
    Navigator.of(context)
        .push(
          PageRouteBuilder(
            fullscreenDialog: false,
            opaque: false,          // permite ver la ruta anterior durante la transición
            barrierColor: Colors.transparent,
            pageBuilder: (context, _, __) => IncomingCallScreen(
              callerName: _sip.remoteIdentity ?? 'Desconocido',
            ),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              // Entrada: slide desde abajo
              // Salida: slide hacia abajo + fade
              final slide = Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              );
              final fade = Tween<double>(begin: 0.0, end: 1.0).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
                ),
              );
              return FadeTransition(
                opacity: fade,
                child: SlideTransition(position: slide, child: child),
              );
            },
            transitionDuration: const Duration(milliseconds: 450),
            reverseTransitionDuration: const Duration(milliseconds: 350),
          ),
        )
        .whenComplete(() {
          _incomingCallScreenOpen = false;
          // Fuerza rebuild del HomePage para que refleje el estado actualizado
          if (mounted) setState(() {});
        });
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // ── Helpers de UI ─────────────────────────────────────────────────────────

  Color get _regColor => switch (_sip.regStatus) {
        RegStatus.registered => Colors.green,
        RegStatus.connecting => Colors.orange,
        RegStatus.failed => Colors.red,
        _ => Colors.grey,
      };

  String get _regLabel =>
      _sip.regStatusText.isNotEmpty ? _sip.regStatusText : 'Sin registro';

  bool get _inCall =>
      _sip.callStatus != CallStatus.none &&
      _sip.callStatus != CallStatus.ended;

  String get _callLabel => switch (_sip.callStatus) {
        CallStatus.ringing => '📲 Llamada entrante…',
        CallStatus.calling => '📡 Llamando…',
        CallStatus.active =>
          '✅ En llamada con ${_sip.remoteIdentity ?? ""}',
        CallStatus.held => '⏸ En espera',
        CallStatus.ended => '📵 Llamada terminada',
        _ => '',
      };

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final buttons = ['1','2','3','4','5','6','7','8','9','*','0','#'];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Zonitel Call'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Chip(
              avatar: CircleAvatar(backgroundColor: _regColor, radius: 6),
              label: Text(_regLabel, style: const TextStyle(fontSize: 11)),
              padding: EdgeInsets.zero,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner de estado de llamada
          if (_inCall || _sip.callStatus == CallStatus.ended)
            Container(
              width: double.infinity,
              color: _inCall ? Colors.indigo.shade50 : Colors.grey.shade100,
              padding:
                  const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Text(_callLabel,
                  style: const TextStyle(fontSize: 14),
                  textAlign: TextAlign.center),
            ),

          const SizedBox(height: 8),

          // Display del número marcado
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _numberCtrl,
              decoration: const InputDecoration(
                labelText: 'Número / Extensión',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),

          // Teclado numérico
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.6,
              ),
              itemCount: buttons.length,
              itemBuilder: (_, i) {
                final label = buttons[i];
                return ElevatedButton(
                  onPressed: _inCall
                      ? () => _sip.activeCall?.sendDTMF(label)
                      : () {
                          _numberCtrl.text += label;
                          _numberCtrl.selection = TextSelection.fromPosition(
                              TextPosition(offset: _numberCtrl.text.length));
                        },
                  child: Text(label, style: const TextStyle(fontSize: 22)),
                );
              },
            ),
          ),

          // Botonera de llamada
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: _inCall
                ? _ActiveCallControls(
                    sip: _sip,
                    onMute: _toggleMute,
                    onSpeaker: _toggleSpeaker,
                    onHold: _toggleHold,
                    onHangUp: _hangUp,
                  )
                : FilledButton.icon(
                    icon: const Icon(Icons.call),
                    label: const Text('Llamar'),
                    onPressed: _startCall,
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48)),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Panel de controles durante la llamada activa ──────────────────────────

class _ActiveCallControls extends StatelessWidget {
  final SipService sip;
  final VoidCallback onMute;
  final Future<void> Function() onSpeaker;
  final VoidCallback onHold;
  final VoidCallback onHangUp;

  const _ActiveCallControls({
    required this.sip,
    required this.onMute,
    required this.onSpeaker,
    required this.onHold,
    required this.onHangUp,
  });

  @override
  Widget build(BuildContext context) {
    final isHeld = sip.callStatus == CallStatus.held;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Fila superior: Mute · Altavoz (solo móvil) · Hold ───────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _ControlButton(
              icon: sip.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
              label: sip.isMuted ? 'Activar mic' : 'Silenciar',
              active: sip.isMuted,
              activeColor: Colors.orange,
              onTap: onMute,
            ),
            // Altavoz solo disponible en Android e iOS
            if (defaultTargetPlatform == TargetPlatform.android ||
                defaultTargetPlatform == TargetPlatform.iOS)
              _ControlButton(
                icon: sip.isSpeaker
                    ? Icons.volume_up_rounded
                    : Icons.volume_down_rounded,
                label: sip.isSpeaker ? 'Auricular' : 'Altavoz',
                active: sip.isSpeaker,
                activeColor: Colors.blue,
                onTap: onSpeaker,
              ),
            _ControlButton(
              icon: isHeld
                  ? Icons.play_circle_outline_rounded
                  : Icons.pause_circle_outline_rounded,
              label: isHeld ? 'Reanudar' : 'Hold',
              active: isHeld,
              activeColor: Colors.purple,
              onTap: onHold,
            ),
          ],
        ),

        const SizedBox(height: 16),

        // ── Botón Colgar ─────────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: const Icon(Icons.call_end_rounded),
            label: const Text('Colgar'),
            onPressed: onHangUp,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Botón de control individual ───────────────────────────────────────────

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? activeColor.withValues(alpha: 0.12)
              : Colors.grey.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active
                ? activeColor.withValues(alpha: 0.5)
                : Colors.grey.withValues(alpha: 0.2),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                icon,
                key: ValueKey(icon),
                size: 28,
                color: active ? activeColor : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: active ? activeColor : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
