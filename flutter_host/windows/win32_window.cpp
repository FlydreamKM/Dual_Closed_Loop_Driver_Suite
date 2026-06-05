#include "win32_window.h"
#include <dwmapi.h>
#include <flutter_windows.h>

Win32Window::Win32Window() {}

Win32Window::~Win32Window() { Destroy(); }

bool Win32Window::Show(const std::wstring& title, const Point& origin,
                       const Size& size) {
  Destroy();

  WNDCLASS window_class = WNDCLASS{};
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.lpszClassName = title.c_str();
  window_class.style = CS_HREDRAW | CS_VREDRAW;
  window_class.cbWndExtra = 0;
  window_class.cbClsExtra = 0;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.hIcon =
      LoadIcon(window_class.hInstance, IDI_APPLICATION);
  window_class.hbrBackground = 0;
  window_class.lpszMenuName = nullptr;
  window_class.lpfnWndProc = WndProc;
  RegisterClass(&window_class);

  const auto dwExStyle = WS_EX_LEFT | WS_EX_LTRREADING | WS_EX_RIGHTSCROLLBAR;
  const auto dwStyle = WS_OVERLAPPEDWINDOW | WS_VISIBLE;

  HWND window = CreateWindowEx(
      dwExStyle, title.c_str(), title.c_str(), dwStyle, origin.x, origin.y,
      size.width, size.height, nullptr, nullptr, window_class.hInstance, this);

  return window != nullptr;
}

LRESULT CALLBACK Win32Window::WndProc(HWND const window, UINT const message,
                                       WPARAM const wparam,
                                       LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto cs = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(cs->lpCreateParams));

    auto that = static_cast<Win32Window*>(cs->lpCreateParams);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT Win32Window::MessageHandler(HWND hwnd, UINT const message,
                                     WPARAM const wparam,
                                     LPARAM const lparam) noexcept {
  switch (message) {
    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;
      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);
      return 0;
    }
    case WM_SIZE:
      RECT rect;
      GetClientRect(hwnd, &rect);
      auto width = rect.right - rect.left;
      auto height = rect.bottom - rect.top;
      if (child_content_ != nullptr) {
        SetWindowPos(child_content_, nullptr, rect.left, rect.top, width,
                     height, SWP_FRAMECHANGED);
      }
      return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }

  UnregisterClass(window_class_name_.c_str(), nullptr);
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame;
  GetClientRect(window_handle_, &frame);
  auto width = frame.right - frame.left;
  auto height = frame.bottom - frame.top;
  SetWindowPos(content, nullptr, frame.left, frame.top, width, height,
               SWP_FRAMECHANGED);
}
