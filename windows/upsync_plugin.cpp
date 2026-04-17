#include "upsync_plugin.h"

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <shlobj.h>
#include <windows.h>

#include <filesystem>
#include <fstream>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

namespace {

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

}  // namespace

void UpsyncPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "upsync/methods",
      &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<UpsyncPlugin>();
  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

UpsyncPlugin::UpsyncPlugin() {}

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

  result->NotImplemented();
}
