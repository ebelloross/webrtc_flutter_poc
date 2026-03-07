/// Propiedades globales de la aplicación.
/// Modifica aquí los valores para apuntar a diferentes entornos.
abstract final class AppProperties {
  // ── Servidor TURN ─────────────────────────────────────────────────────────
  static const String turnUrl      = 'turns:turn.zonitel.com:443?transport=tcp';
  static const String turnUser     = 'zonitel';
  static const String turnPassword = 'Zon1t3l_Turn_2024!';

  // ── API Zonitel ───────────────────────────────────────────────────────────
  static const String apiLoginUrl  = 'https://kn895r3o3m.execute-api.us-east-1.amazonaws.com/api/login_check';

  // ── Registro SIP ──────────────────────────────────────────────────────────
  /// Tiempo de expiración del registro SIP en segundos (register_expires).
  static const int registerExpires     = 300;
  /// Tiempo de expiración de la sesión de registro en segundos (registration_expires).
  static const int registrationExpires = 300;
  /// Política de transporte ICE: solo candidatos RELAY (TURN).
  static const String iceTransportPolicy = 'relay';
}

