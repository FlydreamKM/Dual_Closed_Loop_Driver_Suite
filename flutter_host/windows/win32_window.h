#ifndef WIN32_WINDOW_H_
#define WIN32_WINDOW_H_

#include <Windows.h>
#include <string>

class Win32Window {
 public:
  struct Point {
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  struct Size {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  Win32Window();
  virtual ~Win32Window();

  bool Show(const std::wstring& title, const Point& origin, const Size& size);
  void Destroy();
  void SetQuitOnClose(bool quit_on_close);

  virtual bool OnCreate() { return true; }
  virtual void OnDestroy() {}

 protected:
  HWND window_handle_ = nullptr;
  HWND child_content_ = nullptr;

 private:
  static LRESULT CALLBACK WndProc(HWND const window, UINT const message,
                                    WPARAM const wparam,
                                    LPARAM const lparam) noexcept;
  LRESULT MessageHandler(HWND hwnd, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept;

  static Win32Window* GetThisFromHandle(HWND const window) noexcept;

  bool quit_on_close_ = false;
  std::wstring window_class_name_;
};

#endif  // WIN32_WINDOW_H_
