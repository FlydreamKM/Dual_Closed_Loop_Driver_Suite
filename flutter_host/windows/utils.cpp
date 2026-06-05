#include "utils.h"

#include <windows.h>
#include <iostream>

std::vector<std::string> GetCommandLineArguments() {
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::vector<std::string>();
  }

  std::vector<std::string> arguments;
  for (int i = 0; i < argc; ++i) {
    arguments.push_back(std::string());
  }

  ::LocalFree(argv);
  return arguments;
}
