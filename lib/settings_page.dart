import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_config.dart';
import 'app_properties.dart';
import 'sip_service.dart';
import 'http_service.dart';

// ── SettingsPage ───────────────────────────────────────────────────────────

class SettingsPage extends StatelessWidget {
  final AppConfig config;

  const SettingsPage({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: const Text('Configuración')),
        body: _ZonitelLoginTab(config: config),
      ),
      /*Scaffold(
        appBar: AppBar(
          title: const Text('Configuración'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.settings_phone), text: 'Login WebRTC'),
              Tab(icon: Icon(Icons.person), text: 'Login Zonitel'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _WebRtcLoginTab(config: config),
            _ZonitelLoginTab(config: config),
          ],
        ),
      ),*/
    );
  }
}

// ── Tab 1 : Login WebRTC ───────────────────────────────────────────────────

class _WebRtcLoginTab extends StatefulWidget {
  final AppConfig config;

  const _WebRtcLoginTab({required this.config});

  @override
  State<_WebRtcLoginTab> createState() => _WebRtcLoginTabState();
}

class _WebRtcLoginTabState extends State<_WebRtcLoginTab> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _signalingUrl;

  bool _registering = false;
  bool _showPassword = false;
  final SipService _sip = SipService.instance;

  @override
  void initState() {
    super.initState();
    _sip.addListener(_onSipChanged);
    _username = TextEditingController(text: widget.config.username);
    _password = TextEditingController(text: widget.config.password);
    _signalingUrl = TextEditingController(text: widget.config.signalingUrl);
  }

  @override
  void dispose() {
    _sip.removeListener(_onSipChanged);
    _username.dispose();
    _password.dispose();
    _signalingUrl.dispose();
    super.dispose();
  }

  void _onSipChanged() {
    if (!mounted) return;
    setState(() {});
    if (_registering) {
      if (_sip.regStatus == RegStatus.registered) {
        setState(() => _registering = false);
        _snack('✅ Registrado correctamente');
      } else if (_sip.regStatus == RegStatus.failed) {
        setState(() => _registering = false);
        _snack('❌ ${_sip.regStatusText}');
      }
    }
  }

  Future<void> _saveAndRegister() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _registering = true);

    widget.config
      ..username = _username.text.trim()
      ..password = _password.text
      ..signalingUrl = _signalingUrl.text.trim()
      ..turnUrl = AppProperties.turnUrl
      ..turnUser = AppProperties.turnUser
      ..turnPass = AppProperties.turnPassword;
    await widget.config.save();

    try {
      await _sip.register(
        uri: widget.config.sipUri,
        authUser: widget.config.username,
        password: widget.config.password,
        wsUrl: widget.config.signalingUrl,
        iceServers: widget.config.iceServers(),
        allowBadCertificate: true,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _registering = false);
        _snack('Error al iniciar registro: $e');
      }
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Color get _regColor => switch (_sip.regStatus) {
    RegStatus.registered => Colors.green,
    RegStatus.connecting => Colors.orange,
    RegStatus.failed => Colors.red,
    _ => Colors.grey,
  };

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Estado actual de registro
            Card(
              color: _regColor.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    CircleAvatar(backgroundColor: _regColor, radius: 8),
                    const SizedBox(width: 10),
                    Text(
                      _sip.regStatusText.isEmpty
                          ? 'Sin registro'
                          : _sip.regStatusText,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _username,
              decoration: const InputDecoration(labelText: 'Ext SIP (ej: 200)'),
              validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 8),

            TextFormField(
              controller: _password,
              decoration: InputDecoration(
                labelText: 'Contraseña',
                suffixIcon: IconButton(
                  icon: Icon(
                    _showPassword ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                ),
              ),
              obscureText: !_showPassword,
              validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 8),

            TextFormField(
              controller: _signalingUrl,
              decoration: const InputDecoration(
                labelText: 'WebSocket SIP (wss://…)',
              ),
              keyboardType: TextInputType.url,
              validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 30),

            FilledButton.icon(
              icon: _registering
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.cloud_done),
              label: Text(
                _registering ? 'Registrando…' : 'Guardar y Registrar',
              ),
              onPressed: _registering ? null : _saveAndRegister,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),

            if (_sip.regStatus == RegStatus.registered) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.logout),
                label: const Text('Desregistrar'),
                onPressed: () => _sip.unregister(),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Tab 2 : Login Zonitel ──────────────────────────────────────────────────

class _ZonitelLoginTab extends StatefulWidget {
  final AppConfig config;

  const _ZonitelLoginTab({required this.config});

  @override
  State<_ZonitelLoginTab> createState() => _ZonitelLoginTabState();
}

class _ZonitelLoginTabState extends State<_ZonitelLoginTab> {
  // ── Login form ──────────────────────────────────────────────────────────
  final _loginFormKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _loadingLogin = false;
  bool _showPassword = false;
  bool _loggedIn = false;
  String? _loginMessage;
  bool _isLoginError = false;

  // ── SIP / WebRTC form ───────────────────────────────────────────────────
  final _sipFormKey = GlobalKey<FormState>();
  late final TextEditingController _sipExtCtrl;
  late final TextEditingController _sipPassCtrl;
  late final TextEditingController _sipWsCtrl;

  // ignore: unused_field
  bool _showSipPass = false;
  bool _registering = false;

  final SipService _sip = SipService.instance;

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _sip.addListener(_onSipChanged);
    _sipExtCtrl = TextEditingController(text: widget.config.username);
    _sipPassCtrl = TextEditingController(text: widget.config.password);
    _sipWsCtrl = TextEditingController(text: widget.config.signalingUrl);
    _loadSavedCredentials();
  }

  /// Carga usuario y contraseña de Zonitel guardados previamente.
  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUser = prefs.getString('zonitel_username') ?? '';
    final savedPass = prefs.getString('zonitel_password') ?? '';
    if (savedUser.isNotEmpty && mounted) {
      setState(() {
        _usernameCtrl.text = savedUser;
        _passwordCtrl.text = savedPass;
      });
    }
  }

  /// Persiste usuario y contraseña de Zonitel.
  Future<void> _saveCredentials(String username, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('zonitel_username', username);
    await prefs.setString('zonitel_password', password);
  }

  @override
  void dispose() {
    _sip.removeListener(_onSipChanged);
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _sipExtCtrl.dispose();
    _sipPassCtrl.dispose();
    _sipWsCtrl.dispose();
    super.dispose();
  }

  // ── SIP listener ──────────────────────────────────────────────────────────
  void _onSipChanged() {
    if (!mounted) return;
    setState(() {});
    if (_registering) {
      if (_sip.regStatus == RegStatus.registered) {
        setState(() => _registering = false);
        _snack('✅ Registrado en WebRTC correctamente');
      } else if (_sip.regStatus == RegStatus.failed) {
        setState(() => _registering = false);
        _snack('❌ Registro WebRTC fallido: ${_sip.regStatusText}');
      }
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────
  Future<void> _doLogin() async {
    if (!_loginFormKey.currentState!.validate()) return;
    setState(() {
      _loadingLogin = true;
      _loginMessage = null;
      _isLoginError = false;
    });

    final result = await HttpService.instance.login(
      username: _usernameCtrl.text.trim(),
      password: _passwordCtrl.text,
    );

    if (!mounted) return;
    setState(() {
      _loadingLogin = false;
      _loggedIn = result.success;
      _isLoginError = !result.success;
      _loginMessage = result.success
          ? '✅ Login exitoso${result.token != null ? ' — Token recibido' : ''}'
          : '❌ ${result.errorMessage ?? 'Error desconocido'}';
    });

    // Auto-poblar campos SIP con los datos de la extensión
    if (result.success && result.sipExtension != null) {
      final ext = result.sipExtension!;
      _sipExtCtrl.text = ext.extension;
      _sipPassCtrl.text = ext.password;
      _sipWsCtrl.text = ext.wsUrl;
      // Persistir credenciales de Zonitel
      await _saveCredentials(_usernameCtrl.text.trim(), _passwordCtrl.text);
    }
  }

  Future<void> _doRegisterWebRtc() async {
    if (!_sipFormKey.currentState!.validate()) return;
    setState(() => _registering = true);

    widget.config
      ..username = _sipExtCtrl.text.trim()
      ..password = _sipPassCtrl.text
      ..signalingUrl = _sipWsCtrl.text.trim()
      ..turnUrl = AppProperties.turnUrl
      ..turnUser = AppProperties.turnUser
      ..turnPass = AppProperties.turnPassword;
    await widget.config.save();

    try {
      await _sip.register(
        uri: widget.config.sipUri,
        authUser: widget.config.username,
        password: widget.config.password,
        wsUrl: widget.config.signalingUrl,
        iceServers: widget.config.iceServers(),
        allowBadCertificate: true,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _registering = false);
        _snack('Error al iniciar registro WebRTC: $e');
      }
    }
  }

  void _doLogout() {
    setState(() {
      _loggedIn = false;
      _loginMessage = null;
      _usernameCtrl.clear();
      _passwordCtrl.clear();
    });
    if (_sip.regStatus == RegStatus.registered) _sip.unregister();
    // Borra las credenciales persistidas
    SharedPreferences.getInstance().then(
      (prefs) => prefs
        ..remove('zonitel_username')
        ..remove('zonitel_password'),
    );
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // ── Helpers UI ────────────────────────────────────────────────────────────
  Color get _regColor => switch (_sip.regStatus) {
    RegStatus.registered => Colors.green,
    RegStatus.connecting => Colors.orange,
    RegStatus.failed => Colors.red,
    _ => Colors.grey,
  };

  String get _regLabel => _sip.regStatusText.isNotEmpty
      ? _sip.regStatusText
      : 'Sin registro WebRTC';

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),

          // ── Ícono + título ──────────────────────────────────────────────
          Icon(
            Icons.language,
            size: 56,
            color: colorScheme.primary.withValues(alpha: 0.75),
          ),
          const SizedBox(height: 6),
          Text(
            'Iniciar sesión en Zonitel',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 20),

          // ── Formulario de login ─────────────────────────────────────────
          Form(
            key: _loginFormKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _usernameCtrl,
                  enabled: !_loggedIn,
                  decoration: const InputDecoration(
                    labelText: 'Usuario',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordCtrl,
                  enabled: !_loggedIn,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showPassword ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                  obscureText: !_showPassword,
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: 16),

                // Botón Login / Cerrar sesión
                _loggedIn
                    ? OutlinedButton.icon(
                        icon: const Icon(Icons.logout),
                        label: const Text('Cerrar sesión'),
                        onPressed: _doLogout,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                        ),
                      )
                    : FilledButton.icon(
                        icon: _loadingLogin
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.login),
                        label: Text(_loadingLogin ? 'Ingresando…' : 'Login'),
                        onPressed: _loadingLogin ? null : _doLogin,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),

                // Mensaje de resultado del login
                if (_loginMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: (_isLoginError ? Colors.red : Colors.green)
                          .withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: (_isLoginError ? Colors.red : Colors.green)
                            .withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      _loginMessage!,
                      style: TextStyle(
                        color: _isLoginError
                            ? Colors.red.shade700
                            : Colors.green.shade700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Sección WebRTC (solo visible tras login exitoso) ────────────
          if (_loggedIn) ...[
            const SizedBox(height: 28),
            const Divider(),
            const SizedBox(height: 8),

            // Indicador de estado de registro WebRTC
            Card(
              color: _regColor.withValues(alpha: 0.08),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: _regColor.withValues(alpha: 0.35)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    if (_registering || _sip.regStatus == RegStatus.connecting)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _regColor,
                        ),
                      )
                    else
                      CircleAvatar(backgroundColor: _regColor, radius: 8),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _registering ? 'Registrando en WebRTC…' : _regLabel,
                        style: TextStyle(
                          fontSize: 13,
                          color: _regColor.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                    if (_sip.regStatus == RegStatus.registered)
                      Icon(
                        Icons.verified,
                        color: Colors.green.shade600,
                        size: 18,
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),
            Text(
              'Registro WebRTC / SIP',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),

            // Formulario de datos SIP
            Form(
              key: _sipFormKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Extensión siempre visible (no es sensible)
                  TextFormField(
                    controller: _sipExtCtrl,
                    readOnly: _sip.regStatus == RegStatus.registered,
                    decoration: InputDecoration(
                      labelText: 'Extensión SIP',
                      prefixIcon: const Icon(Icons.dialpad),
                      border: const OutlineInputBorder(),
                      filled: _sip.regStatus == RegStatus.registered,
                      fillColor: Colors.grey.withValues(alpha: 0.08),
                    ),
                    keyboardType: TextInputType.phone,
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Requerido' : null,
                  ),

                  // Contraseña SIP y WebSocket: ocultos cuando ya está registrado
                  /*if (_sip.regStatus != RegStatus.registered) ...[
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _sipPassCtrl,
                      decoration: InputDecoration(
                        labelText: 'Contraseña SIP',
                        prefixIcon: const Icon(Icons.vpn_key_outlined),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _showSipPass
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () =>
                              setState(() => _showSipPass = !_showSipPass),
                        ),
                      ),
                      obscureText: !_showSipPass,
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Requerido' : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _sipWsCtrl,
                      decoration: const InputDecoration(
                        labelText: 'WebSocket SIP (wss://…)',
                        prefixIcon: Icon(Icons.electrical_services),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Requerido' : null,
                    ),
                  ],*/

                  const SizedBox(height: 16),

                  // Botón Registrar / Desregistrar
                  if (_sip.regStatus == RegStatus.registered)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.cloud_off),
                      label: const Text('Desregistrar WebRTC'),
                      onPressed: () => _sip.unregister(),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                      ),
                    )
                  else
                    FilledButton.icon(
                      icon: _registering
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.cloud_done),
                      label: Text(
                        _registering ? 'Registrando…' : 'Registrar WebRTC',
                      ),
                      onPressed: _registering ? null : _doRegisterWebRtc,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
