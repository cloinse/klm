# Kontakt Library Manager

Aplicación Flutter de escritorio para inventariar y diagnosticar librerías de
Kontakt en macOS y Windows.

## Estado actual

El inventario y los diagnósticos son funcionales en ambas plataformas:

- Usa inglés de forma predeterminada y permite seleccionar español o portugués
  de Brasil desde Settings. La selección se aplica inmediatamente y se guarda.
- Reconcilia XML de Service Center, PLIST de macOS y JSON de
  `installed_products`.
- Muestra el SNPID normalizado de cada librería y reserva el indicador de estado
  para sus diagnósticos generales.
- Detecta registros incompletos, rutas perdidas, discos desconectados, SNPID
  duplicados y rutas compartidas.
- Permite buscar, filtrar, ordenar y mostrar el contenido en Finder/Explorador.
- Conserva un registro de operaciones y errores durante la sesión.
- Se centra exclusivamente en el navegador clásico de Kontakt. Lee el orden
  `UserListIndex`, permite reorganizar librerías mediante arrastre y guarda los
  cambios en las preferencias del usuario de macOS o en `HKCU` de Windows sin
  autorización administrativa.
- En Windows reconcilia XML, JSON y las vistas de 32/64 bits del Registro. Las
  altas, reparaciones, reubicaciones y eliminaciones se ejecutan mediante un
  helper puntual que solicita UAC únicamente al confirmar cada cambio.

Los flujos de alta individual y por lote, reparación, reubicación y eliminación
exclusiva de registros se canalizan a componentes incluidos con la aplicación.
Al confirmar un cambio, el sistema muestra su diálogo normal de administrador,
ejecuta una sola transacción y cierra el componente inmediatamente. La app
Flutter no se ejecuta como administrador y los helpers no aceptan rutas de
destino arbitrarias.

Ni la aplicación ni el helper son procesos residentes. No se instala ningún
LaunchDaemon, servicio XPC, Ítem de inicio ni componente de fondo. La aplicación
termina al cerrar su última ventana y el helper existe únicamente mientras se
aplica una operación confirmada. Tampoco se abre Terminal ni se invoca `sudo`.

Las versiones Release se distribuyen en un DMG visual con la aplicación, una
flecha de instalación y un enlace a Applications; solo pueden ejecutarse desde
`/Applications`. Las actualizaciones de macOS usan Sparkle con firma Ed25519 y
firma ad-hoc del bundle. KLM hace una comprobación silenciosa al abrirse y
muestra un aviso cuando hay una nueva versión; la descarga e instalación solo
se inicia por decisión del usuario. No mantiene procesos cuando KLM está
cerrada. El procedimiento de publicación está documentado en
[`docs/updates.md`](docs/updates.md).

La misma estrategia puntual se conserva en la compilación compatible con macOS
10.15 mediante el workflow `macos-catalina-legacy` de Codemagic. El proyecto
local permanece en macOS 12; únicamente el checkout temporal de CI cambia el
deployment target. La matriz está documentada en
[`docs/build-matrix.md`](docs/build-matrix.md).

## Desarrollo

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d macos
```

Para crear el DMG local después de una compilación Release:

```sh
tool/package_macos_dmg.sh
```

La compilación de Windows debe ejecutarse y validarse en Windows:

```powershell
flutter build windows
```

## Arquitectura

```text
lib/
  app/                       tema y raíz de la aplicación
  core/models/               modelo común de librerías y diagnósticos
  core/metadata/             extracción segura de ProductHints
  core/validation/           rutas, duplicados y registros incompletos
  features/libraries/        controlador e interfaz principal
  platform/                  contrato común y ensamblador de inventario
  platform/macos/            XML, PLIST y JSON de macOS
  platform/windows/          XML, JSON y Registro de Windows
```

El navegador moderno, los mosaicos NKS y la base de datos `komplete.db3` quedan
fuera del alcance. Kontakt y cualquier DAW que lo esté utilizando deben cerrarse
antes de guardar un nuevo orden clásico.
