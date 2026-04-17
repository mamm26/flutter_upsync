# upsync

## Menu / Menú

- [English](#english)
- [Español](#espanol)

<a id="english"></a>
## English

`upsync` is a Flutter plugin for Windows that keeps a desktop application up to
date by checking a remote manifest, downloading a newer package, and applying
it on restart.

It does three things:

- checks a remote manifest;
- downloads the update when a newer version is available;
- applies the package on restart and relaunches the app.

It does not include a UI. The plugin only handles the background workflow. Your
app decides whether to show a badge, a dialog, a "Restart now" button, or to
require the user to update.

The plugin currently supports:

- Windows only;
- full release `.zip` packages;
- `.exe` packages;
- `sha256` validation when provided by the manifest;
- automatic periodic checks;
- restoration of a pending download when the app is opened again.

## Getting Started

### 1. Install the package

From pub.dev:

```yaml
dependencies:
  upsync: ^0.0.1+2
```

Or directly from GitHub:

```yaml
dependencies:
  upsync:
    git:
      url: https://github.com/mamm26/flutter_upsync
```

### 2. Import the plugin

```dart
import 'package:upsync/upsync.dart';
```

### 3. Prepare the required values

To start `upsync`, your app needs to know:

- where the manifest is hosted;
- which version is currently installed;
- which build is currently installed;
- optionally, the file name to use for downloaded packages.

Example:

```dart
const manifestUrl = 'https://your-domain.com/windows/manifest.json';
const currentVersion = '1.1.1';
const currentBuildNumber = 113;
const appName = 'my_app';
```

If you do not provide `appName`, the plugin uses the current executable name.

### 4. Create the configuration

```dart
final config = UpsyncConfig(
  manifestUrl: manifestUrl,
  currentVersion: currentVersion,
  currentBuildNumber: currentBuildNumber,
  appName: appName,
);
```

Available parameters:

- `manifestUrl`
- `currentVersion`
- `currentBuildNumber`
- `appName`
- `checkInterval`
- `requestHeaders`
- `autoDownload`
- `requestTimeout`

Default values:

- `checkInterval`: 30 minutes
- `autoDownload`: `true`
- `requestTimeout`: 45 seconds

### 5. Start the plugin

Call it once when your app starts:

```dart
await Upsync.instance.start(config);
```

Simple example:

```dart
Future<void> initUpsync() async {
  await Upsync.instance.start(
    const UpsyncConfig(
      manifestUrl: 'https://your-domain.com/windows/manifest.json',
      currentVersion: '1.1.1',
      currentBuildNumber: 113,
      appName: 'my_app',
    ),
  );
}
```

What `start()` does:

1. validates that the app is running on Windows;
2. resolves the local working path;
3. restores a pending update if one already exists;
4. performs an immediate check;
5. schedules periodic checks.

### 6. Read the state

Current state:

```dart
final state = Upsync.instance.state;
```

State change stream:

```dart
Upsync.instance.states.listen((state) {
  if (state.status == UpsyncStatus.downloading) {
    print(state.progress);
  }

  if (state.isReadyToInstall) {
    print('An update is ready');
  }
});
```

Available statuses:

- `UpsyncStatus.idle`
- `UpsyncStatus.disabled`
- `UpsyncStatus.checking`
- `UpsyncStatus.upToDate`
- `UpsyncStatus.updateAvailable`
- `UpsyncStatus.downloading`
- `UpsyncStatus.downloaded`
- `UpsyncStatus.applying`
- `UpsyncStatus.error`

Useful helpers:

```dart
final ready = Upsync.instance.state.isReadyToInstall;
final showIndicator = Upsync.instance.state.showIndicator;
```

### 7. Force a manual check

```dart
final state = await Upsync.instance.checkNow();
```

This is useful if you want to check for updates after login, when opening a
screen, or from a button.

### 8. Apply the update

When the download is ready:

```dart
await Upsync.instance.applyDownloadedUpdateAndRestart();
```

This method:

1. launches the native helper;
2. closes the current app;
3. applies the package;
4. relaunches the app.

### 9. Clear a pending update

If you need to remove the downloaded update:

```dart
await Upsync.instance.clearPendingUpdate();
```

This removes:

- `pending_update.json`;
- the pending downloaded package, if it exists.

## Manifest

The plugin accepts these keys:

- version: `version` or `versionName`
- url: `url`, `downloadUrl` or `exeUrl`
- build: `buildNumber`, `build` or `versionCode`
- type: `packageType` or `type`
- hash: `sha256` or `checksum`
- notes: `notes` or `releaseNotes`
- size: `fileSizeBytes` or `size`

Recommended example:

```json
{
  "version": "1.1.1",
  "buildNumber": 113,
  "url": "https://your-domain.com/releases/my-app-windows.zip",
  "packageType": "zip",
  "sha256": "optional_sha256",
  "notes": "Optional notes",
  "fileSizeBytes": 12345678
}
```

Required fields:

- `version`
- `url`

How it decides whether a version is newer:

- if the manifest includes `buildNumber` and your configuration includes
  `currentBuildNumber`, it compares those numbers;
- otherwise, it compares `version` against `currentVersion`.

## Supported Packages

### ZIP

This is the most useful case for Flutter Windows. The zip file can include the
release content at the root:

```text
my_app.exe
flutter_windows.dll
data/
```

Or inside a single folder:

```text
my-app-windows/
  my_app.exe
  flutter_windows.dll
  data/
```

Both formats are supported.

### EXE

If the manifest points to an `.exe`, the plugin attempts to replace the current
executable.

## Where Files Are Stored

Base path:

```text
%LOCALAPPDATA%\<app>\updates\
```

Stored there:

- version-specific subfolders;
- the downloaded package;
- `pending_update.json`.

If you do not provide `appName`, `<app>` is derived from the `.exe` name.

## Useful Details Before You Use It

- `manifestUrl` cannot be empty.
- `autoDownload` is enabled by default.
- if there is already a valid download for a newer version, `start()` restores
  it without downloading again.
- if the manifest includes `sha256`, the file is validated before it is marked
  as ready.
- the current public API does not expose a separate manual download method
  after setting `autoDownload: false`.

## Minimal Example

```dart
import 'package:flutter/material.dart';
import 'package:upsync/upsync.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Upsync.instance.start(
    const UpsyncConfig(
      manifestUrl: 'https://your-domain.com/windows/manifest.json',
      currentVersion: '1.1.1',
      currentBuildNumber: 113,
      appName: 'my_app',
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();

    Upsync.instance.states.listen((state) async {
      if (state.isReadyToInstall) {
        await Upsync.instance.applyDownloadedUpdateAndRestart();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('Upsync active'),
        ),
      ),
    );
  }
}
```

<a id="espanol"></a>
## Español

`upsync` es un plugin de Flutter para Windows que mantiene actualizada una
aplicación de escritorio mediante la revisión de un manifest remoto, la
descarga de un paquete más reciente y su aplicación al reiniciar.

Hace tres cosas:

- revisa un manifest remoto;
- descarga la actualización si encuentra una versión más nueva;
- aplica el paquete al reiniciar y vuelve a abrir la app.

No trae interfaz. El plugin solo resuelve el trabajo de fondo. Tu app decide
si muestra un badge, un diálogo, un botón de "Reiniciar ahora" o si obliga al
usuario a actualizar.

Hoy el plugin soporta:

- Windows solamente;
- paquetes `.zip` con el release completo;
- paquetes `.exe`;
- validación `sha256` si el manifest la trae;
- comprobación automática periódica;
- restauración de una descarga pendiente si la app se vuelve a abrir.

## Uso desde cero

### 1. Instala el paquete

Desde pub.dev:

```yaml
dependencies:
  upsync: ^0.0.1+2
```

O directamente desde GitHub:

```yaml
dependencies:
  upsync:
    git:
      url: https://github.com/mamm26/flutter_upsync
```

### 2. Importa el plugin

```dart
import 'package:upsync/upsync.dart';
```

### 3. Prepara los datos que necesita

Para arrancar `upsync`, tu app tiene que saber:

- dónde está el manifest;
- cuál es la versión instalada;
- cuál es el build instalado;
- opcionalmente, el nombre con el que quieres guardar las descargas.

Ejemplo:

```dart
const manifestUrl = 'https://tu-dominio.com/windows/manifest.json';
const currentVersion = '1.1.1';
const currentBuildNumber = 113;
const appName = 'mi_app';
```

Si no mandas `appName`, el plugin usa el nombre del ejecutable actual.

### 4. Crea la configuración

```dart
final config = UpsyncConfig(
  manifestUrl: manifestUrl,
  currentVersion: currentVersion,
  currentBuildNumber: currentBuildNumber,
  appName: appName,
);
```

Parámetros disponibles:

- `manifestUrl`
- `currentVersion`
- `currentBuildNumber`
- `appName`
- `checkInterval`
- `requestHeaders`
- `autoDownload`
- `requestTimeout`

Valores por defecto:

- `checkInterval`: 30 minutos
- `autoDownload`: `true`
- `requestTimeout`: 45 segundos

### 5. Inicia el plugin

Hazlo una vez cuando arranque tu app:

```dart
await Upsync.instance.start(config);
```

Ejemplo simple:

```dart
Future<void> initUpsync() async {
  await Upsync.instance.start(
    const UpsyncConfig(
      manifestUrl: 'https://tu-dominio.com/windows/manifest.json',
      currentVersion: '1.1.1',
      currentBuildNumber: 113,
      appName: 'mi_app',
    ),
  );
}
```

Qué hace `start()`:

1. valida que estás en Windows;
2. resuelve la ruta local de trabajo;
3. recupera una actualización pendiente si ya existía;
4. hace una comprobación inmediata;
5. programa las comprobaciones periódicas.

### 6. Lee el estado

Estado actual:

```dart
final state = Upsync.instance.state;
```

Stream de cambios:

```dart
Upsync.instance.states.listen((state) {
  if (state.status == UpsyncStatus.downloading) {
    print(state.progress);
  }

  if (state.isReadyToInstall) {
    print('Hay una actualización lista');
  }
});
```

Estados disponibles:

- `UpsyncStatus.idle`
- `UpsyncStatus.disabled`
- `UpsyncStatus.checking`
- `UpsyncStatus.upToDate`
- `UpsyncStatus.updateAvailable`
- `UpsyncStatus.downloading`
- `UpsyncStatus.downloaded`
- `UpsyncStatus.applying`
- `UpsyncStatus.error`

Helpers útiles:

```dart
final ready = Upsync.instance.state.isReadyToInstall;
final showIndicator = Upsync.instance.state.showIndicator;
```

### 7. Fuerza una revisión manual

```dart
final state = await Upsync.instance.checkNow();
```

Eso te sirve si quieres revisar actualizaciones al entrar al login, al abrir
una pantalla o desde un botón.

### 8. Aplica la actualización

Cuando la descarga ya esté lista:

```dart
await Upsync.instance.applyDownloadedUpdateAndRestart();
```

Ese método:

1. lanza el helper nativo;
2. cierra la app actual;
3. aplica el paquete;
4. vuelve a abrir la app.

### 9. Limpia una actualización pendiente

Si por alguna razón necesitas borrar lo descargado:

```dart
await Upsync.instance.clearPendingUpdate();
```

Eso borra:

- `pending_update.json`;
- el paquete descargado pendiente, si existe.

## Manifest

El plugin acepta estas claves:

- versión: `version` o `versionName`
- url: `url`, `downloadUrl` o `exeUrl`
- build: `buildNumber`, `build` o `versionCode`
- tipo: `packageType` o `type`
- hash: `sha256` o `checksum`
- notas: `notes` o `releaseNotes`
- tamaño: `fileSizeBytes` o `size`

Ejemplo recomendado:

```json
{
  "version": "1.1.1",
  "buildNumber": 113,
  "url": "https://tu-dominio.com/releases/mi-app-windows.zip",
  "packageType": "zip",
  "sha256": "opcional_sha256",
  "notes": "Notas opcionales",
  "fileSizeBytes": 12345678
}
```

Campos obligatorios:

- `version`
- `url`

Cómo decide si una versión es más nueva:

- si el manifest trae `buildNumber` y tu config trae `currentBuildNumber`,
  compara esos números;
- si no, compara `version` contra `currentVersion`.

## Paquetes soportados

### ZIP

Es el caso más útil para Flutter Windows. El zip puede traer el contenido del
release en la raíz:

```text
mi_app.exe
flutter_windows.dll
data/
```

O dentro de una sola carpeta:

```text
mi-app-windows/
  mi_app.exe
  flutter_windows.dll
  data/
```

Ambos formatos funcionan.

### EXE

Si el manifest apunta a un `.exe`, el plugin intenta reemplazar el ejecutable
actual.

## Dónde guarda los archivos

Ruta base:

```text
%LOCALAPPDATA%\<app>\updates\
```

Ahí guarda:

- subcarpetas por versión;
- el paquete descargado;
- `pending_update.json`.

Si no envías `appName`, `<app>` sale del nombre del `.exe`.

## Detalles útiles antes de usarlo

- `manifestUrl` no puede ir vacío.
- `autoDownload` viene activado por defecto.
- si ya había una descarga válida de una versión más nueva, `start()` la
  recupera sin volver a descargar.
- si el manifest trae `sha256`, el archivo se valida antes de marcarse como
  listo.
- hoy la API pública no expone un método aparte para descargar manualmente
  después de marcar `autoDownload: false`.

## Ejemplo mínimo

```dart
import 'package:flutter/material.dart';
import 'package:upsync/upsync.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Upsync.instance.start(
    const UpsyncConfig(
      manifestUrl: 'https://tu-dominio.com/windows/manifest.json',
      currentVersion: '1.1.1',
      currentBuildNumber: 113,
      appName: 'mi_app',
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();

    Upsync.instance.states.listen((state) async {
      if (state.isReadyToInstall) {
        await Upsync.instance.applyDownloadedUpdateAndRestart();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('Upsync activo'),
        ),
      ),
    );
  }
}
```
