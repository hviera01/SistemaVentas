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
  // Ver el comentario en MessageHandler: F10 nunca llega a Flutter por el
  // camino normal de teclado, así que este canal es la única forma de
  // avisarle a Dart cuando se presiona.
  atajos_channel_ = std::make_unique<flutter::MethodChannel<>>(
      flutter_controller_->engine()->messenger(), "atajos_teclado",
      &flutter::StandardMethodCodec::GetInstance());
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
  // F10 sin ningún modificador es, a nivel de Win32, una "tecla de
  // sistema" igual que Alt solo (WM_SYSKEYDOWN/WM_SYSKEYUP). Un primer
  // intento cortaba este mensaje DESPUÉS de dárselo a
  // HandleTopLevelWindowProc, pero no alcanzó: el motor de Flutter, al no
  // consumirla del todo en el lado nativo, la deja pasar igual hacia el
  // procesamiento por default de Windows -eso pasa adentro del motor
  // (flutter_windows.dll), no acá, así que no hay forma de interceptarlo
  // después de haberla dejado entrar-. Una vez que Windows procesa ese
  // mensaje entra en "modo menú", y como esta app no tiene menú nativo, la
  // siguiente tecla que se escribe se pierde con el beep de error en vez
  // de escribirse.
  //
  // La única forma confiable de evitarlo es no dejar que el mensaje llegue
  // a Flutter en absoluto: se traga entero acá (keyDown y keyUp, antes de
  // llamar a HandleTopLevelWindowProc) y, en el keyDown, se le avisa a
  // Dart por un canal aparte (atajos_channel_, ver AtajoNativo en
  // atajo_nativo.dart) en vez de por el camino normal de teclado. F12 no
  // tiene este problema -no es una tecla de sistema- y sigue andando igual
  // que siempre, sin pasar por acá.
  if (message == WM_SYSKEYDOWN && wparam == VK_F10) {
    if (atajos_channel_) {
      atajos_channel_->InvokeMethod("f10", nullptr);
    }
    return 0;
  }
  if (message == WM_SYSKEYUP && wparam == VK_F10) {
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
