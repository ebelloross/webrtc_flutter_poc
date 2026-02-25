# WebRTC Flutter POC (Audio Only)

POC de llamada RTC (solo audio) en Flutter usando `flutter_webrtc` y señalización por WebSocket.

## Requisitos
- Flutter 3.19.6
- Node.js 18+ (para el servidor de señalización)

## Estructura
- `lib/` contiene el cliente Flutter
- `signaling-server/` contiene el servidor WebSocket

## Inicializar plataforma (solo una vez)
Este repo contiene el código del POC. Para generar las carpetas de plataformas (android/ios/windows/macos), ejecuta:

```bash
flutter create .
flutter config --enable-windows-desktop --enable-macos-desktop
```

## Ejecutar el servidor de señalización
```bash
cd signaling-server
npm install
npm start
```

El servidor escucha en `ws://0.0.0.0:8080`.

## Ejecutar Flutter
En dos dispositivos o simuladores:

```bash
flutter pub get
flutter run
```

En ambos:
- WebSocket URL: `ws://TU_IP_LOCAL:8080`
- Room ID: el mismo en los dos dispositivos

Luego:
1. Presiona **Conectar** en ambos
2. Presiona **Llamar** en uno

## STUN
Configurado por defecto:
- `stun:stun.l.google.com:19302`

## Permisos
Asegúrate de agregar permisos para micrófono:

### Android
`android/app/src/main/AndroidManifest.xml`
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.INTERNET"/>
```

### iOS / macOS
`ios/Runner/Info.plist` y `macos/Runner/Info.plist`
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Se necesita acceso al micrófono para llamadas de audio</string>
```

## Notas
- Si los dispositivos están en redes distintas, usa un túnel (ej. ngrok) o un servidor público.
- Para NAT estrictos, necesitarás un TURN server.