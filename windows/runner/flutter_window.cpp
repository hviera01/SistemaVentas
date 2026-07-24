#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    // Arranca siempre maximizada. Tiene que ser acá (no alcanza con
    // llamarlo después de Create() en main.cpp): este callback es lo que
    // de verdad muestra la ventana por primera vez, recién cuando Flutter
    // ya renderizó el primer frame -antes, este->Show() normal pisaba
    // cualquier maximizado que se hubiera pedido antes.
    ::ShowWindow(this->GetHandle(), SW_SHOWMAXIMIZED);
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // F10 (y Alt solo) son teclas de sistema en Win32: aunque esta ventana no
  // tiene menú nativo, Windows las procesa igual como un pedido de "activar
  // el menú" -internamente, DefWindowProc traduce el WM_SYSKEYUP de F10 en
  // un WM_SYSCOMMAND con wParam SC_KEYMENU-. Como acá no hay ningún menú
  // real, Windows queda esperando una tecla de mnemónico, y la siguiente
  // tecla que se escribe se interpreta como ese intento y se pierde con el
  // beep de error en vez de escribirse. Esto pasa en el procesamiento
  // nativo de Windows sin importar qué haga Flutter/Dart con la tecla, así
  // que no alcanza con manejar F10 del lado de Dart (ver
  // _manejarAtajoTeclado en registrar_venta_screen.dart).
  //
  // Cortando acá el WM_SYSCOMMAND/SC_KEYMENU (sin llamar a DefWindowProc)
  // se evita que se active ese modo, sin tocar el resto del manejo de
  // teclado: F10 le sigue llegando a Flutter/Dart exactamente igual que
  // siempre, por el camino normal.
  if (message == WM_SYSCOMMAND && (wparam & 0xFFF0) == SC_KEYMENU) {
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
