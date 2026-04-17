/// Configuración del actualizador para Windows.
class UpsyncConfig {
  /// Crea una configuración para consultar, descargar y aplicar actualizaciones.
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

  /// Versión instalada para comparar contra el manifest.
  final String currentVersion;

  /// Build instalada cuando el manifest también trae `buildNumber`.
  final int currentBuildNumber;

  /// Nombre opcional para la carpeta local. Si va vacío, sale del exe.
  final String appName;

  /// Intervalo entre revisiones automáticas del manifiesto remoto.
  final Duration checkInterval;

  /// Encabezados HTTP adicionales para las solicitudes del actualizador.
  final Map<String, String> requestHeaders;

  /// Indica si la descarga debe iniciar automáticamente al detectar una actualización.
  final bool autoDownload;

  /// Tiempo máximo para completar cada solicitud HTTP.
  final Duration requestTimeout;
}
