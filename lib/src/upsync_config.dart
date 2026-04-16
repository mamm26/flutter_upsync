class UpsyncConfig {
  const UpsyncConfig({
    required this.manifestUrl,
    required this.currentVersion,
    required this.currentBuildNumber,
    this.appName = '',
    this.checkInterval = const Duration(minutes: 30),
    this.requestHeaders = const {},
    this.autoDownload = true,
    this.requestTimeout = const Duration(seconds: 45),
  });

  /// URL del manifest remoto.
  final String manifestUrl;

  /// Version instalada para comparar contra el manifest.
  final String currentVersion;

  /// Build instalada cuando el manifest tambien trae buildNumber.
  final int currentBuildNumber;

  /// Nombre opcional para la carpeta local. Si va vacio, sale del exe.
  final String appName;
  final Duration checkInterval;
  final Map<String, String> requestHeaders;
  final bool autoDownload;
  final Duration requestTimeout;
}
