import 'package:flutter_test/flutter_test.dart';
import 'package:upsync/upsync.dart';

void main() {
  group('UpsyncConfig', () {
    test('configura Microsoft Store sin manifest remoto', () {
      const config = UpsyncConfig.microsoftStore();

      expect(config.updateSource, UpsyncUpdateSource.microsoftStore);
      expect(config.usesMicrosoftStore, isTrue);
      expect(config.manifestUrl, isEmpty);
      expect(config.autoDownload, isFalse);
      expect(config.installMicrosoftStoreUpdates, isTrue);
    });
  });
}
