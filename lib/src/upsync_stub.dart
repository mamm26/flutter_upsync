import 'dart:async';

import 'upsync_config.dart';
import 'upsync_state.dart';

/// Implementación no operativa usada en plataformas sin soporte.
class Upsync {
  Upsync._();

  /// Instancia singleton del actualizador.
  static final Upsync instance = Upsync._();

  final StreamController<UpsyncState> _states =
      StreamController<UpsyncState>.broadcast();

  final UpsyncState _state = const UpsyncState(
    status: UpsyncStatus.disabled,
    message: 'Actualizador Windows no disponible en esta plataforma.',
  );

  /// Flujo de cambios de estado del actualizador.
  Stream<UpsyncState> get states => _states.stream;

  /// Último estado conocido del actualizador.
  UpsyncState get state => _state;

  /// Inicializa el actualizador.
  Future<void> start(UpsyncConfig config) async {}

  /// Detiene cualquier operación programada del actualizador.
  Future<void> stop() async {}

  /// Fuerza una comprobación inmediata de actualización.
  Future<UpsyncState> checkNow() async => _state;

  /// Intenta aplicar una actualización descargada y reiniciar la app.
  Future<bool> applyDownloadedUpdateAndRestart() async => false;

  /// Elimina cualquier actualización pendiente almacenada localmente.
  Future<void> clearPendingUpdate() async {}
}
