#include "flutter_window.h"

#include <commdlg.h>
#include <shellapi.h>

#include <array>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <cwctype>
#include <filesystem>
#include <fstream>
#include <optional>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"
#include <flutter/standard_method_codec.h>

namespace {

std::wstring JoinPath(const std::wstring& directory,
                      const std::wstring& file_name) {
  if (directory.empty()) {
    return file_name;
  }
  return std::filesystem::path(directory).append(file_name).wstring();
}

std::string ToUtf8(const std::wstring& value) {
  return Utf8FromUtf16(value.c_str());
}

std::wstring Basename(const std::wstring& value) {
  return std::filesystem::path(value).filename().wstring();
}

bool IsImagePath(const std::wstring& value) {
  auto extension = std::filesystem::path(value).extension().wstring();
  for (auto& character : extension) {
    character = static_cast<wchar_t>(towlower(character));
  }
  return extension == L".png" || extension == L".jpg" || extension == L".jpeg" ||
         extension == L".gif" || extension == L".bmp" || extension == L".webp" ||
         extension == L".tif" || extension == L".tiff";
}

flutter::EncodableValue MakeAttachmentValue(const std::wstring& path) {
  flutter::EncodableMap value;
  value[flutter::EncodableValue("type")] =
      flutter::EncodableValue(IsImagePath(path) ? "localImage" : "mention");
  value[flutter::EncodableValue("path")] = flutter::EncodableValue(ToUtf8(path));
  value[flutter::EncodableValue("name")] =
      flutter::EncodableValue(ToUtf8(Basename(path)));
  return flutter::EncodableValue(value);
}

std::vector<flutter::EncodableValue> PickAttachmentValues(HWND owner) {
  std::vector<wchar_t> buffer(65536, L'\0');
  OPENFILENAMEW dialog = {};
  dialog.lStructSize = sizeof(dialog);
  dialog.hwndOwner = owner;
  dialog.lpstrFilter =
      L"All files\0*.*\0"
      L"Images\0*.png;*.jpg;*.jpeg;*.gif;*.bmp;*.webp;*.tif;*.tiff\0";
  dialog.lpstrFile = buffer.data();
  dialog.nMaxFile = static_cast<DWORD>(buffer.size());
  dialog.Flags = OFN_EXPLORER | OFN_ALLOWMULTISELECT | OFN_FILEMUSTEXIST |
                 OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR;

  if (!GetOpenFileNameW(&dialog)) {
    return {};
  }

  std::vector<flutter::EncodableValue> values;
  std::wstring first(buffer.data());
  if (first.empty()) {
    return values;
  }

  const wchar_t* cursor = buffer.data() + first.size() + 1;
  if (*cursor == L'\0') {
    values.push_back(MakeAttachmentValue(first));
    return values;
  }

  const std::wstring directory = first;
  while (*cursor != L'\0') {
    const std::wstring file_name(cursor);
    values.push_back(MakeAttachmentValue(JoinPath(directory, file_name)));
    cursor += file_name.size() + 1;
  }
  return values;
}

std::filesystem::path TempAttachmentDirectory() {
  std::array<wchar_t, MAX_PATH + 1> buffer{};
  const DWORD length = GetTempPathW(static_cast<DWORD>(buffer.size()),
                                    buffer.data());
  std::filesystem::path temp_path =
      length == 0 ? std::filesystem::temp_directory_path()
                  : std::filesystem::path(buffer.data());
  const auto directory = temp_path / "codex-control";
  std::filesystem::create_directories(directory);
  return directory;
}

std::filesystem::path NextClipboardImagePath() {
  const auto ticks =
      std::chrono::duration_cast<std::chrono::microseconds>(
          std::chrono::system_clock::now().time_since_epoch())
          .count();
  return TempAttachmentDirectory() /
         ("clipboard-image-" + std::to_string(ticks) + ".bmp");
}

bool SaveBitmapToFile(HBITMAP bitmap, const std::filesystem::path& file_path) {
  BITMAP bitmap_info = {};
  if (GetObject(bitmap, sizeof(bitmap_info), &bitmap_info) == 0) {
    return false;
  }

  BITMAPINFOHEADER header = {};
  header.biSize = sizeof(BITMAPINFOHEADER);
  header.biWidth = bitmap_info.bmWidth;
  header.biHeight = bitmap_info.bmHeight;
  header.biPlanes = 1;
  header.biBitCount = 32;
  header.biCompression = BI_RGB;

  const auto height = static_cast<unsigned int>(std::abs(bitmap_info.bmHeight));
  const DWORD row_bytes =
      ((bitmap_info.bmWidth * header.biBitCount + 31) / 32) * 4;
  const DWORD pixel_bytes = row_bytes * height;
  std::vector<std::uint8_t> pixels(pixel_bytes);

  HDC device_context = GetDC(nullptr);
  const auto did_copy = GetDIBits(device_context, bitmap, 0, height,
                                  pixels.data(),
                                  reinterpret_cast<BITMAPINFO*>(&header),
                                  DIB_RGB_COLORS);
  ReleaseDC(nullptr, device_context);
  if (did_copy == 0) {
    return false;
  }

  BITMAPFILEHEADER file_header = {};
  file_header.bfType = 0x4D42;
  file_header.bfOffBits =
      sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER);
  file_header.bfSize = file_header.bfOffBits + pixel_bytes;

  std::ofstream stream(file_path, std::ios::binary);
  if (!stream.is_open()) {
    return false;
  }

  stream.write(reinterpret_cast<const char*>(&file_header), sizeof(file_header));
  stream.write(reinterpret_cast<const char*>(&header), sizeof(header));
  stream.write(reinterpret_cast<const char*>(pixels.data()), pixels.size());
  return stream.good();
}

std::vector<flutter::EncodableValue> ReadClipboardAttachmentValues() {
  std::vector<flutter::EncodableValue> values;
  if (!OpenClipboard(nullptr)) {
    return values;
  }

  if (IsClipboardFormatAvailable(CF_HDROP)) {
    auto* drop_files =
        static_cast<HDROP>(GetClipboardData(CF_HDROP));
    if (drop_files != nullptr) {
      const UINT count = DragQueryFileW(drop_files, 0xFFFFFFFF, nullptr, 0);
      for (UINT index = 0; index < count; index += 1) {
        const UINT length = DragQueryFileW(drop_files, index, nullptr, 0);
        std::wstring path(length + 1, L'\0');
        DragQueryFileW(drop_files, index, path.data(), length + 1);
        path.resize(length);
        if (!path.empty()) {
          values.push_back(MakeAttachmentValue(path));
        }
      }
    }
    CloseClipboard();
    return values;
  }

  if (IsClipboardFormatAvailable(CF_BITMAP)) {
    auto* bitmap = static_cast<HBITMAP>(GetClipboardData(CF_BITMAP));
    if (bitmap != nullptr) {
      const auto path = NextClipboardImagePath();
      if (SaveBitmapToFile(bitmap, path)) {
        values.push_back(MakeAttachmentValue(path.wstring()));
      }
    }
  }

  CloseClipboard();
  return values;
}

}  // namespace

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
  attachments_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "codex_control/attachments",
          &flutter::StandardMethodCodec::GetInstance());
  attachments_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "pickAttachments") {
          result->Success(flutter::EncodableValue(
              PickAttachmentValues(this->GetHandle())));
          return;
        }
        if (call.method_name() == "readClipboardAttachments") {
          result->Success(
              flutter::EncodableValue(ReadClipboardAttachmentValues()));
          return;
        }
        result->NotImplemented();
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
  attachments_channel_.reset();
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
