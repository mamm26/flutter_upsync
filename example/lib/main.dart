import 'dart:async';

import 'package:flutter/material.dart';
import 'package:upsync/upsync.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _manifestUrlController = TextEditingController(
    text: 'https://tu-servidor.com/windows/manifest.json',
  );
  final _versionController = TextEditingController(text: '1.0.0');
  final _buildController = TextEditingController(text: '1');
  StreamSubscription<UpsyncState>? _subscription;

  UpsyncState _state = Upsync.instance.state;
  bool _autoDownload = true;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _subscription = Upsync.instance.states.listen((state) {
      if (!mounted) {
        return;
      }

      setState(() {
        _state = state;
      });
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _manifestUrlController.dispose();
    _versionController.dispose();
    _buildController.dispose();
    unawaited(Upsync.instance.stop());
    super.dispose();
  }

  Future<void> _startWatcher() async {
    await Upsync.instance.start(
      UpsyncConfig(
        manifestUrl: _manifestUrlController.text.trim(),
        currentVersion: _versionController.text.trim(),
        currentBuildNumber: int.tryParse(_buildController.text.trim()) ?? 0,
        autoDownload: _autoDownload,
      ),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _started = true;
      _state = Upsync.instance.state;
    });
  }

  Future<void> _checkNow() async {
    final state = await Upsync.instance.checkNow();
    if (!mounted) {
      return;
    }

    setState(() {
      _state = state;
    });
  }

  Future<void> _clearPending() async {
    await Upsync.instance.clearPendingUpdate();
    if (!mounted) {
      return;
    }

    setState(() {
      _state = Upsync.instance.state;
    });
  }

  String _statusLabel(UpsyncStatus status) {
    switch (status) {
      case UpsyncStatus.idle:
        return 'Idle';
      case UpsyncStatus.disabled:
        return 'Disabled';
      case UpsyncStatus.checking:
        return 'Checking';
      case UpsyncStatus.upToDate:
        return 'Up to date';
      case UpsyncStatus.updateAvailable:
        return 'Update available';
      case UpsyncStatus.downloading:
        return 'Downloading';
      case UpsyncStatus.downloaded:
        return 'Downloaded';
      case UpsyncStatus.applying:
        return 'Applying';
      case UpsyncStatus.error:
        return 'Error';
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Upsync example')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Configura aqui el manifest y prueba el flujo del plugin en Windows.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _manifestUrlController,
              decoration: const InputDecoration(
                labelText: 'Manifest URL',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _versionController,
              decoration: const InputDecoration(
                labelText: 'Current version',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _buildController,
              decoration: const InputDecoration(
                labelText: 'Current build number',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _autoDownload,
              onChanged: (value) {
                setState(() {
                  _autoDownload = value;
                });
              },
              contentPadding: EdgeInsets.zero,
              title: const Text('Descargar automaticamente'),
            ),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton(
                  onPressed: _startWatcher,
                  child: const Text('Iniciar upsync'),
                ),
                OutlinedButton(
                  onPressed: _started ? _checkNow : null,
                  child: const Text('Revisar ahora'),
                ),
                OutlinedButton(
                  onPressed: _state.isReadyToInstall
                      ? () => Upsync.instance.applyDownloadedUpdateAndRestart()
                      : null,
                  child: const Text('Aplicar y reiniciar'),
                ),
                TextButton(
                  onPressed: _clearPending,
                  child: const Text('Limpiar pendiente'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Estado: ${_statusLabel(_state.status)}'),
                    const SizedBox(height: 8),
                    Text('Mensaje: ${_state.message ?? '-'}'),
                    const SizedBox(height: 8),
                    Text('Error: ${_state.error ?? '-'}'),
                    const SizedBox(height: 8),
                    Text(
                      'Progreso: ${_state.progress == null ? '-' : '${(_state.progress! * 100).toStringAsFixed(0)}%'}',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Archivo descargado: ${_state.downloadedFilePath ?? '-'}',
                    ),
                  ],
                ),
              ),
            ),
            if (_state.manifest != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Version remota: ${_state.manifest!.version}'),
                      const SizedBox(height: 8),
                      Text('Build remoto: ${_state.manifest!.buildNumber}'),
                      const SizedBox(height: 8),
                      Text('Tipo: ${_state.manifest!.resolvedPackageType}'),
                      const SizedBox(height: 8),
                      Text('URL: ${_state.manifest!.downloadUrl}'),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
