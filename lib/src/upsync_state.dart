import 'upsync_manifest.dart';

enum UpsyncStatus {
  idle,
  disabled,
  checking,
  upToDate,
  updateAvailable,
  downloading,
  downloaded,
  applying,
  error,
}

class UpsyncState {
  const UpsyncState({
    this.status = UpsyncStatus.idle,
    this.manifest,
    this.downloadedFilePath,
    this.progress,
    this.lastCheckedAt,
    this.message,
    this.error,
  });

  final UpsyncStatus status;
  final UpsyncManifest? manifest;
  final String? downloadedFilePath;
  final double? progress;
  final DateTime? lastCheckedAt;
  final String? message;
  final String? error;

  bool get isReadyToInstall =>
      status == UpsyncStatus.downloaded &&
      downloadedFilePath != null &&
      downloadedFilePath!.isNotEmpty;

  bool get showIndicator =>
      status == UpsyncStatus.updateAvailable ||
      status == UpsyncStatus.downloading ||
      status == UpsyncStatus.downloaded;

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
