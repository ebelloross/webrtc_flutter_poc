#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <wrl/client.h>

// Windows Runtime para solicitar permisos de micrófono
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.Capture.h>

#include "flutter_window.h"
#include "utils.h"

// Solicita acceso al micrófono via Windows Privacy API.
// Retorna true si el acceso fue concedido.
static bool RequestMicrophoneAccess() {
  try {
    winrt::init_apartment();
    auto mediaCapture =
        winrt::Windows::Media::Capture::MediaCapture();
    auto settings =
        winrt::Windows::Media::Capture::MediaCaptureInitializationSettings();
    settings.StreamingCaptureMode(
        winrt::Windows::Media::Capture::StreamingCaptureMode::Audio);
    mediaCapture.InitializeAsync(settings).get();
    return true;
  } catch (...) {
    // Si el usuario denegó o el dispositivo no tiene micrófono
    return false;
  }
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // Solicita permiso de micrófono a Windows antes de iniciar Flutter.
  // Esto activa el diálogo de permisos en Windows 10/11 si aún no fue aceptado.
  RequestMicrophoneAccess();

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"poc_webrtc_zonitel", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
