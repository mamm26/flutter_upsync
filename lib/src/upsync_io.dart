import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'upsync_config.dart';
import 'upsync_manifest.dart';
import 'upsync_state.dart';

/// Implementación de `Upsync` para entornos con `dart:io`.
class Upsync {
  Upsync._();

  /// Instancia singleton del actualizador.
  static final Upsync instance = Upsync._();
  static const MethodChannel _channel =
      MethodChannel('upsync/methods');

  final StreamController<UpsyncState> _states =
      StreamController<UpsyncState>.broadcast();
  final http.Client _client = http.Client();

  UpsyncConfig? _config;
  UpsyncState _state = const UpsyncState();
  Timer? _timer;
  _UpsyncPlatformPaths? _paths;
  Future<UpsyncState>? _activeCheck;
  Future<void>? _activeDownload;

  /// Flujo de cambios de estado del actualizador.
  Stream<UpsyncState> get states => _states.stream;

  /// Último estado conocido del actualizador.
  UpsyncState get state => _state;

  bool get _isSupportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// Inicializa el actualizador, restaura descargas pendientes y agenda revisiones.
  Future<void> start(UpsyncConfig config) async {
    _config = config;

    if (!_isSupportedPlatform) {
      _emit(_state.copyWith(
        status: UpsyncStatus.disabled,
        message: 'Actualizador Windows no disponible en esta plataforma.',
        clearError: true,
      ));
      return;
    }

    if (config.manifestUrl.trim().isEmpty) {
      _emit(_state.copyWith(
        status: UpsyncStatus.disabled,
        message: 'No se configuro la URL del manifiesto de Windows.',
        clearError: true,
      ));
      return;
    }

    _paths = await _resolvePaths(config);
    await _restorePendingUpdateIfAny(config, _paths!);

    if (!_state.isReadyToInstall) {
      await checkNow();
    }

    _timer?.cancel();
    _timer = Timer.periodic(config.checkInterval, (_) {
      unawaited(checkNow());
    });
  }

  /// Detiene las revisiones periódicas automáticas.
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  /// Ejecuta una comprobación inmediata del manifiesto remoto.
  Future<UpsyncState> checkNow() async {
    if (!_isSupportedPlatform) {
      return _state.copyWith(
        status: UpsyncStatus.disabled,
        message: 'Actualizador Windows no disponible en esta plataforma.',
      );
    }

    if (_activeCheck != null) {
      return _activeCheck!;
    }

    final future = _checkNowInternal();
    _activeCheck = future.whenComplete(() {
      _activeCheck = null;
    });
    return _activeCheck!;
  }

  /// Intenta aplicar el paquete descargado y reiniciar la aplicación.
  Future<bool> applyDownloadedUpdateAndRestart() async {
    if (!_isSupportedPlatform || !_state.isReadyToInstall) {
      return false;
    }

    final downloadedFilePath = _state.downloadedFilePath;
    if (downloadedFilePath == null || downloadedFilePath.isEmpty) {
      return false;
    }

    _emit(_state.copyWith(
      status: UpsyncStatus.applying,
      message: 'Aplicando actualización descargada...',
      clearError: true,
    ));

    try {
      final ok = await _channel.invokeMethod<bool>(
            'applyUpdateAndRestart',
            <String, Object?>{
              'downloadedPackagePath': downloadedFilePath,
            },
          ) ??
          false;

      if (!ok) {
        _emit(_state.copyWith(
          status: UpsyncStatus.error,
          error: 'No se pudo iniciar la aplicación de la actualización.',
          clearMessage: true,
        ));
        return false;
      }

      await Future<void>.delayed(const Duration(milliseconds: 150));
      exit(0);
    } catch (e) {
      _emit(_state.copyWith(
        status: UpsyncStatus.error,
        error: e.toString(),
        clearMessage: true,
      ));
      return false;
    }
  }

  /// Elimina los metadatos y el archivo de una actualización pendiente.
  Future<void> clearPendingUpdate() async {
    if (!_isSupportedPlatform) {
      return;
    }

    final config = _config;
    if (config == null) {
      return;
    }

    final paths = _paths ?? await _resolvePaths(config);
    await _clearPendingMetadata(paths, deleteDownloadedFile: true);
    _emit(_state.copyWith(
      status: UpsyncStatus.idle,
      clearManifest: true,
      clearDownloadedFilePath: true,
      clearProgress: true,
      clearMessage: true,
      clearError: true,
    ));
  }

  Future<UpsyncState> _checkNowInternal() async {
    final config = _config;
    if (config == null) {
      throw StateError('Debes llamar start() antes de checkNow().');
    }

    final paths = _paths ??= await _resolvePaths(config);

    if (!_state.isReadyToInstall &&
        _state.status != UpsyncStatus.downloading) {
      _emit(_state.copyWith(
        status: UpsyncStatus.checking,
        lastCheckedAt: DateTime.now(),
        clearError: true,
        clearMessage: true,
      ));
    }

    try {
      final manifest = await _fetchManifest(config);
      final isNewer = _isManifestNewer(config, manifest);

      if (!isNewer) {
        if (_state.isReadyToInstall) {
          return _state;
        }

        await _clearPendingMetadata(paths, deleteDownloadedFile: false);
        _emit(_state.copyWith(
          status: UpsyncStatus.upToDate,
          manifest: manifest,
          lastCheckedAt: DateTime.now(),
          clearDownloadedFilePath: true,
          clearProgress: true,
          clearError: true,
          message: 'La aplicación ya está en la versión más reciente.',
        ));
        return _state;
      }

      final existingDownload = await _findExistingDownload(paths, manifest);
      if (existingDownload != null) {
        await _writePendingMetadata(paths, manifest, existingDownload);
        _emit(_state.copyWith(
          status: UpsyncStatus.downloaded,
          manifest: manifest,
          downloadedFilePath: existingDownload,
          progress: 1.0,
          lastCheckedAt: DateTime.now(),
          clearError: true,
          message: 'Hay una actualización lista para instalar.',
        ));
        return _state;
      }

      if (!config.autoDownload) {
        _emit(_state.copyWith(
          status: UpsyncStatus.updateAvailable,
          manifest: manifest,
          lastCheckedAt: DateTime.now(),
          clearDownloadedFilePath: true,
          clearProgress: true,
          clearError: true,
          message: 'Hay una actualización disponible.',
        ));
        return _state;
      }

      await _downloadManifest(paths, config, manifest);
      return _state;
    } catch (e) {
      _emit(_state.copyWith(
        status: UpsyncStatus.error,
        error: e.toString(),
        lastCheckedAt: DateTime.now(),
        clearMessage: true,
      ));
      return _state;
    }
  }

  Future<UpsyncManifest> _fetchManifest(
      UpsyncConfig config) async {
    final manifestUri = Uri.parse(config.manifestUrl.trim());
    if (manifestUri.scheme == 'data') {
      final uriData = manifestUri.data;
      if (uriData == null) {
        throw const FormatException(
            'El manifiesto inline de actualización no es válido.');
      }

      final decoded = jsonDecode(uriData.contentAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException(
            'El manifiesto inline de actualización debe ser un JSON objeto.');
      }

      final manifest = UpsyncManifest.fromJson(decoded);
      return UpsyncManifest(
        version: manifest.version,
        buildNumber: manifest.buildNumber,
        downloadUrl: manifest.downloadUrl,
        packageType: manifest.packageType,
        sha256: manifest.sha256,
        notes: manifest.notes,
        fileSizeBytes: manifest.fileSizeBytes,
      );
    }

    final response = await _client
        .get(
          manifestUri,
          headers: config.requestHeaders,
        )
        .timeout(config.requestTimeout);

    if (response.statusCode != 200) {
      throw HttpException(
        'No se pudo leer el manifiesto de actualización (${response.statusCode}).',
        uri: manifestUri,
      );
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
          'El manifiesto de actualización debe ser un JSON objeto.');
    }

    final manifest = UpsyncManifest.fromJson(decoded);
    final resolvedUrl = manifestUri.resolve(manifest.downloadUrl).toString();
    return UpsyncManifest(
      version: manifest.version,
      buildNumber: manifest.buildNumber,
      downloadUrl: resolvedUrl,
      packageType: manifest.packageType,
      sha256: manifest.sha256,
      notes: manifest.notes,
      fileSizeBytes: manifest.fileSizeBytes,
    );
  }

  Future<void> _downloadManifest(
    _UpsyncPlatformPaths paths,
    UpsyncConfig config,
    UpsyncManifest manifest,
  ) async {
    if (_activeDownload != null) {
      await _activeDownload;
      return;
    }

    final operation = _downloadManifestInternal(paths, config, manifest);
    _activeDownload = operation.whenComplete(() {
      _activeDownload = null;
    });
    await _activeDownload;
  }

  Future<void> _downloadManifestInternal(
    _UpsyncPlatformPaths paths,
    UpsyncConfig config,
    UpsyncManifest manifest,
  ) async {
    final targetFile = _buildDownloadTarget(paths, manifest).path;
    final tempFile = File('$targetFile.download');

    await tempFile.parent.create(recursive: true);

    _emit(_state.copyWith(
      status: UpsyncStatus.downloading,
      manifest: manifest,
      progress: 0.0,
      lastCheckedAt: DateTime.now(),
      clearError: true,
      message: 'Descargando actualización en segundo plano...',
    ));

    final request = http.Request('GET', Uri.parse(manifest.downloadUrl));
    request.headers.addAll(config.requestHeaders);
    final response =
        await _client.send(request).timeout(config.requestTimeout);

    if (response.statusCode != 200) {
      throw HttpException(
        'No se pudo descargar el paquete de actualización (${response.statusCode}).',
        uri: Uri.parse(manifest.downloadUrl),
      );
    }

    final sink = tempFile.openWrite();
    final contentLength = response.contentLength ?? manifest.fileSizeBytes ?? 0;
    var received = 0;

    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;

        if (contentLength > 0) {
          final progress =
              (received / contentLength).clamp(0.0, 1.0).toDouble();
          _emit(_state.copyWith(
            status: UpsyncStatus.downloading,
            manifest: manifest,
            progress: progress,
            clearError: true,
            message: 'Descargando actualización en segundo plano...',
          ));
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
    }

    if (manifest.sha256 != null && manifest.sha256!.trim().isNotEmpty) {
      final digest = await sha256.bind(tempFile.openRead()).first;
      final expected = manifest.sha256!.trim().toLowerCase();
      if (digest.toString().toLowerCase() != expected) {
        await _deleteSilently(tempFile);
        throw const FormatException(
            'El paquete descargado no coincide con el SHA-256 esperado.');
      }
    }

    final target = File(targetFile);
    if (await target.exists()) {
      await target.delete();
    }

    await tempFile.rename(targetFile);
    await _writePendingMetadata(paths, manifest, targetFile);

    _emit(_state.copyWith(
      status: UpsyncStatus.downloaded,
      manifest: manifest,
      downloadedFilePath: targetFile,
      progress: 1.0,
      clearError: true,
      message: 'Actualización descargada y lista para instalar.',
    ));
  }

  Future<void> _restorePendingUpdateIfAny(
    UpsyncConfig config,
    _UpsyncPlatformPaths paths,
  ) async {
    final metadataFile = File(_pendingMetadataPath(paths));
    if (!await metadataFile.exists()) {
      return;
    }

    try {
      final decoded = jsonDecode(await metadataFile.readAsString());
      if (decoded is! Map<String, dynamic>) {
        await _clearPendingMetadata(paths, deleteDownloadedFile: false);
        return;
      }

      final manifestJson = decoded['manifest'];
      final filePath = decoded['filePath']?.toString() ?? '';
      if (manifestJson is! Map<String, dynamic> || filePath.isEmpty) {
        await _clearPendingMetadata(paths, deleteDownloadedFile: false);
        return;
      }

      final manifest = UpsyncManifest.fromJson(manifestJson);
      final file = File(filePath);
      if (!await file.exists()) {
        await _clearPendingMetadata(paths, deleteDownloadedFile: false);
        return;
      }

      if (!_isManifestNewer(config, manifest)) {
        await _clearPendingMetadata(paths, deleteDownloadedFile: true);
        return;
      }

      _emit(_state.copyWith(
        status: UpsyncStatus.downloaded,
        manifest: manifest,
        downloadedFilePath: filePath,
        progress: 1.0,
        clearError: true,
        message: 'Hay una actualización lista para instalar.',
      ));
    } catch (_) {
      await _clearPendingMetadata(paths, deleteDownloadedFile: false);
    }
  }

  Future<String?> _findExistingDownload(
    _UpsyncPlatformPaths paths,
    UpsyncManifest manifest,
  ) async {
    final target = _buildDownloadTarget(paths, manifest);
    if (await target.exists()) {
      return target.path;
    }

    return null;
  }

  File _buildDownloadTarget(
    _UpsyncPlatformPaths paths,
    UpsyncManifest manifest,
  ) {
    final uri = Uri.parse(manifest.downloadUrl);
    final urlName = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final packageType = manifest.resolvedPackageType;
    final fallbackName = packageType == 'zip'
        ? '${paths.appName}_windows_update.zip'
        : (paths.currentExecutableName.isNotEmpty
            ? paths.currentExecutableName
            : '${paths.appName}.exe');
    final executableName = urlName.isNotEmpty ? urlName : fallbackName;
    final versionFolder = _normalizeFolderName(manifest.identifier);
    final fullPath =
        p.join(paths.updatesDirectory, versionFolder, executableName);
    return File(fullPath);
  }

  Future<_UpsyncPlatformPaths> _resolvePaths(
      UpsyncConfig config) async {
    final values = await _channel.invokeMapMethod<String, dynamic>(
      'getPaths',
      <String, Object?>{'appName': config.appName.trim()},
    );
    final currentExecutablePath =
        values?['currentExecutablePath']?.toString() ?? '';
    var updatesDirectory = values?['updatesDirectory']?.toString() ?? '';
    final currentExecutableName =
        values?['currentExecutableName']?.toString() ?? '';
    final resolvedAppName = _resolveAppName(
      values?['resolvedAppName']?.toString() ?? config.appName,
      currentExecutableName,
    );

    if (updatesDirectory.isEmpty) {
      final supportDirectory = await getApplicationSupportDirectory();
      updatesDirectory = p.join(supportDirectory.path, 'updates');
    }

    await Directory(updatesDirectory).create(recursive: true);

    return _UpsyncPlatformPaths(
      currentExecutablePath: currentExecutablePath,
      currentExecutableName: currentExecutableName,
      updatesDirectory: updatesDirectory,
      appName: resolvedAppName,
    );
  }

  String _resolveAppName(String configuredAppName, String executableName) {
    final normalizedName = configuredAppName.trim();
    if (normalizedName.isNotEmpty) {
      return normalizedName;
    }

    final executableBaseName = p.basenameWithoutExtension(
      executableName.trim(),
    );
    if (executableBaseName.isNotEmpty) {
      return executableBaseName;
    }

    return 'app';
  }

  bool _isManifestNewer(
    UpsyncConfig config,
    UpsyncManifest manifest,
  ) {
    if (manifest.buildNumber > 0 && config.currentBuildNumber > 0) {
      return manifest.buildNumber > config.currentBuildNumber;
    }

    return _compareSemanticVersions(manifest.version, config.currentVersion) > 0;
  }

  int _compareSemanticVersions(String left, String right) {
    final leftParts = _versionParts(left);
    final rightParts = _versionParts(right);
    final maxLength =
        leftParts.length > rightParts.length ? leftParts.length : rightParts.length;

    for (var i = 0; i < maxLength; i++) {
      final a = i < leftParts.length ? leftParts[i] : 0;
      final b = i < rightParts.length ? rightParts[i] : 0;
      if (a != b) {
        return a.compareTo(b);
      }
    }

    return 0;
  }

  List<int> _versionParts(String value) {
    return value
        .split(RegExp(r'[^0-9]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
  }

  Future<void> _writePendingMetadata(
    _UpsyncPlatformPaths paths,
    UpsyncManifest manifest,
    String filePath,
  ) async {
    final file = File(_pendingMetadataPath(paths));
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'filePath': filePath,
        'manifest': manifest.toJson(),
      }),
    );
  }

  Future<void> _clearPendingMetadata(
    _UpsyncPlatformPaths paths, {
    required bool deleteDownloadedFile,
  }) async {
    final file = File(_pendingMetadataPath(paths));
    if (!await file.exists()) {
      return;
    }

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (deleteDownloadedFile && decoded is Map<String, dynamic>) {
        final pendingFilePath = decoded['filePath']?.toString() ?? '';
        if (pendingFilePath.isNotEmpty) {
          final pendingFile = File(pendingFilePath);
          if (await pendingFile.exists()) {
            await pendingFile.delete();
          }
        }
      }
    } catch (_) {}

    await _deleteSilently(file);
  }

  String _pendingMetadataPath(_UpsyncPlatformPaths paths) {
    return p.join(paths.updatesDirectory, 'pending_update.json');
  }

  String _normalizeFolderName(String value) {
    return value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
  }

  Future<void> _deleteSilently(FileSystemEntity entity) async {
    try {
      await entity.delete();
    } catch (_) {}
  }

  void _emit(UpsyncState value) {
    _state = value;
    if (!_states.isClosed) {
      _states.add(value);
    }
  }
}

class _UpsyncPlatformPaths {
  const _UpsyncPlatformPaths({
    required this.currentExecutablePath,
    required this.currentExecutableName,
    required this.updatesDirectory,
    required this.appName,
  });

  final String currentExecutablePath;
  final String currentExecutableName;
  final String updatesDirectory;
  final String appName;
}
