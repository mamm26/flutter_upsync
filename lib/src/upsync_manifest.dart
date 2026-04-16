class UpsyncManifest {
  const UpsyncManifest({
    required this.version,
    required this.downloadUrl,
    this.buildNumber = 0,
    this.packageType,
    this.sha256,
    this.notes,
    this.fileSizeBytes,
  });

  final String version;
  final int buildNumber;
  final String downloadUrl;
  final String? packageType;
  final String? sha256;
  final String? notes;
  final int? fileSizeBytes;

  String get identifier =>
      buildNumber > 0 ? '$version+$buildNumber' : version;

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
