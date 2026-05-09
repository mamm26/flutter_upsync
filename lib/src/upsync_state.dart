import 'upsync_config.dart';
import 'upsync_manifest.dart';

/// Estados posibles del ciclo de actualización.
enum UpsyncStatus {
  /// El actualizador está inactivo y sin trabajo pendiente.
  idle,

  /// La plataforma actual no admite el actualizador.
  disabled,

  /// Se está consultando el manifiesto remoto.
  checking,

  /// La aplicación local ya está actualizada.
  upToDate,

  /// Existe una versión nueva disponible para descargar.
  updateAvailable,

  /// El paquete se está descargando.
  downloading,

  /// La actualización ya se descargó y puede instalarse.
  downloaded,

  /// Se está intentando aplicar la actualización descargada.
  applying,

  /// Ocurrió un error durante el proceso.
  error,
}

/// Estado observable del actualizador.
class UpsyncState {
  /// Crea un estado inmutable del actualizador.
  const UpsyncState({
    this.status = UpsyncStatus.idle,
    this.updateSource = UpsyncUpdateSource.manifest,
    this.manifest,
    this.downloadedFilePath,
    this.progress,
    this.lastCheckedAt,
    this.message,
    this.error,
    this.microsoftStoreUpdateCount = 0,
    this.microsoftStoreInstallRequested = false,
    this.microsoftStoreInstallCompleted = false,
    this.microsoftStoreResult,
  });

  /// Estado actual del flujo de actualización.
  final UpsyncStatus status;

  /// Canal que produjo el estado actual.
  final UpsyncUpdateSource updateSource;

  /// Manifiesto detectado o descargado más recientemente.
  final UpsyncManifest? manifest;

  /// Ruta local del instalador o paquete descargado.
  final String? downloadedFilePath;

  /// Progreso actual de descarga entre `0.0` y `1.0`.
  final double? progress;

  /// Momento de la última revisión del manifiesto.
  final DateTime? lastCheckedAt;

  /// Mensaje informativo para la interfaz.
  final String? message;

  /// Descripción del error más reciente.
  final String? error;

  /// Cantidad de paquetes con actualización disponibles en Microsoft Store.
  final int microsoftStoreUpdateCount;

  /// Indica si se pidió a Microsoft Store instalar una actualización.
  final bool microsoftStoreInstallRequested;

  /// Indica si Microsoft Store terminó correctamente la instalación.
  final bool microsoftStoreInstallCompleted;

  /// Resultado nativo informado por Microsoft Store.
  final String? microsoftStoreResult;

  /// Indica si existe un paquete descargado listo para instalar.
  bool get isReadyToInstall =>
      status == UpsyncStatus.downloaded &&
      downloadedFilePath != null &&
      downloadedFilePath!.isNotEmpty;

  /// Indica si se puede iniciar la aplicación de una actualización.
  bool get canApplyUpdate =>
      isReadyToInstall ||
      (updateSource == UpsyncUpdateSource.microsoftStore &&
          status == UpsyncStatus.updateAvailable);

  /// Indica si conviene mostrar un indicador visible de actualización.
  bool get showIndicator =>
      status == UpsyncStatus.updateAvailable ||
      status == UpsyncStatus.downloading ||
      status == UpsyncStatus.downloaded ||
      status == UpsyncStatus.applying;

  /// Crea una copia del estado actual con cambios puntuales.
  UpsyncState copyWith({
    UpsyncStatus? status,
    UpsyncUpdateSource? updateSource,
    UpsyncManifest? manifest,
    String? downloadedFilePath,
    double? progress,
    DateTime? lastCheckedAt,
    String? message,
    String? error,
    int? microsoftStoreUpdateCount,
    bool? microsoftStoreInstallRequested,
    bool? microsoftStoreInstallCompleted,
    String? microsoftStoreResult,
    bool clearManifest = false,
    bool clearDownloadedFilePath = false,
    bool clearProgress = false,
    bool clearLastCheckedAt = false,
    bool clearMessage = false,
    bool clearError = false,
    bool clearMicrosoftStoreResult = false,
  }) {
    return UpsyncState(
      status: status ?? this.status,
      updateSource: updateSource ?? this.updateSource,
      manifest: clearManifest ? null : (manifest ?? this.manifest),
      downloadedFilePath: clearDownloadedFilePath
          ? null
          : (downloadedFilePath ?? this.downloadedFilePath),
      progress: clearProgress ? null : (progress ?? this.progress),
      lastCheckedAt:
          clearLastCheckedAt ? null : (lastCheckedAt ?? this.lastCheckedAt),
      message: clearMessage ? null : (message ?? this.message),
      error: clearError ? null : (error ?? this.error),
      microsoftStoreUpdateCount:
          microsoftStoreUpdateCount ?? this.microsoftStoreUpdateCount,
      microsoftStoreInstallRequested:
          microsoftStoreInstallRequested ?? this.microsoftStoreInstallRequested,
      microsoftStoreInstallCompleted:
          microsoftStoreInstallCompleted ?? this.microsoftStoreInstallCompleted,
      microsoftStoreResult: clearMicrosoftStoreResult
          ? null
          : (microsoftStoreResult ?? this.microsoftStoreResult),
    );
  }
}
