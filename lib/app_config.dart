import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_properties.dart';

class AppConfig extends ChangeNotifier {
  String username = '';
  String password = '';
  String signalingUrl = '';
  String turnUrl = '';
  String turnUser = '';
  String turnPass = '';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    username = prefs.getString('username') ?? '';
    password = prefs.getString('password') ?? '';
    signalingUrl = prefs.getString('signalingUrl') ?? '';
    turnUrl = prefs.getString('turnUrl') ?? '';
    turnUser = prefs.getString('turnUser') ?? '';
    turnPass = prefs.getString('turnPass') ?? '';
    notifyListeners();
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', username);
    await prefs.setString('password', password);
    await prefs.setString('signalingUrl', signalingUrl);
    await prefs.setString('turnUrl', turnUrl);
    await prefs.setString('turnUser', turnUser);
    await prefs.setString('turnPass', turnPass);
    notifyListeners();
  }

  /// Construye la lista de ICE servers para sip_ua (solo TURN, sin STUN).
  List<Map<String, String>> iceServers() {
    final servers = <Map<String, String>>[];
    if (turnUrl.isNotEmpty) {
      final entry = <String, String>{'urls': turnUrl};
      if (turnUser.isNotEmpty) entry['username'] = turnUser;
      if (turnPass.isNotEmpty) entry['credential'] = turnPass;
      servers.add(entry);
    }
    if (servers.isEmpty) {
      // Fallback: TURN de Zonitel por defecto
      servers.add({
        'urls': AppProperties.turnUrl,
        'username': AppProperties.turnUser,
        'credential': AppProperties.turnPassword,
      });
    }
    return servers;
  }

  /// URI SIP derivada del usuario y el host del WS.
  String get sipUri {
    final host = _hostFromWs(signalingUrl);
    return 'sip:$username@$host';
  }

  static String _hostFromWs(String ws) {
    try {
      final uri = Uri.parse(ws);
      return uri.host.isEmpty ? ws : uri.host;
    } catch (_) {
      return ws;
    }
  }
}
