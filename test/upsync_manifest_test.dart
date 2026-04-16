import 'package:flutter_test/flutter_test.dart';
import 'package:upsync/upsync.dart';

void main() {
  group('UpsyncManifest', () {
    test('parsea el formato recomendado', () {
      final manifest = UpsyncManifest.fromJson(const {
        'version': '1.2.0',
        'buildNumber': 12,
        'url': 'https://cdn.example.com/app.zip',
        'packageType': 'zip',
        'sha256': 'abc123',
        'notes': 'release notes',
        'fileSizeBytes': 321,
      });

      expect(manifest.version, '1.2.0');
      expect(manifest.buildNumber, 12);
      expect(manifest.downloadUrl, 'https://cdn.example.com/app.zip');
      expect(manifest.resolvedPackageType, 'zip');
      expect(manifest.sha256, 'abc123');
      expect(manifest.notes, 'release notes');
      expect(manifest.fileSizeBytes, 321);
      expect(manifest.identifier, '1.2.0+12');
    });

    test('acepta aliases y deduce exe por la extension', () {
      final manifest = UpsyncManifest.fromJson(const {
        'versionName': '2.0.0',
        'versionCode': '34',
        'downloadUrl': 'https://cdn.example.com/app.exe',
      });

      expect(manifest.version, '2.0.0');
      expect(manifest.buildNumber, 34);
      expect(manifest.downloadUrl, 'https://cdn.example.com/app.exe');
      expect(manifest.resolvedPackageType, 'exe');
    });
  });
}
