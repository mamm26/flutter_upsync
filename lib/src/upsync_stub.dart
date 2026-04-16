import 'dart:async';

import 'upsync_config.dart';
import 'upsync_state.dart';

class Upsync {
  Upsync._();

  static final Upsync instance = Upsync._();

  final StreamController<UpsyncState> _states =
      StreamController<UpsyncState>.broadcast();

  UpsyncState _state = const UpsyncState(
    status: UpsyncStatus.disabled,
    message: 'Actualizador Windows no disponible en esta plataforma.',
  );

  Stream<UpsyncState> get states => _states.stream;

  UpsyncState get state => _state;

  Future<void> start(UpsyncConfig config) async {}

  Future<void> stop() async {}

  Future<UpsyncState> checkNow() async => _state;

  Future<bool> applyDownloadedUpdateAndRestart() async => false;

  Future<void> clearPendingUpdate() async {}
}
