/// Describe una versión disponible para descargar e instalar.
class UpsyncManifest {
  /// Crea una representación inmutable del manifiesto remoto.
  const UpsyncManifest({
    required this.version,
    required this.downloadUrl,
    this.buildNumber = 0,
    this.packageType,
    this.sha256,
    this.notes,
    this.fileSizeBytes,
  });

  /// Versión legible de la actualización.
  final String version;

  /// Número de compilación usado como criterio adicional de comparación.
  final int buildNumber;

  /// URL desde la que se descarga el paquete de actualización.
  final String downloadUrl;

  /// Tipo explícito del paquete remoto, si el manifiesto lo informa.
  final String? packageType;

  /// Hash SHA-256 esperado del archivo descargado.
  final String? sha256;

  /// Notas o cambios relevantes de la versión.
  final String? notes;

  /// Tamaño esperado del archivo en bytes.
  final int? fileSizeBytes;

  /// Identificador estable de la versión, incluyendo build cuando existe.
  String get identifier =>
      buildNumber > 0 ? '$version+$buildNumber' : version;

  /// Tipo de paquete resuelto a partir del manifiesto o de la URL.
  String get resolvedPackageType {
    final normalized = packageType?.trim().toLowerCase();
    if (normalized == 'zip' || normalized == 'exe') {
      return normalized!;
    }

    final uri = Uri.tryParse(downloadUrl);
    final path = uri?.path.toLowerCase() ?? downloadUrl.toLowerCase();
    if (path.endsWith('.zip')) {
      return 'zip';
    }

    return 'exe';
  }

  /// Construye una instancia a partir del JSON recibido desde el servidor.
  factory UpsyncManifest.fromJson(Map<String, dynamic> json) {
    final version = (json['version'] ?? json['versionName'] ?? '')
        .toString()
        .trim();
    final downloadUrl = (json['url'] ?? json['downloadUrl'] ?? json['exeUrl'])
        .toString()
        .trim();

    if (version.isEmpty) {
      throw const FormatException(
          'El manifiesto de actualización no incluye "version".');
    }

    if (downloadUrl.isEmpty) {
      throw const FormatException(
          'El manifiesto de actualización no incluye "url".');
    }

    return UpsyncManifest(
      version: version,
      buildNumber: _parseInt(
          json['buildNumber'] ?? json['build'] ?? json['versionCode']),
      downloadUrl: downloadUrl,
      packageType: _nullableString(json['packageType'] ?? json['type']),
      sha256: _nullableString(json['sha256'] ?? json['checksum']),
      notes: _nullableString(json['notes'] ?? json['releaseNotes']),
      fileSizeBytes: _parseNullableInt(json['fileSizeBytes'] ?? json['size']),
    );
  }

  /// Convierte la instancia al formato JSON persistido localmente.
  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'buildNumber': buildNumber,
      'url': downloadUrl,
      'packageType': packageType,
      'sha256': sha256,
      'notes': notes,
      'fileSizeBytes': fileSizeBytes,
    };
  }

  static int _parseInt(dynamic value) {
    if (value is int) {
      return value;
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int? _parseNullableInt(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    return int.tryParse(value.toString());
  }

  static String? _nullableString(dynamic value) {
    final normalized = value?.toString().trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    return normalized;
  }
}
