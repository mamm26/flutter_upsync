#include "upsync_plugin.h"

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <appmodel.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <windows.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Services.Store.h>
#include <winrt/base.h>

#include <filesystem>
#include <fstream>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

namespace {

using PluginResult =
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>;
using winrt::Windows::Services::Store::StoreContext;
using winrt::Windows::Services::Store::StorePackageUpdateResult;
using winrt::Windows::Services::Store::StorePackageUpdateState;

std::wstring Utf8ToWide(const std::string& input) {
  if (input.empty()) {
    return std::wstring();
  }

  const int size_needed = MultiByteToWideChar(
      CP_UTF8, 0, input.c_str(), static_cast<int>(input.size()), nullptr, 0);
  if (size_needed <= 0) {
    return std::wstring();
  }

  std::wstring output(size_needed, 0);
  MultiByteToWideChar(CP_UTF8, 0, input.c_str(),
                      static_cast<int>(input.size()), output.data(),
                      size_needed);
  return output;
}

std::string WideToUtf8(const std::wstring& input) {
  if (input.empty()) {
    return std::string();
  }

  const int size_needed = WideCharToMultiByte(
      CP_UTF8, 0, input.c_str(), static_cast<int>(input.size()), nullptr, 0,
      nullptr, nullptr);
  if (size_needed <= 0) {
    return std::string();
  }

  std::string output(size_needed, 0);
  WideCharToMultiByte(CP_UTF8, 0, input.c_str(),
                      static_cast<int>(input.size()), output.data(),
                      size_needed, nullptr, nullptr);
  return output;
}

void EnsureWinrtApartment() {
  static thread_local bool initialized = false;
  if (initialized) {
    return;
  }

  try {
    winrt::init_apartment(winrt::apartment_type::single_threaded);
    initialized = true;
  } catch (...) {
    initialized = true;
  }
}

bool HasPackageIdentity() {
  UINT32 length = 0;
  const LONG result = GetCurrentPackageFullName(&length, nullptr);
  return result == ERROR_INSUFFICIENT_BUFFER || result == ERROR_SUCCESS;
}

bool InitializeStoreContextWindow(const StoreContext& context, HWND hwnd) {
  if (hwnd == nullptr) {
    return false;
  }

  try {
    auto initialize_with_window = context.as<IInitializeWithWindow>();
    return SUCCEEDED(initialize_with_window->Initialize(hwnd));
  } catch (...) {
    return false;
  }
}

std::string HResultToHex(winrt::hresult code) {
  std::stringstream stream;
  stream << "0x" << std::hex << std::uppercase
         << static_cast<uint32_t>(code);
  return stream.str();
}

std::string StorePackageUpdateStateToString(
    StorePackageUpdateState state) {
  switch (state) {
    case StorePackageUpdateState::Pending:
      return "pending";
    case StorePackageUpdateState::Downloading:
      return "downloading";
    case StorePackageUpdateState::Deploying:
      return "deploying";
    case StorePackageUpdateState::Completed:
      return "completed";
    case StorePackageUpdateState::Canceled:
      return "canceled";
    case StorePackageUpdateState::OtherError:
      return "otherError";
    case StorePackageUpdateState::ErrorLowBattery:
      return "errorLowBattery";
    case StorePackageUpdateState::ErrorWiFiRecommended:
      return "errorWiFiRecommended";
    case StorePackageUpdateState::ErrorWiFiRequired:
      return "errorWiFiRequired";
  }

  return "unknown";
}

flutter::EncodableMap MicrosoftStoreBaseResult() {
  flutter::EncodableMap result;
  result[flutter::EncodableValue("isPackaged")] =
      flutter::EncodableValue(true);
  result[flutter::EncodableValue("updateAvailable")] =
      flutter::EncodableValue(false);
  result[flutter::EncodableValue("updateCount")] =
      flutter::EncodableValue(0);
  result[flutter::EncodableValue("installRequested")] =
      flutter::EncodableValue(false);
  result[flutter::EncodableValue("installCompleted")] =
      flutter::EncodableValue(false);
  result[flutter::EncodableValue("status")] =
      flutter::EncodableValue("upToDate");
  return result;
}

flutter::EncodableMap MicrosoftStoreNotPackagedResult() {
  auto result = MicrosoftStoreBaseResult();
  result[flutter::EncodableValue("isPackaged")] =
      flutter::EncodableValue(false);
  result[flutter::EncodableValue("status")] =
      flutter::EncodableValue("notPackaged");
  return result;
}

flutter::EncodableMap MicrosoftStoreUpdateAvailableResult(
    uint32_t update_count) {
  auto result = MicrosoftStoreBaseResult();
  result[flutter::EncodableValue("updateAvailable")] =
      flutter::EncodableValue(true);
  result[flutter::EncodableValue("updateCount")] =
      flutter::EncodableValue(static_cast<int32_t>(update_count));
  result[flutter::EncodableValue("status")] =
      flutter::EncodableValue("updateAvailable");
  return result;
}

flutter::EncodableMap MicrosoftStoreInstallResult(
    uint32_t update_count,
    const StorePackageUpdateResult& update_result) {
  const StorePackageUpdateState state = update_result.OverallState();
  auto result = MicrosoftStoreUpdateAvailableResult(update_count);
  result[flutter::EncodableValue("installRequested")] =
      flutter::EncodableValue(true);
  result[flutter::EncodableValue("installCompleted")] =
      flutter::EncodableValue(state == StorePackageUpdateState::Completed);
  result[flutter::EncodableValue("status")] =
      flutter::EncodableValue(StorePackageUpdateStateToString(state));
  return result;
}

std::wstring GetCurrentExecutablePath() {
  std::vector<wchar_t> buffer(MAX_PATH);

  while (true) {
    const DWORD buffer_length = static_cast<DWORD>(buffer.size());
    const DWORD written =
        GetModuleFileNameW(nullptr, buffer.data(), buffer_length);
    if (written == 0) {
      return std::wstring();
    }

    if (written < buffer_length - 1) {
      return std::wstring(buffer.data(), written);
    }

    buffer.resize(buffer.size() * 2);
  }
}

std::wstring ResolveAppStorageName(const std::wstring& preferred_name) {
  if (!preferred_name.empty()) {
    return preferred_name;
  }

  const std::filesystem::path current_executable_path(
      GetCurrentExecutablePath());
  const std::wstring executable_name =
      current_executable_path.stem().wstring();
  if (!executable_name.empty()) {
    return executable_name;
  }

  return L"app";
}

std::wstring GetLocalUpdatesDirectory(const std::wstring& app_name) {
  PWSTR path = nullptr;
  if (FAILED(
          SHGetKnownFolderPath(FOLDERID_LocalAppData, KF_FLAG_CREATE, nullptr,
                               &path)) ||
      path == nullptr) {
    return std::wstring();
  }

  std::filesystem::path result(path);
  CoTaskMemFree(path);

  result /= app_name;
  result /= L"updates";

  std::error_code ec;
  std::filesystem::create_directories(result, ec);
  return result.wstring();
}

std::wstring GetPowerShellScriptPath() {
  std::vector<wchar_t> temp_path(MAX_PATH);
  const DWORD size = GetTempPathW(static_cast<DWORD>(temp_path.size()),
                                  temp_path.data());
  if (size == 0 || size > temp_path.size()) {
    return std::wstring();
  }

  wchar_t temp_file[MAX_PATH];
  if (GetTempFileNameW(temp_path.data(), L"jup", 0, temp_file) == 0) {
    return std::wstring();
  }

  std::filesystem::path script_path(temp_file);
  script_path.replace_extension(L".ps1");

  std::error_code ec;
  std::filesystem::rename(temp_file, script_path, ec);
  if (ec) {
    return std::wstring();
  }

  return script_path.wstring();
}

std::wstring EscapeForPowerShellLiteral(const std::wstring& input) {
  std::wstring output;
  output.reserve(input.size());

  for (const wchar_t ch : input) {
    output.push_back(ch);
    if (ch == L'\'') {
      output.push_back(L'\'');
    }
  }

  return output;
}

bool WritePowerShellScript(const std::wstring& script_path,
                           const std::wstring& current_exe_path,
                           const std::wstring& downloaded_package_path,
                           DWORD current_pid) {
  const std::wstring escaped_script =
      EscapeForPowerShellLiteral(script_path);
  const std::wstring escaped_current =
      EscapeForPowerShellLiteral(current_exe_path);
  const std::wstring escaped_download =
      EscapeForPowerShellLiteral(downloaded_package_path);

  std::wstringstream content;
  content << L"$package = '" << escaped_download << L"'\n";
  content << L"$currentExe = '" << escaped_current << L"'\n";
  content << L"$installDir = Split-Path -Parent $currentExe\n";
  content << L"$extractRoot = $null\n";
  content << L"$preservedRoot = $null\n";
  content << L"$pidToWait = " << current_pid << L"\n";
  content << L"while (Get-Process -Id $pidToWait -ErrorAction SilentlyContinue) { "
             L"Start-Sleep -Milliseconds 500 }\n";
  content << L"try {\n";
  content << L"  $extension = [System.IO.Path]::GetExtension($package).ToLowerInvariant()\n";
  content << L"  if ($extension -eq '.zip') {\n";
  content << L"    $extractRoot = Join-Path ([System.IO.Path]::GetDirectoryName($package)) "
             L"('extract_' + [System.Guid]::NewGuid().ToString('N'))\n";
  content << L"    New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null\n";
  content << L"    Expand-Archive -LiteralPath $package -DestinationPath $extractRoot -Force\n";
  content << L"    $entries = @(Get-ChildItem -LiteralPath $extractRoot)\n";
  content << L"    $sourceDir = $extractRoot\n";
  content << L"    if ($entries.Count -eq 1 -and $entries[0].PSIsContainer) {\n";
  content << L"      $sourceDir = $entries[0].FullName\n";
  content << L"    }\n";
  content << L"    if (Test-Path -LiteralPath $installDir) {\n";
  content << L"      $preservedDirectories = @()\n";
  content << L"      $dotItems = @(Get-ChildItem -LiteralPath $installDir -Force -Recurse | "
             L"Where-Object { $_.Name.StartsWith('.') } | "
             L"Sort-Object { $_.FullName.Length })\n";
  content << L"      foreach ($item in $dotItems) {\n";
  content << L"        $relativePath = $item.FullName.Substring($installDir.Length).TrimStart('\\')\n";
  content << L"        if ([string]::IsNullOrWhiteSpace($relativePath)) { continue }\n";
  content << L"        $sourcePath = Join-Path $sourceDir $relativePath\n";
  content << L"        if (Test-Path -LiteralPath $sourcePath) { continue }\n";
  content << L"        $skipItem = $false\n";
  content << L"        foreach ($preservedDir in $preservedDirectories) {\n";
  content << L"          if ($relativePath.StartsWith($preservedDir + '\\', [System.StringComparison]::OrdinalIgnoreCase)) {\n";
  content << L"            $skipItem = $true\n";
  content << L"            break\n";
  content << L"          }\n";
  content << L"        }\n";
  content << L"        if ($skipItem) { continue }\n";
  content << L"        if ($preservedRoot -eq $null) {\n";
  content << L"          $preservedRoot = Join-Path ([System.IO.Path]::GetDirectoryName($package)) "
             L"('preserve_' + [System.Guid]::NewGuid().ToString('N'))\n";
  content << L"          New-Item -ItemType Directory -Path $preservedRoot -Force | Out-Null\n";
  content << L"        }\n";
  content << L"        $preservedPath = Join-Path $preservedRoot $relativePath\n";
  content << L"        $preservedParent = Split-Path -Parent $preservedPath\n";
  content << L"        if ($preservedParent) {\n";
  content << L"          New-Item -ItemType Directory -Path $preservedParent -Force | Out-Null\n";
  content << L"        }\n";
  content << L"        Copy-Item -LiteralPath $item.FullName -Destination $preservedPath -Recurse -Force\n";
  content << L"        if ($item.PSIsContainer) {\n";
  content << L"          $preservedDirectories += $relativePath\n";
  content << L"        }\n";
  content << L"      }\n";
  content << L"    }\n";
  content << L"    for ($i = 0; $i -lt 5; $i++) {\n";
  content << L"      & robocopy $sourceDir $installDir /MIR /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null\n";
  content << L"      $code = $LASTEXITCODE\n";
  content << L"      if ($code -lt 8) { break }\n";
  content << L"      Start-Sleep -Seconds 1\n";
  content << L"    }\n";
  content << L"    if ($code -ge 8) {\n";
  content << L"      throw \"robocopy failed with exit code $code\"\n";
  content << L"    }\n";
  content << L"    if ($preservedRoot) {\n";
  content << L"      Get-ChildItem -LiteralPath $preservedRoot -Force | ForEach-Object {\n";
  content << L"        Copy-Item -LiteralPath $_.FullName -Destination $installDir -Recurse -Force\n";
  content << L"      }\n";
  content << L"    }\n";
  content << L"  } elseif ($extension -eq '.exe') {\n";
  content << L"    Copy-Item -LiteralPath $package -Destination $currentExe -Force\n";
  content << L"  } else {\n";
  content << L"    throw \"Unsupported update package type: $extension\"\n";
  content << L"  }\n";
  content << L"  Start-Process -FilePath $currentExe\n";
  content << L"} catch {\n";
  content << L"  Start-Process -FilePath $currentExe -ErrorAction SilentlyContinue\n";
  content << L"} finally {\n";
  content << L"  Remove-Item -LiteralPath $package -Force -ErrorAction SilentlyContinue\n";
  content << L"  if ($extractRoot) {\n";
  content << L"    Remove-Item -LiteralPath $extractRoot -Recurse -Force -ErrorAction SilentlyContinue\n";
  content << L"  }\n";
  content << L"  if ($preservedRoot) {\n";
  content << L"    Remove-Item -LiteralPath $preservedRoot -Recurse -Force -ErrorAction SilentlyContinue\n";
  content << L"  }\n";
  content << L"  Start-Sleep -Milliseconds 500\n";
  content << L"  Remove-Item -LiteralPath '" << escaped_script
          << L"' -Force -ErrorAction SilentlyContinue\n";
  content << L"}\n";

  const std::string utf8 = WideToUtf8(content.str());
  std::ofstream file(std::filesystem::path(script_path),
                     std::ios::binary | std::ios::trunc);
  if (!file.is_open()) {
    return false;
  }

  const unsigned char bom[] = {0xEF, 0xBB, 0xBF};
  file.write(reinterpret_cast<const char*>(bom), sizeof(bom));
  file.write(utf8.data(), static_cast<std::streamsize>(utf8.size()));
  file.close();
  return file.good();
}

bool LaunchPowerShellScript(const std::wstring& script_path) {
  std::wstring command = L"powershell.exe -NoProfile -ExecutionPolicy Bypass "
                         L"-WindowStyle Hidden -File \"" +
                         script_path + L"\"";

  STARTUPINFOW startup_info{};
  startup_info.cb = sizeof(startup_info);
  startup_info.dwFlags = STARTF_USESHOWWINDOW;
  startup_info.wShowWindow = SW_HIDE;

  PROCESS_INFORMATION process_info{};
  const BOOL created =
      CreateProcessW(nullptr, command.data(), nullptr, nullptr, FALSE,
                     CREATE_NO_WINDOW, nullptr, nullptr, &startup_info,
                     &process_info);

  if (!created) {
    return false;
  }

  CloseHandle(process_info.hThread);
  CloseHandle(process_info.hProcess);
  return true;
}

bool ApplyUpdateAndRestart(const std::wstring& downloaded_package_path) {
  if (downloaded_package_path.empty() ||
      !std::filesystem::exists(std::filesystem::path(downloaded_package_path))) {
    return false;
  }

  const std::wstring current_exe_path = GetCurrentExecutablePath();
  if (current_exe_path.empty()) {
    return false;
  }

  const std::wstring script_path = GetPowerShellScriptPath();
  if (script_path.empty()) {
    return false;
  }

  if (!WritePowerShellScript(script_path, current_exe_path, downloaded_package_path,
                             GetCurrentProcessId())) {
    return false;
  }

  return LaunchPowerShellScript(script_path);
}

flutter::EncodableMap GetPaths(const std::string& app_name_utf8) {
  const std::wstring app_name =
      ResolveAppStorageName(Utf8ToWide(app_name_utf8));
  const std::wstring current_executable_path = GetCurrentExecutablePath();
  const std::wstring updates_directory = GetLocalUpdatesDirectory(app_name);

  std::filesystem::path executable_path(current_executable_path);

  flutter::EncodableMap result;
  result[flutter::EncodableValue("currentExecutablePath")] =
      flutter::EncodableValue(WideToUtf8(current_executable_path));
  result[flutter::EncodableValue("currentExecutableName")] =
      flutter::EncodableValue(WideToUtf8(executable_path.filename().wstring()));
  result[flutter::EncodableValue("updatesDirectory")] =
      flutter::EncodableValue(WideToUtf8(updates_directory));
  result[flutter::EncodableValue("resolvedAppName")] =
      flutter::EncodableValue(WideToUtf8(app_name));
  return result;
}

winrt::fire_and_forget CheckMicrosoftStoreUpdatesAsync(
    HWND owner_window,
    bool install,
    PluginResult result) {
  EnsureWinrtApartment();
  winrt::apartment_context ui_thread;
  std::string error_code;
  std::string error_message;
  std::string error_details;

  try {
    if (!HasPackageIdentity()) {
      co_await ui_thread;
      result->Success(
          flutter::EncodableValue(MicrosoftStoreNotPackagedResult()));
      co_return;
    }

    StoreContext context = StoreContext::GetDefault();
    InitializeStoreContextWindow(context, owner_window);

    const auto updates =
        co_await context.GetAppAndOptionalStorePackageUpdatesAsync();
    co_await ui_thread;
    const uint32_t update_count = updates.Size();

    if (update_count == 0) {
      result->Success(flutter::EncodableValue(MicrosoftStoreBaseResult()));
      co_return;
    }

    if (!install) {
      result->Success(flutter::EncodableValue(
          MicrosoftStoreUpdateAvailableResult(update_count)));
      co_return;
    }

    if (!InitializeStoreContextWindow(context, owner_window)) {
      result->Error(
          "microsoft_store_window_unavailable",
          "Microsoft Store could not be associated with the app window.");
      co_return;
    }

    auto operation =
        context.RequestDownloadAndInstallStorePackageUpdatesAsync(updates);
    const StorePackageUpdateResult update_result = co_await operation;

    co_await ui_thread;
    result->Success(flutter::EncodableValue(
        MicrosoftStoreInstallResult(update_count, update_result)));
    co_return;
  } catch (const winrt::hresult_error& error) {
    error_code = "microsoft_store_update_failed";
    error_message = WideToUtf8(std::wstring(error.message().c_str()));
    error_details = HResultToHex(error.code());
  } catch (const std::exception& error) {
    error_code = "microsoft_store_update_failed";
    error_message = error.what();
  } catch (...) {
    error_code = "microsoft_store_update_failed";
    error_message = "Microsoft Store update failed.";
  }

  co_await ui_thread;
  if (error_details.empty()) {
    result->Error(error_code, error_message);
  } else {
    result->Error(error_code, error_message,
                  flutter::EncodableValue(error_details));
  }
}

}  // namespace

void UpsyncPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "upsync/methods",
      &flutter::StandardMethodCodec::GetInstance());

  HWND owner_window = nullptr;
  if (registrar->GetView() != nullptr) {
    owner_window = registrar->GetView()->GetNativeWindow();
  }

  auto plugin = std::make_unique<UpsyncPlugin>(owner_window);
  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

UpsyncPlugin::UpsyncPlugin(HWND owner_window) : owner_window_(owner_window) {}

UpsyncPlugin::~UpsyncPlugin() {}

void UpsyncPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto& method = method_call.method_name();

  if (method == "getPaths") {
    const auto* arguments =
        std::get_if<flutter::EncodableMap>(method_call.arguments());

    std::string app_name;
    if (arguments != nullptr) {
      const auto name_it = arguments->find(flutter::EncodableValue("appName"));
      if (name_it != arguments->end() &&
          std::holds_alternative<std::string>(name_it->second)) {
        app_name = std::get<std::string>(name_it->second);
      }
    }

    result->Success(flutter::EncodableValue(GetPaths(app_name)));
    return;
  }

  if (method == "applyUpdateAndRestart") {
    const auto* arguments =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (arguments == nullptr) {
      result->Success(flutter::EncodableValue(false));
      return;
    }

    const auto path_it =
        arguments->find(flutter::EncodableValue("downloadedPackagePath"));
    if (path_it == arguments->end() ||
        !std::holds_alternative<std::string>(path_it->second)) {
      result->Success(flutter::EncodableValue(false));
      return;
    }

    const auto downloaded_package_path =
        Utf8ToWide(std::get<std::string>(path_it->second));
    result->Success(
        flutter::EncodableValue(ApplyUpdateAndRestart(downloaded_package_path)));
    return;
  }

  if (method == "checkMicrosoftStoreUpdates") {
    const auto* arguments =
        std::get_if<flutter::EncodableMap>(method_call.arguments());

    bool install = false;
    if (arguments != nullptr) {
      const auto install_it =
          arguments->find(flutter::EncodableValue("install"));
      if (install_it != arguments->end() &&
          std::holds_alternative<bool>(install_it->second)) {
        install = std::get<bool>(install_it->second);
      }
    }

    CheckMicrosoftStoreUpdatesAsync(owner_window_, install, std::move(result));
    return;
  }

  result->NotImplemented();
}
