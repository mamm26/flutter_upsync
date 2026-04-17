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
    this.manifest,
    this.downloadedFilePath,
    this.progress,
    this.lastCheckedAt,
    this.message,
    this.error,
  });

  /// Estado actual del flujo de actualización.
  final UpsyncStatus status;

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

  /// Indica si existe un paquete descargado listo para instalar.
  bool get isReadyToInstall =>
      status == UpsyncStatus.downloaded &&
      downloadedFilePath != null &&
      downloadedFilePath!.isNotEmpty;

  /// Indica si conviene mostrar un indicador visible de actualización.
  bool get showIndicator =>
      status == UpsyncStatus.updateAvailable ||
      status == UpsyncStatus.downloading ||
      status == UpsyncStatus.downloaded;

  /// Crea una copia del estado actual con cambios puntuales.
  UpsyncState copyWith({
    UpsyncStatus? status,
    UpsyncManifest? manifest,
    String? downloadedFilePath,
    double? progress,
    DateTime? lastCheckedAt,
    String? message,
    String? error,
    bool clearManifest = false,
    bool clearDownloadedFilePath = false,
    bool clearProgress = false,
    bool clearLastCheckedAt = false,
    bool clearMessage = false,
    bool clearError = false,
  }) {
    return UpsyncState(
      status: status ?? this.status,
      manifest: clearManifest ? null : (manifest ?? this.manifest),
      downloadedFilePath: clearDownloadedFilePath
          ? null
          : (downloadedFilePath ?? this.downloadedFilePath),
      progress: clearProgress ? null : (progress ?? this.progress),
      lastCheckedAt:
          clearLastCheckedAt ? null : (lastCheckedAt ?? this.lastCheckedAt),
      message: clearMessage ? null : (message ?? this.message),
      error: clearError ? null : (error ?? this.error),
    );
  }
}
