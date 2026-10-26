#include "flutter_window.h"

// Platform API and channel identities: hardcode HC-076.

#include <optional>
#include <psapi.h>
#include <flutter/standard_method_codec.h>

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
  auto messenger = flutter_controller_->engine()->messenger();
  safety_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "vitalis/device_safety", &flutter::StandardMethodCodec::GetInstance());
  safety_channel_->SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() != "snapshot") { result->NotImplemented(); return; }
    flutter::EncodableMap snapshot;
    MEMORYSTATUSEX memory{};
    memory.dwLength = sizeof(memory);
    if (GlobalMemoryStatusEx(&memory)) {
      snapshot[flutter::EncodableValue("availableMemoryBytes")] = flutter::EncodableValue(static_cast<int64_t>(memory.ullAvailPhys));
      snapshot[flutter::EncodableValue("totalMemoryBytes")] = flutter::EncodableValue(static_cast<int64_t>(memory.ullTotalPhys));
    }
    PROCESS_MEMORY_COUNTERS process{};
    if (GetProcessMemoryInfo(GetCurrentProcess(), &process, sizeof(process))) {
      snapshot[flutter::EncodableValue("processRssBytes")] = flutter::EncodableValue(static_cast<int64_t>(process.WorkingSetSize));
    }
    HANDLE notification = CreateMemoryResourceNotification(LowMemoryResourceNotification);
    if (notification != nullptr) {
      BOOL low_memory = FALSE;
      if (QueryMemoryResourceNotification(notification, &low_memory)) {
        snapshot[flutter::EncodableValue("lowMemory")] = flutter::EncodableValue(low_memory != FALSE);
      }
      CloseHandle(notification);
    }
    SYSTEM_POWER_STATUS power{};
    if (GetSystemPowerStatus(&power)) {
      snapshot[flutter::EncodableValue("powerSaveMode")] = flutter::EncodableValue(power.SystemStatusFlag != 0);
    }
    snapshot[flutter::EncodableValue("logicalProcessors")] = flutter::EncodableValue(static_cast<int32_t>(GetActiveProcessorCount(ALL_PROCESSOR_GROUPS)));
    snapshot[flutter::EncodableValue("deviceFingerprint")] = flutter::EncodableValue("windows-x64-cpu");
    snapshot[flutter::EncodableValue("supportedAbis")] = flutter::EncodableValue(flutter::EncodableList{flutter::EncodableValue("x64")});
    snapshot[flutter::EncodableValue("packagedBackends")] = flutter::EncodableValue(flutter::EncodableList{flutter::EncodableValue("cpu")});
    // Windows provides no uniform thermal/topology class API; omit unknown sensors.
    result->Success(flutter::EncodableValue(snapshot));
  });
  storage_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "vitalis/model_storage", &flutter::StandardMethodCodec::GetInstance());
  storage_channel_->SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() != "allocatableBytes") { result->NotImplemented(); return; }
    const auto* path = call.arguments() == nullptr ? nullptr : std::get_if<std::string>(call.arguments());
    if (path == nullptr || path->empty()) { result->Error("invalidStoragePath", "Storage location is required"); return; }
    const int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path->data(), static_cast<int>(path->size()), nullptr, 0);
    if (count <= 0) { result->Error("invalidStoragePath", "Storage location is invalid"); return; }
    std::wstring wide_path(static_cast<size_t>(count), L'\0');
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path->data(), static_cast<int>(path->size()), wide_path.data(), count);
    ULARGE_INTEGER available{};
    if (!GetDiskFreeSpaceExW(wide_path.c_str(), &available, nullptr, nullptr)) {
      result->Error("storageUnavailable", "Available storage could not be measured"); return;
    }
    result->Success(flutter::EncodableValue(static_cast<int64_t>(available.QuadPart)));
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  storage_channel_ = nullptr;
  safety_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
