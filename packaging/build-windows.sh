#!/bin/sh
# Export the Windows build and zip it with the French readme:
# build/magneto-windows.zip (exe + capture DLL + LISEZMOI.txt).
set -e
cd "$(dirname "$(readlink -f "$0")")/.."
rm -rf build/windows && mkdir -p build/windows
godot --headless --path . --export-release "Windows Desktop" build/windows/magneto.exe
cp packaging/LISEZMOI.txt build/windows/
rm -f build/magneto-windows.zip
(cd build/windows && zip -q -9 ../magneto-windows.zip magneto.exe libwincap.windows.template_release.x86_64.dll LISEZMOI.txt)
ls -la build/magneto-windows.zip
