import 'package:flutter_test/flutter_test.dart';
import 'package:upsync/upsync.dart';

void main() {
  group('UpsyncState', () {
    test('marca listo para instalar cuando hay archivo descargado', () {
      const state = UpsyncState(
        status: UpsyncStatus.downloaded,
        downloadedFilePath: 'C:/temp/app.zip',
      );

      expect(state.isReadyToInstall, isTrue);
      expect(state.showIndicator, isTrue);
    });

    test('copyWith permite limpiar campos puntuales', () {
      const original = UpsyncState(
        status: UpsyncStatus.error,
        message: 'fallo',
        error: 'boom',
      );

      final updated = original.copyWith(
        status: UpsyncStatus.idle,
        clearMessage: true,
        clearError: true,
      );

      expect(updated.status, UpsyncStatus.idle);
      expect(updated.message, isNull);
      expect(updated.error, isNull);
    });

    test('marca aplicable una actualización detectada por Microsoft Store', () {
      const state = UpsyncState(
        status: UpsyncStatus.updateAvailable,
        updateSource: UpsyncUpdateSource.microsoftStore,
        microsoftStoreUpdateCount: 1,
      );

      expect(state.canApplyUpdate, isTrue);
      expect(state.isReadyToInstall, isFalse);
      expect(state.showIndicator, isTrue);
    });
  });
}
