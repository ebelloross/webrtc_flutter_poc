import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_config.dart';
import 'app_properties.dart';
import 'http_service.dart';
import 'sip_service.dart';
import 'main.dart';

class SplashScreen extends StatefulWidget {
  final AppConfig config;
  const SplashScreen({super.key, required this.config});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _subtitleFade;

  // Estado del proceso de auto-inicio
  String _statusText = 'Iniciando…';
  bool _hasError = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _fadeAnim = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeIn),
    );

    _scaleAnim = Tween<double>(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack),
      ),
    );

    _subtitleFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.55, 1.0, curve: Curves.easeIn),
    );

    _controller.forward();

    // Inicia el proceso de auto-login/registro tras la animación de entrada
    Future.delayed(const Duration(milliseconds: 800), _autoInit);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ── Lógica de inicialización ──────────────────────────────────────────────

  void _setStatus(String text, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _statusText = text;
      _hasError = error;
    });
  }

  Future<void> _autoInit() async {
    final prefs = await SharedPreferences.getInstance();
    final zonitelUser = prefs.getString('zonitel_username') ?? '';
    final zonitelPass = prefs.getString('zonitel_password') ?? '';

    if (zonitelUser.isNotEmpty) {
      // ── Ruta A: credenciales Zonitel guardadas ──────────────────────────
      await _autoLoginZonitel(zonitelUser, zonitelPass);
    } else if (widget.config.username.isNotEmpty &&
        widget.config.signalingUrl.isNotEmpty) {
      // ── Ruta B: config SIP directa guardada ────────────────────────────
      await _autoRegisterSip();
    } else {
      // ── Sin configuración previa ────────────────────────────────────────
      _setStatus('Sin configuración previa');
      await Future.delayed(const Duration(milliseconds: 800));
      _goToHome();
    }
  }

  /// Login Zonitel → extrae extensión → registra WebRTC automáticamente.
  Future<void> _autoLoginZonitel(String username, String password) async {
    _setStatus('Iniciando sesión en Zonitel…');

    final result = await HttpService.instance.login(
      username: username,
      password: password,
    );

    if (!mounted) return;

    if (!result.success) {
      _setStatus(
        'No se pudo iniciar sesión: ${result.errorMessage ?? 'Error desconocido'}',
        error: true,
      );
      await Future.delayed(const Duration(milliseconds: 1500));
      _goToHome();
      return;
    }

    if (result.sipExtension == null) {
      _setStatus('Login exitoso, sin datos de extensión', error: true);
      await Future.delayed(const Duration(milliseconds: 1500));
      _goToHome();
      return;
    }

    // Actualiza la config con los datos de la extensión
    final ext = result.sipExtension!;
    widget.config
      ..username = ext.extension
      ..password = ext.password
      ..signalingUrl = ext.wsUrl
      ..turnUrl = AppProperties.turnUrl
      ..turnUser = AppProperties.turnUser
      ..turnPass = AppProperties.turnPassword;
    await widget.config.save();

    await _registerSipWithStatus();
  }

  /// Registra usando la config SIP guardada directamente (tab Login WebRTC).
  Future<void> _autoRegisterSip() async {
    _setStatus('Conectando con configuración guardada…');
    await _registerSipWithStatus();
  }

  /// Ejecuta el registro SIP y espera el resultado (éxito, fallo o timeout).
  Future<void> _registerSipWithStatus() async {
    _setStatus('Registrando en WebRTC…');

    final sip = SipService.instance;

    try {
      await sip.register(
        uri: widget.config.sipUri,
        authUser: widget.config.username,
        password: widget.config.password,
        wsUrl: widget.config.signalingUrl,
        iceServers: widget.config.iceServers(),
        allowBadCertificate: true,
      );
    } catch (e) {
      _setStatus('Error al iniciar registro: $e', error: true);
      await Future.delayed(const Duration(milliseconds: 1500));
      _goToHome();
      return;
    }

    // Espera hasta que el estado cambie o expire el timeout (8 s)
    const checkInterval = Duration(milliseconds: 200);
    const timeout = Duration(seconds: 8);
    var elapsed = Duration.zero;

    while (elapsed < timeout) {
      await Future.delayed(checkInterval);
      elapsed += checkInterval;
      if (!mounted) return;

      final status = sip.regStatus;
      if (status == RegStatus.registered) {
        _setStatus('✅ Registrado correctamente');
        await Future.delayed(const Duration(milliseconds: 700));
        _goToHome();
        return;
      } else if (status == RegStatus.failed) {
        _setStatus('❌ Registro fallido: ${sip.regStatusText}', error: true);
        await Future.delayed(const Duration(milliseconds: 1500));
        _goToHome();
        return;
      }
    }

    // Timeout sin respuesta definitiva → continúa de todas formas
    _setStatus('Tiempo de espera agotado', error: true);
    await Future.delayed(const Duration(milliseconds: 1000));
    _goToHome();
  }

  // ── Navegación ────────────────────────────────────────────────────────────

  void _goToHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, _, __) => HomePage(config: widget.config),
        transitionsBuilder: (context, animation, _, child) => FadeTransition(
          opacity: animation,
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF1A237E);
    const accent = Color(0xFF3F51B5);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [primary, accent, Color(0xFF283593)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Ícono animado ──────────────────────────────────────
                ScaleTransition(
                  scale: _scaleAnim,
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.phone_in_talk_rounded,
                        size: 64,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // ── Nombre de la app ───────────────────────────────────
                FadeTransition(
                  opacity: _fadeAnim,
                  child: const Text(
                    'Zonitel',
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 2,
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // ── Subtítulo ──────────────────────────────────────────
                FadeTransition(
                  opacity: _subtitleFade,
                  child: Text(
                    'Comunicaciones WebRTC',
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.white.withValues(alpha: 0.75),
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ),

                const SizedBox(height: 64),

                // ── Indicador de carga ─────────────────────────────────
                if (!_hasError)
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  )
                else
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange.shade300,
                    size: 28,
                  ),

                const SizedBox(height: 14),

                // ── Texto de estado del proceso ────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      _statusText,
                      key: ValueKey(_statusText),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: _hasError
                            ? Colors.orange.shade300
                            : Colors.white.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w300,
                      ),
                    ),
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

