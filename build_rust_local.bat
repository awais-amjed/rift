@echo off
REM Script to build Rust library locally on Windows

echo Building Rust library for Windows...
echo.

cd rust

REM Build for the current platform (Windows x64)
echo Building for x86_64-pc-windows-msvc (release mode)...
cargo build --release --target x86_64-pc-windows-msvc

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ========================================
    echo Cargo build FAILED!
    echo ========================================
    echo.
    echo Please check the error messages above.
    exit /b 1
)

cd ..

echo.
echo Generating Flutter Rust Bridge bindings...
flutter_rust_bridge_codegen generate

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================
    echo Build completed successfully!
    echo ========================================
    echo.
    echo Binaries are located in:
    echo   rust\target\x86_64-pc-windows-msvc\release\
    echo.
    echo The Flutter build will now use these precompiled binaries
    echo instead of building from scratch each time.
    echo.
) else (
    echo.
    echo ========================================
    echo flutter_rust_bridge_codegen FAILED!
    echo ========================================
    echo.
    echo Please check the error messages above.
    exit /b 1
)

