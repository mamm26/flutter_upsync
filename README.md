# upsync

`upsync` es un plugin Flutter para Windows que sirve para actualizar una app de
escritorio sin meter la logica de actualizacion dentro de la app.

Hace tres cosas:

- revisa un manifest remoto;
- descarga la actualizacion si encuentra una version mas nueva;
- aplica el paquete al reiniciar y vuelve a abrir la app.

No trae interfaz. El plugin solo resuelve el trabajo de fondo. Tu app decide si
muestra un badge, un dialogo, un boton de "Reiniciar ahora" o si obliga al
usuario a actualizar.

Hoy el plugin soporta:

- Windows solamente;
- paquetes `.zip` con el release completo;
- paquetes `.exe`;
- validacion `sha256` si el manifest la trae;
- comprobacion automatica periodica;
- restauracion de una descarga pendiente si la app se vuelve a abrir.

## Uso desde cero

### 1. Instala el paquete

Desde GitHub:

```yaml
dependencies:
  upsync:
    git:
      url: https://github.com/mamm26/flutter_upsync
```

O localmente:

```yaml
dependencies:
  upsync:
    path: plugins/upsync
```

### 2. Importa el plugin

```dart
import 'package:upsync/upsync.dart';
```

### 3. Prepara los datos que necesita

Para arrancar `upsync`, tu app tiene que saber:

- donde esta el manifest;
- cual es la version instalada;
- cual es el build instalado;
- opcionalmente, el nombre con el que quieres guardar las descargas.

Ejemplo:

```dart
const manifestUrl = 'https://tu-dominio.com/windows/manifest.json';
const currentVersion = '1.1.1';
const currentBuildNumber = 113;
const appName = 'mi_app';
```

Si no mandas `appName`, el plugin usa el nombre del ejecutable actual.

### 4. Crea la configuracion

```dart
final config = UpsyncConfig(
  manifestUrl: manifestUrl,
  currentVersion: currentVersion,
  currentBuildNumber: currentBuildNumber,
  appName: appName,
);
```

Parametros disponibles:

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

Que hace `start()`:

1. valida que estas en Windows;
2. resuelve la ruta local de trabajo;
3. recupera una actualizacion pendiente si ya existia;
4. hace una comprobacion inmediata;
5. programa las comprobaciones periodicas.

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
    print('Hay una actualizacion lista');
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

Helpers utiles:

```dart
final ready = Upsync.instance.state.isReadyToInstall;
final showIndicator = Upsync.instance.state.showIndicator;
```

### 7. Fuerza una revision manual

```dart
final state = await Upsync.instance.checkNow();
```

Eso te sirve si quieres revisar actualizaciones al entrar al login, al abrir
una pantalla o desde un boton.

### 8. Aplica la actualizacion

Cuando la descarga ya este lista:

```dart
await Upsync.instance.applyDownloadedUpdateAndRestart();
```

Ese metodo:

1. lanza el helper nativo;
2. cierra la app actual;
3. aplica el paquete;
4. vuelve a abrir la app.

### 9. Limpia una actualizacion pendiente

Si por alguna razon necesitas borrar lo descargado:

```dart
await Upsync.instance.clearPendingUpdate();
```

Eso borra:

- `pending_update.json`;
- el paquete descargado pendiente, si existe.

## Manifest

El plugin acepta estas claves:

- version: `version` o `versionName`
- url: `url`, `downloadUrl` o `exeUrl`
- build: `buildNumber`, `build` o `versionCode`
- tipo: `packageType` o `type`
- hash: `sha256` o `checksum`
- notas: `notes` o `releaseNotes`
- tamano: `fileSizeBytes` o `size`

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

Como decide si una version es mas nueva:

- si el manifest trae `buildNumber` y tu config trae `currentBuildNumber`,
  compara esos numeros;
- si no, compara `version` contra `currentVersion`.

## Paquetes soportados

### ZIP

Es el caso mas util para Flutter Windows. El zip puede traer el contenido del
release en la raiz:

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

## Donde guarda los archivos

Ruta base:

```text
%LOCALAPPDATA%\<app>\updates\
```

Ahi guarda:

- subcarpetas por version;
- el paquete descargado;
- `pending_update.json`.

Si no envias `appName`, `<app>` sale del nombre del `.exe`.

## Detalles utiles antes de usarlo

- `manifestUrl` no puede ir vacio.
- `autoDownload` viene activado por defecto.
- si ya habia una descarga valida de una version mas nueva, `start()` la
  recupera sin volver a descargar.
- si el manifest trae `sha256`, el archivo se valida antes de marcarse como
  listo.
- hoy la API publica no expone un metodo aparte para descargar manualmente
  despues de marcar `autoDownload: false`.

## Ejemplo minimo

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
