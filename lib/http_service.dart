import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_properties.dart';

/// Datos de la extensión SIP devuelta por el API de Zonitel.
class SipExtension {
  final String extension;
  final String password;
  final String user;

  const SipExtension({
    required this.extension,
    required this.password,
    required this.user,
  });

  factory SipExtension.fromJson(Map<String, dynamic> json) => SipExtension(
        extension: json['extension'] as String? ?? '',
        password: json['password'] as String? ?? '',
        user: json['user'] as String? ?? '',
      );

  /// Construye la URL del WebSocket SIP a partir del host devuelto por la API.
  String get wsUrl => 'wss://$user:7443/ws';

  @override
  String toString() =>
      'SipExtension(extension: $extension, user: $user)';
}

/// Resultado del login de Zonitel.
class LoginResult {
  final bool success;
  final String? token;
  final String? errorMessage;
  /// Extensión SIP lista para usar en el registro WebRTC.
  final SipExtension? sipExtension;
  /// JSON completo de la respuesta para uso posterior.
  final Map<String, dynamic>? data;

  LoginResult({
    required this.success,
    this.token,
    this.errorMessage,
    this.sipExtension,
    this.data,
  });
}

/// Servicio HTTP para operaciones con el backend de Zonitel.
class HttpService {
  // ── URL base configurable ──────────────────────────────────────────────
  /// URL del endpoint de login. Definida en AppProperties.
  static String loginUrl = AppProperties.apiLoginUrl;

  // Singleton
  HttpService._();
  static final HttpService instance = HttpService._();

  /// Realiza un POST al endpoint de login con [username] y [password].
  /// Devuelve un [LoginResult] con el resultado de la operación.
  Future<LoginResult> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(loginUrl),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'username': username,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final body = _tryDecode(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final token = body?['token'] as String?;

        // Extrae user.extension del JSON
        SipExtension? sipExt;
        final userMap = body?['user'] as Map<String, dynamic>?;
        final extMap = userMap?['extension'] as Map<String, dynamic>?;
        if (extMap != null) {
          sipExt = SipExtension.fromJson(extMap);
        }

        return LoginResult(
          success: true,
          token: token,
          sipExtension: sipExt,
          data: body,
        );
      } else {
        final msg = body?['message'] as String? ??
            body?['error'] as String? ??
            'Error ${response.statusCode}';
        return LoginResult(success: false, errorMessage: msg);
      }
    } on Exception catch (e) {
      return LoginResult(
        success: false,
        errorMessage: e.toString(),
      );
    }
  }

  Map<String, dynamic>? _tryDecode(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }
}

