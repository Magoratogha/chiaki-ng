# SETUP.md — Reconstruir el ambiente de desarrollo desde cero

Esta guía asume que estás en una Windows 11 nueva (o querés reconstruir el
ambiente desde cero) y vas a clonar **tu propio fork** (no el chiaki-ng
original) — el código de la Ally X ya está commiteado ahí, así que **no
hace falta re-aplicar ningún patch de C++/QML manualmente**, solo instalar
herramientas y compilar.

Todos los comandos son PowerShell. Reemplazá `TU-USUARIO` por tu usuario
real de GitHub en todos los pasos.

---

## 0. Prerrequisitos base

```powershell
winget install Git.Git
winget install Kitware.CMake
winget install Ninja-build.Ninja
winget install Python.Python.3.12
winget install LLVM.LLVM
```

Instalá también **Visual Studio Build Tools 2022** (buscalo en
visualstudio.microsoft.com/downloads, sección "Tools for Visual Studio"),
con el workload **"Desktop development with C++"** tildado. Esto te da
`cl.exe`, el linker, y el Windows SDK.

**Regla de oro para toda esta guía:** cualquier paso que compile algo
(no solo `cmake --build`, también `meson`, `ninja`, clones que después vas
a compilar) tiene que correrse desde una terminal con el entorno de MSVC
cargado. La forma más simple: abrí **"x64 Native Tools Command Prompt for
VS 2022"** desde el menú de inicio, y ahí adentro escribí `powershell`
para lanzar una PowerShell que herede esas variables. Una PowerShell
"normal" sin pasar por ahí va a fallar con errores raros tipo "clang-cl
cannot compile programs" o no va a encontrar `cl.exe`.

Reabrí la terminal después de instalar todo esto, para que el PATH se
actualice.

---

## 1. Clonar tu fork

```powershell
cd C:\dev
git clone --recursive https://github.com/TU-USUARIO/chiaki-ng-ally-x.git chiaki-ng
cd chiaki-ng
```

(Si en algún momento querés traer actualizaciones del chiaki-ng original,
podés agregarlo como remote: `git remote add upstream https://github.com/streetpea/chiaki-ng.git`)

---

## 2. Vulkan SDK

Descargá e instalá manualmente desde
https://vulkan.lunarg.com/sdk/home#windows (no hay forma simple de
scriptear la versión "latest"). Anotá la carpeta donde lo instalás
(por defecto algo como `C:\VulkanSDK\<version>\`).

```powershell
$env:VULKAN_SDK = "C:\VulkanSDK\<version_que_instalaste>"
```

---

## 3. Qt 6.9 con los módulos necesarios

```powershell
pip install aqtinstall
python -m aqt install-qt windows desktop 6.9.0 win64_msvc2022_64 `
    -m qtwebengine qtpositioning qtwebchannel qtwebsockets qtserialport `
    -O C:\Qt
```

Tarda bastante (Qt es grande). Al terminar vas a tener
`C:\Qt\6.9.0\msvc2022_64\`.

```powershell
$env:Qt6_DIR = "C:\Qt\6.9.0\msvc2022_64"
$env:PATH += ";C:\Qt\6.9.0\msvc2022_64\bin"
```

---

## 4. Dependencias de Python

```powershell
python -m pip install --upgrade pip setuptools wheel
python -m pip install --user --upgrade scons protobuf grpcio-tools pyinstaller meson
```

`meson` queda instalado en una carpeta de usuario que normalmente NO está
en el PATH. Buscala así y agregala:

```powershell
$userBase = python -m site --user-base
$env:PATH += ";$userBase\Scripts"
meson --version   # confirmar que ahora se reconoce
```

---

## 5. FFmpeg precompilado

Andá a https://github.com/streetpea/FFmpeg-Builds/releases y descargá el
build "win64-gpl-shared" más reciente. Extraelo y renombrá/movelo de forma
que quede como `C:\dev\chiaki-ng\deps\` (con subcarpetas `bin`, `lib`,
`include` adentro).

```powershell
mkdir C:\dev\chiaki-ng\deps -ErrorAction SilentlyContinue
```

---

## 6. sdl2-compat precompilado

Andá a https://github.com/libsdl-org/sdl2-compat/releases, descargá el
zip `win32-x64` de una release reciente, extraelo, y copiá todos los
`.dll` de ahí a `C:\dev\chiaki-ng\deps\bin`.

---

## 7. Compilar SPIRV-Cross

Desde el "x64 Native Tools Command Prompt" (ver regla de oro arriba):

```powershell
cd C:\dev
git clone https://github.com/KhronosGroup/SPIRV-Cross.git
cd SPIRV-Cross
cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="C:\dev\chiaki-ng\deps" -DSPIRV_CROSS_SHARED=ON -S . -B build -G Ninja
cmake --build build --config Release
cmake --install build
cd ..
```

---

## 8. Compilar shaderc

Los precompilados de Google (`storage.googleapis.com/shaderc/badges/...`)
están discontinuados — se compila desde fuente:

```powershell
cd C:\dev
git clone https://github.com/google/shaderc.git
cd shaderc
python utils/git-sync-deps
cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="C:\dev\chiaki-ng\deps" -DSHADERC_SKIP_TESTS=ON -DSHADERC_SKIP_EXAMPLES=ON -S . -B build -G Ninja
cmake --build build --config Release
cmake --install build
cd ..
```

`python utils/git-sync-deps` es obligatorio — shaderc no usa submódulos
de git normales, tiene su propio script para bajar glslang/SPIRV-Tools/
SPIRV-Headers.

---

## 9. vcpkg

```powershell
cd C:\dev
git clone https://github.com/microsoft/vcpkg.git
cd vcpkg
.\bootstrap-vcpkg.bat
cd C:\dev\chiaki-ng
```

```powershell
$env:VCPKG_INSTALLED_DIR = "C:\dev\chiaki-ng\build\vcpkg_installed"
C:\dev\vcpkg\vcpkg install --triplet x64-windows --x-install-root="$env:VCPKG_INSTALLED_DIR"
```

Esto tarda mucho — compila Qt/SDL/ffmpeg/etc vía vcpkg.

---

## 10. Compilar libplacebo (la parte más delicada)

**Tiene que ir clonado DENTRO de `chiaki-ng`**, no en `C:\dev` — el
comando de abajo usa una ruta relativa (`../meson.ini`) que asume que
`libplacebo` es subcarpeta de `chiaki-ng`.

```powershell
cd C:\dev\chiaki-ng
git clone --recursive https://github.com/haasn/libplacebo.git
cd libplacebo
git checkout --recurse-submodules v7.360.1

$env:CC = "clang-cl.exe"
$env:CXX = "clang-cl.exe"
$env:INCLUDE += ";$env:VULKAN_SDK\Include"
$env:LIB += ";$env:VULKAN_SDK\Lib"

meson setup `
    --prefix "C:\dev\chiaki-ng\deps" `
    --native-file ../meson.ini `
    "--pkg-config-path=['$env:VCPKG_INSTALLED_DIR\x64-windows\lib\pkgconfig','$env:VCPKG_INSTALLED_DIR\x64-windows\share\pkgconfig','C:\dev\chiaki-ng\deps\lib\pkgconfig']" `
    "--cmake-prefix-path=['$env:VCPKG_INSTALLED_DIR\x64-windows', '$env:VULKAN_SDK', 'C:\dev\chiaki-ng\deps']" `
    -Ddemos=false `
    ./build

ninja -C ./build
ninja -C ./build install
cd ..
```

Nota: usamos las variables de entorno `INCLUDE`/`LIB` para los headers y
libs de Vulkan en vez de pasarlos como argumentos de meson — pasarlos como
`-Dc_link_args` rompe el "sanity check" de meson con clang-cl (error
`no such file or directory: '/LIBPATH:...'`).

Si `meson setup` se queja de no encontrar `../meson.ini`, confirmá que
estás parado en `C:\dev\chiaki-ng\libplacebo` (no en otra ubicación).

---

## 11. Aplicar el patch de gf-complete

```powershell
git apply --ignore-whitespace --verbose --directory=third-party/gf-complete/ scripts/windows-vc/gf-complete.patch
```

---

## 12. Configurar con CMake

```powershell
$env:CC = "clang-cl.exe"
$env:CXX = "clang-cl.exe"

cmake -S . -B build -G Ninja `
    -DCMAKE_TOOLCHAIN_FILE:STRING="C:\dev\vcpkg\scripts\buildsystems\vcpkg.cmake" `
    -DCMAKE_BUILD_TYPE=Release `
    -DCHIAKI_ENABLE_CLI=OFF `
    -DCHIAKI_GUI_ENABLE_SDL_GAMECONTROLLER=ON `
    -DCHIAKI_ENABLE_STEAMDECK_NATIVE=OFF `
    -DCMAKE_PREFIX_PATH="C:\dev\chiaki-ng\deps;$env:VULKAN_SDK"
```

**Importante:** `clang-cl` (no `cl.exe` puro) es obligatorio — el código
de chiaki-ng usa comportamientos específicos de Clang. Con MSVC puro
falla con errores tipo "array de tamaño constante 0" en `session.c`/
`ctrl.c`.

Si `cmake` no encuentra `python`, agregá
`-DPYTHON_EXECUTABLE="<ruta a tu python.exe>"` (buscala con `where python`).

---

## 13. Compilar

```powershell
cmake --build build --config Release --target chiaki
```

La parte más larga de todas la primera vez.

---

## 14. Empaquetar como app portable

Ya tenemos un script que hace todo esto solo — ver `package-chiaki-ng.ps1`
en la raíz del repo:

```powershell
powershell -ExecutionPolicy Bypass -File .\package-chiaki-ng.ps1
```

Genera `chiaki-ng-dist\` con el `.exe` + todas las DLLs necesarias +
recursos de Qt, sin símbolos de debug. Movible a cualquier carpeta.

Si `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` está seteado, no
hace falta el `-ExecutionPolicy Bypass` cada vez.

---

## Notas generales

- Cada paso puede fallar por versiones/rutas que cambien con el tiempo
  (Vulkan SDK, Qt, versión de libplacebo, etc). Los errores más comunes ya
  los pisamos una vez durante el desarrollo — ver el historial de la
  conversación original si hace falta re-diagnosticar algo parecido.
- El **código fuente de la integración con la Ally X** (protocolo HID,
  hook en `SetTriggerEffects`, checkbox de Settings) ya está en este repo,
  commiteado — esta guía es solo sobre el ambiente/dependencias, no hay
  que volver a escribir C++.
- Para referencia de CÓMO funciona el protocolo HID y la integración en
  sí (no solo cómo compilarla), ver `protocolo-haptics-ally-x.md` y
  `plan-integracion-chiaki-ng.md` en este mismo repo (si los agregaste),
  o pedirle a Claude que retome desde ahí.
