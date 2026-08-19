# package-chiaki-ng.ps1
# Empaqueta chiaki-ng como una carpeta portable lista para usar.
# Corre esto parado en C:\dev\chiaki-ng, DESPUES de compilar
# (cmake --build build --config Release --target chiaki)

$ErrorActionPreference = "Continue"  # seguimos aunque falte algun DLL suelto

$outputDir = "chiaki-ng-dist"

# Asegurarnos que windeployqt este disponible, sin depender de que la
# terminal ya tenga el PATH de Qt seteado (nos paso varias veces con
# meson/clang-cl/etc, mejor resolverlo aca de una vez).
$qtBinDir = "C:\Qt\6.9.0\msvc2022_64\bin"
if(-not ($env:PATH -like "*$qtBinDir*")) {
    $env:PATH += ";$qtBinDir"
}

Write-Host "=== Empaquetando chiaki-ng ===" -ForegroundColor Cyan

# 1. Carpeta de salida limpia
if(Test-Path $outputDir) {
    Write-Host "Borrando carpeta anterior..."
    Remove-Item -Recurse -Force $outputDir
}
New-Item -ItemType Directory -Path $outputDir | Out-Null

# 2. Ejecutable principal
Write-Host "Copiando chiaki.exe..."
Copy-Item "build\gui\chiaki.exe" $outputDir -Force

# 3. cpp-steam-tools.dll (si existe en esta version del build)
if(Test-Path "build\third-party\cpp-steam-tools\cpp-steam-tools.dll") {
    Copy-Item "build\third-party\cpp-steam-tools\cpp-steam-tools.dll" $outputDir -Force
}

# 4. Todos los DLL de vcpkg y de deps (mas simple y robusto que listar uno
#    por uno -- ya nos comimos mas de un dolor de cabeza con nombres que
#    cambian entre versiones, tipo lcms2 vs lcms2-2)
Write-Host "Copiando DLLs de vcpkg..."
Copy-Item "build\vcpkg_installed\x64-windows\bin\*.dll" $outputDir -Force -ErrorAction SilentlyContinue

Write-Host "Copiando DLLs de deps..."
Copy-Item "deps\bin\*.dll" $outputDir -Force -ErrorAction SilentlyContinue

# 5. QML extra que necesita windeployqt para resolver imports
$qmlDir = "$outputDir\qml"
New-Item -ItemType Directory -Path $qmlDir -Force | Out-Null
if(Test-Path "scripts\qtwebengine_import.qml") {
    Copy-Item "scripts\qtwebengine_import.qml" "gui\src\qml\" -Force -ErrorAction SilentlyContinue
}

# 6. windeployqt: resuelve todas las dependencias de Qt automaticamente
Write-Host "Corriendo windeployqt..."
windeployqt.exe --no-translations --qmldir gui\src\qml --release "$outputDir\chiaki.exe"

Write-Host ""
Write-Host "Limpiando simbolos de debug (.pdb), no hacen falta para correr..."
Get-ChildItem $outputDir -Filter "*.pdb" -Recurse | Remove-Item -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=== Listo ===" -ForegroundColor Green
Write-Host "Paquete generado en: $outputDir"
Write-Host "Podes mover esa carpeta entera a donde quieras (ej: C:\Apps\chiaki-ng-ally-x)"