import 'dart:math';
import 'package:flutter/material.dart';
import 'sip_service.dart';

class IncomingCallScreen extends StatefulWidget {
  final String callerName;

  const IncomingCallScreen({super.key, required this.callerName});

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with TickerProviderStateMixin {
  // ── Animaciones ───────────────────────────────────────────────────────────
  late final AnimationController _pulseCtrl;
  late final AnimationController _ringCtrl;
  late final AnimationController _slideCtrl;

  late final Animation<double> _pulse1;
  late final Animation<double> _pulse2;
  late final Animation<double> _pulse3;
  late final Animation<double> _ringRotation;
  late final Animation<Offset> _acceptSlide;
  late final Animation<Offset> _rejectSlide;
  late final Animation<double> _fadeIn;

  final SipService _sip = SipService.instance;

  @override
  void initState() {
    super.initState();
    _sip.addListener(_onSipChanged);

    // ── Pulsos de fondo (ondas expansivas) ───────────────────────────────
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _pulse1 = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
          parent: _pulseCtrl,
          curve: const Interval(0.0, 0.8, curve: Curves.easeOut)),
    );
    _pulse2 = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
          parent: _pulseCtrl,
          curve: const Interval(0.2, 1.0, curve: Curves.easeOut)),
    );
    _pulse3 = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
          parent: _pulseCtrl,
          curve: const Interval(0.4, 1.0, curve: Curves.easeOut)),
    );

    // ── Rotación del ícono de teléfono ────────────────────────────────────
    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _ringRotation = Tween<double>(begin: -0.12, end: 0.12).animate(
      CurvedAnimation(parent: _ringCtrl, curve: Curves.easeInOut),
    );

    // ── Slide de entrada de botones ───────────────────────────────────────
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();

    _acceptSlide = Tween<Offset>(
      begin: const Offset(1.5, 0),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _slideCtrl, curve: Curves.elasticOut));

    _rejectSlide = Tween<Offset>(
      begin: const Offset(-1.5, 0),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _slideCtrl, curve: Curves.elasticOut));

    _fadeIn = CurvedAnimation(parent: _slideCtrl, curve: Curves.easeIn);
  }

  @override
  void dispose() {
    _sip.removeListener(_onSipChanged);
    _pulseCtrl.dispose();
    _ringCtrl.dispose();
    _slideCtrl.dispose();
    super.dispose();
  }

  void _onSipChanged() {
    if (!mounted) return;
    // Solo cerrar si la llamada fue cancelada externamente (no por el usuario)
    // active/held = fue aceptada, ended = terminó → cerrar
    final s = _sip.callStatus;
    if (s == CallStatus.ended || s == CallStatus.none) {
      _safeClose();
    }
  }

  /// Cierra la pantalla de forma segura garantizando que el HomePage quede visible.
  void _safeClose() {
    if (!mounted) return;
    // Si todavía hay rutas detrás, hacemos pop; si no, reemplazamos con home.
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _accept() {
    _sip.answerCall();
    _safeClose();
  }

  void _reject() {
    _sip.hangUp();
    _safeClose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0D1B2A),
              Color(0xFF1B2A4A),
              Color(0xFF0D2137),
            ],
          ),
        ),
        child: Stack(
          children: [
            // ── Partículas decorativas de fondo ──────────────────────
            ..._buildParticles(size),

            // ── Contenido principal ───────────────────────────────────
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 60),

                  // ── Etiqueta "Llamada entrante" ───────────────────
                  FadeTransition(
                    opacity: _fadeIn,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF4CAF50),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'LLAMADA ENTRANTE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 2.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 60),

                  // ── Avatar con ondas de pulso ─────────────────────
                  SizedBox(
                    width: 220,
                    height: 220,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Onda 3 (más exterior)
                        AnimatedBuilder(
                          animation: _pulse3,
                          builder: (_, __) => _buildPulseRing(
                            220 * _pulse3.value,
                            (1 - _pulse3.value) * 0.25,
                          ),
                        ),
                        // Onda 2
                        AnimatedBuilder(
                          animation: _pulse2,
                          builder: (_, __) => _buildPulseRing(
                            180 * _pulse2.value,
                            (1 - _pulse2.value) * 0.35,
                          ),
                        ),
                        // Onda 1 (más interior)
                        AnimatedBuilder(
                          animation: _pulse1,
                          builder: (_, __) => _buildPulseRing(
                            140 * _pulse1.value,
                            (1 - _pulse1.value) * 0.45,
                          ),
                        ),

                        // Avatar del llamante
                        Container(
                          width: 110,
                          height: 110,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFF2196F3),
                                Color(0xFF1565C0),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF2196F3)
                                    .withValues(alpha: 0.5),
                                blurRadius: 30,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: AnimatedBuilder(
                            animation: _ringRotation,
                            builder: (_, __) => Transform.rotate(
                              angle: _ringRotation.value,
                              child: const Icon(
                                Icons.phone_in_talk_rounded,
                                size: 52,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 36),

                  // ── Nombre del llamante ───────────────────────────
                  FadeTransition(
                    opacity: _fadeIn,
                    child: Text(
                      widget.callerName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  FadeTransition(
                    opacity: _fadeIn,
                    child: Text(
                      'Llamada de voz',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 15,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 1,
                      ),
                    ),
                  ),

                  const Spacer(),

                  // ── Botones Aceptar / Rechazar ────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(40, 0, 40, 60),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Rechazar
                        SlideTransition(
                          position: _rejectSlide,
                          child: _CallButton(
                            icon: Icons.call_end_rounded,
                            label: 'Rechazar',
                            color: const Color(0xFFE53935),
                            onTap: _reject,
                          ),
                        ),

                        // Aceptar
                        SlideTransition(
                          position: _acceptSlide,
                          child: _CallButton(
                            icon: Icons.call_rounded,
                            label: 'Aceptar',
                            color: const Color(0xFF43A047),
                            onTap: _accept,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _buildPulseRing(double size, double opacity) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFF2196F3).withValues(alpha: opacity),
            width: 1.5,
          ),
        ),
      );

  List<Widget> _buildParticles(Size size) {
    final rng = Random(42);
    return List.generate(18, (i) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final r = rng.nextDouble() * 3 + 1;
      final op = rng.nextDouble() * 0.18 + 0.05;
      return Positioned(
        left: x,
        top: y,
        child: Container(
          width: r * 2,
          height: r * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: op),
          ),
        ),
      );
    });
  }
}

// ── Widget de botón de llamada ─────────────────────────────────────────────

class _CallButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _CallButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  State<_CallButton> createState() => _CallButtonState();
}

class _CallButtonState extends State<_CallButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final Animation<double> _pressScale;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.88,
      upperBound: 1.0,
      value: 1.0,
    );
    _pressScale = _pressCtrl;
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _pressCtrl.reverse(),
      onTapUp: (_) {
        _pressCtrl.forward();
        widget.onTap();
      },
      onTapCancel: () => _pressCtrl.forward(),
      child: ScaleTransition(
        scale: _pressScale,
        child: Column(
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color,
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.55),
                    blurRadius: 22,
                    spreadRadius: 3,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(widget.icon, color: Colors.white, size: 36),
            ),
            const SizedBox(height: 12),
            Text(
              widget.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

