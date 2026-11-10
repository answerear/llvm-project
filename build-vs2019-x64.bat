@echo off
if "%~1"=="__INNER__" goto :main
chcp 65001 >nul
cmd /c ""%~f0" __INNER__"
set "RET=%ERRORLEVEL%"
echo.
pause
exit /b %RET%

:main
setlocal EnableDelayedExpansion

pushd "%~dp0"

set "REPO_ROOT=%~dp0"
if "%REPO_ROOT:~-1%"=="\" set "REPO_ROOT=%REPO_ROOT:~0,-1%"

set "LLVM_SOURCE_DIR=%REPO_ROOT%\llvm"
set "BUILD_DIR=%REPO_ROOT%\build_vs2019_x64"
for %%I in ("%REPO_ROOT%\..\..\Tiny3D\dependencies\llvm") do set "TARGET_DIR=%%~fI"

set "TARGET_INC_DIR=%TARGET_DIR%\include\clang-c"
set "TARGET_WIN_X64_DIR=%TARGET_DIR%\prebuilt\Windows\x64"
set "TARGET_RESOURCE_INC_DIR=%TARGET_DIR%\prebuilt\clang-resource\include"
set "OMP_BACKUP_DIR=%BUILD_DIR%\omp_header_backup"

echo ============================================================================
echo   LLVM / libclang - Windows x64 (CMake + MSVC + Ninja) Build ^& Deploy
echo ============================================================================
echo.

if not exist "%LLVM_SOURCE_DIR%\CMakeLists.txt" (
    echo [ERROR] llvm\CMakeLists.txt not found at "%LLVM_SOURCE_DIR%"!
    goto :error
)

if not exist "%TARGET_DIR%" (
    echo [ERROR] Target dependencies directory does not exist: "%TARGET_DIR%"!
    goto :error
)

REM ============================================================================
REM [1/6] Clean Previous Build Artifacts
REM ============================================================================
echo [1/6] Cleaning previous build directory "%BUILD_DIR%"...
if exist "%BUILD_DIR%" (
    rmdir /S /Q "%BUILD_DIR%"
    if exist "%BUILD_DIR%" (
        echo [ERROR] Failed to clean "%BUILD_DIR%". Please close any open files/IDE and retry.
        goto :error
    )
    echo       Previous build artifacts cleaned.
) else (
    echo       No previous build directory found.
)

REM ============================================================================
REM [2/6] Locate Visual Studio (2019 preferred, 2022 fallback) and vcvars64.bat
REM ============================================================================
echo.
echo [2/6] Initializing Visual Studio x64 MSVC environment...

set "VS_DIR="
set "PF86=%ProgramFiles(x86)%"
set "VSWHERE=%PF86%\Microsoft Visual Studio\Installer\vswhere.exe"

if exist "%VSWHERE%" (
    for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -version "[16.0,17.0)" -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do (
        if not defined VS_DIR set "VS_DIR=%%i"
    )
    if not defined VS_DIR (
        for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -version "[17.0,18.0)" -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do (
            if not defined VS_DIR set "VS_DIR=%%i"
        )
    )
)

if not defined VS_DIR if exist "%PF86%\Microsoft Visual Studio\2019\Enterprise\VC\Auxiliary\Build\vcvars64.bat" set "VS_DIR=%PF86%\Microsoft Visual Studio\2019\Enterprise"
if not defined VS_DIR if exist "%PF86%\Microsoft Visual Studio\2019\Professional\VC\Auxiliary\Build\vcvars64.bat" set "VS_DIR=%PF86%\Microsoft Visual Studio\2019\Professional"
if not defined VS_DIR if exist "%PF86%\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvars64.bat" set "VS_DIR=%PF86%\Microsoft Visual Studio\2019\Community"
if not defined VS_DIR if exist "%PF86%\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvars64.bat" set "VS_DIR=%PF86%\Microsoft Visual Studio\2019\BuildTools"
if not defined VS_DIR if exist "%ProgramFiles%\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat" set "VS_DIR=%ProgramFiles%\Microsoft Visual Studio\2022\Professional"
if not defined VS_DIR if exist "%ProgramFiles%\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" set "VS_DIR=%ProgramFiles%\Microsoft Visual Studio\2022\Community"

if not defined VS_DIR (
    echo [ERROR] Visual Studio 2019/2022 with C++ x64 toolset was not found!
    goto :error
)

set "VCVARS64=%VS_DIR%\VC\Auxiliary\Build\vcvars64.bat"
if not exist "%VCVARS64%" (
    echo [ERROR] vcvars64.bat not found at "%VCVARS64%"!
    goto :error
)

echo       Visual Studio : "%VS_DIR%"
set "PreferredToolArchitecture=x64"
call "%VCVARS64%"
if errorlevel 1 (
    echo [ERROR] Failed to initialize MSVC x64 environment via vcvars64.bat!
    goto :error
)

REM ============================================================================
REM [3/6] Check Required Tools (CMake, Ninja, Python 3, cl.exe)
REM ============================================================================
echo.
echo [3/6] Checking required build tools [cl / cmake / ninja / python]...

if exist "%VS_DIR%\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe" (
    set "PATH=%VS_DIR%\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja;%PATH%"
)
if exist "%VS_DIR%\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" (
    set "PATH=%PATH%;%VS_DIR%\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin"
)

where cl.exe >nul 2>nul
if errorlevel 1 (
    echo [ERROR] MSVC compiler cl.exe not found in PATH!
    goto :error
)

where cmake.exe >nul 2>nul
if errorlevel 1 (
    echo [ERROR] cmake.exe not found in PATH!
    goto :error
)

where ninja.exe >nul 2>nul
if errorlevel 1 (
    echo [ERROR] ninja.exe not found in PATH! Please install Ninja or Visual Studio CMake tools.
    goto :error
)

where python.exe >nul 2>nul
if errorlevel 1 (
    echo [ERROR] python.exe not found in PATH! Python 3.x is required to build LLVM.
    goto :error
)

python.exe -c "import sys; sys.exit(0 if sys.version_info[0] >= 3 else 1)" >nul 2>nul
if errorlevel 1 (
    echo [ERROR] python.exe in PATH is not a valid Python 3.x installation!
    goto :error
)

for /f "tokens=*" %%i in ('where cl.exe') do (echo       MSVC  : %%i & goto :cl_ok)
:cl_ok
for /f "tokens=*" %%i in ('where cmake.exe') do (echo       CMake : %%i & goto :cmake_ok)
:cmake_ok
for /f "tokens=*" %%i in ('where ninja.exe') do (echo       Ninja : %%i & goto :ninja_ok)
:ninja_ok
for /f "tokens=*" %%i in ('where python.exe') do (echo       Python: %%i & goto :py_ok)
:py_ok

REM ============================================================================
REM [4/6] Configure LLVM + Clang with CMake + Ninja + MSVC (x64 Release)
REM ============================================================================
echo.
echo [4/6] Configuring LLVM with CMake (Generator: Ninja, Arch: x64, Config: Release)...

cmake -S "%LLVM_SOURCE_DIR%" -B "%BUILD_DIR%" ^
    -G "Ninja" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_C_COMPILER=cl.exe ^
    -DCMAKE_CXX_COMPILER=cl.exe ^
    -DCMAKE_RC_COMPILER=rc.exe ^
    -DCMAKE_MT=mt.exe ^
    -DLLVM_ENABLE_PROJECTS="clang" ^
    -DLLVM_TARGETS_TO_BUILD="all" ^
    -DBUILD_SHARED_LIBS=OFF ^
    -DLLVM_ENABLE_ZLIB=OFF ^
    -DLLVM_ENABLE_ZSTD=OFF ^
    -DLLVM_ENABLE_LIBXML2=OFF ^
    -DLLVM_ENABLE_TERMINFO=OFF ^
    -DLLVM_ENABLE_LIBEDIT=OFF ^
    -DLLVM_INCLUDE_TESTS=OFF ^
    -DLLVM_INCLUDE_EXAMPLES=OFF ^
    -DLLVM_INCLUDE_BENCHMARKS=OFF ^
    -DLLVM_INCLUDE_DOCS=OFF ^
    -DCLANG_INCLUDE_TESTS=OFF ^
    -DCLANG_INCLUDE_DOCS=OFF ^
    -DCLANG_BUILD_EXAMPLES=OFF
if errorlevel 1 (
    echo [ERROR] CMake configuration failed!
    goto :error
)

REM ============================================================================
REM [5/6] Build LLVM/Clang Static Libraries, libclang & clang-resource-headers
REM ============================================================================
echo.
echo [5/6] Building LLVM/Clang static libraries, libclang and resource headers via Ninja...

cmake --build "%BUILD_DIR%" --target libclang clang-resource-headers
if errorlevel 1 (
    echo [ERROR] Ninja build failed!
    goto :error
)

set "BUILT_LIB=%BUILD_DIR%\lib\libclang.lib"
set "BUILT_DLL=%BUILD_DIR%\bin\libclang.dll"

if not exist "%BUILT_LIB%" (
    echo [ERROR] Expected library not found: "%BUILT_LIB%"
    goto :error
)
if not exist "%BUILT_DLL%" (
    echo [ERROR] Expected binary not found: "%BUILT_DLL%"
    goto :error
)

set "BUILT_RESOURCE_INC_DIR="
for /d %%D in ("%BUILD_DIR%\lib\clang\*") do (
    if exist "%%~fD\include\stddef.h" set "BUILT_RESOURCE_INC_DIR=%%~fD\include"
)
if not defined BUILT_RESOURCE_INC_DIR (
    echo [ERROR] Built clang-resource include directory not found under "%BUILD_DIR%\lib\clang\*"!
    goto :error
)

REM ============================================================================
REM [6/6] Clean Target Directories and Copy Artifacts to Tiny3D\dependencies\llvm
REM ============================================================================
echo.
echo [6/6] Cleaning target directories and copying artifacts to "%TARGET_DIR%"...

REM Backup existing OpenMP headers (omp.h / ompt.h / omp-tools.h) if present in clang-resource
if exist "%OMP_BACKUP_DIR%" rmdir /S /Q "%OMP_BACKUP_DIR%"
mkdir "%OMP_BACKUP_DIR%"
if exist "%TARGET_RESOURCE_INC_DIR%\omp*.h" (
    xcopy /Y /Q "%TARGET_RESOURCE_INC_DIR%\omp*.h" "%OMP_BACKUP_DIR%\" >nul
)

REM Clean target include/clang-c, prebuilt/clang-resource/include, and prebuilt/Windows/x64
REM (Note: prebuilt/OSX is intentionally preserved for macOS builds)
if exist "%TARGET_INC_DIR%" (
    echo       Cleaning: "%TARGET_INC_DIR%"
    rmdir /S /Q "%TARGET_INC_DIR%"
    if exist "%TARGET_INC_DIR%" (
        echo [ERROR] Failed to clean "%TARGET_INC_DIR%"!
        goto :error
    )
)

if exist "%TARGET_RESOURCE_INC_DIR%" (
    echo       Cleaning: "%TARGET_RESOURCE_INC_DIR%"
    rmdir /S /Q "%TARGET_RESOURCE_INC_DIR%"
    if exist "%TARGET_RESOURCE_INC_DIR%" (
        echo [ERROR] Failed to clean "%TARGET_RESOURCE_INC_DIR%"!
        goto :error
    )
)

if exist "%TARGET_WIN_X64_DIR%" (
    echo       Cleaning: "%TARGET_WIN_X64_DIR%"
    rmdir /S /Q "%TARGET_WIN_X64_DIR%"
    if exist "%TARGET_WIN_X64_DIR%" (
        echo [ERROR] Failed to clean "%TARGET_WIN_X64_DIR%"!
        goto :error
    )
)

mkdir "%TARGET_INC_DIR%"
mkdir "%TARGET_RESOURCE_INC_DIR%"
mkdir "%TARGET_WIN_X64_DIR%"

REM 1. Copy clang-c headers -> dependencies/llvm/include/clang-c
echo       Copying clang-c headers to "%TARGET_INC_DIR%"...
xcopy /E /I /Y /Q "%REPO_ROOT%\clang\include\clang-c\*.h" "%TARGET_INC_DIR%\" >nul
if errorlevel 1 (
    echo [ERROR] Failed to copy clang-c headers!
    goto :error
)

REM 2. Copy clang-resource headers -> dependencies/llvm/prebuilt/clang-resource/include
echo       Copying clang-resource headers to "%TARGET_RESOURCE_INC_DIR%"...
xcopy /E /I /Y /Q "%BUILT_RESOURCE_INC_DIR%\*" "%TARGET_RESOURCE_INC_DIR%\" >nul
if errorlevel 1 (
    echo [ERROR] Failed to copy built clang-resource headers!
    goto :error
)

REM Copy compiler-rt resource headers (sanitizer, fuzzer, xray, orc, profile) to match structure
if exist "%REPO_ROOT%\compiler-rt\include\sanitizer" (
    mkdir "%TARGET_RESOURCE_INC_DIR%\sanitizer" 2>nul
    xcopy /Y /Q "%REPO_ROOT%\compiler-rt\include\sanitizer\*.h" "%TARGET_RESOURCE_INC_DIR%\sanitizer\" >nul
    if exist "%TARGET_RESOURCE_INC_DIR%\sanitizer\memprof_interface.h" (
        del /F /Q "%TARGET_RESOURCE_INC_DIR%\sanitizer\memprof_interface.h" >nul
    )
)
if exist "%REPO_ROOT%\compiler-rt\include\fuzzer" (
    mkdir "%TARGET_RESOURCE_INC_DIR%\fuzzer" 2>nul
    xcopy /Y /Q "%REPO_ROOT%\compiler-rt\include\fuzzer\*.h" "%TARGET_RESOURCE_INC_DIR%\fuzzer\" >nul
)
if exist "%REPO_ROOT%\compiler-rt\include\xray" (
    mkdir "%TARGET_RESOURCE_INC_DIR%\xray" 2>nul
    xcopy /Y /Q "%REPO_ROOT%\compiler-rt\include\xray\*.h" "%TARGET_RESOURCE_INC_DIR%\xray\" >nul
)
if exist "%REPO_ROOT%\compiler-rt\include\orc" (
    mkdir "%TARGET_RESOURCE_INC_DIR%\orc" 2>nul
    xcopy /Y /Q "%REPO_ROOT%\compiler-rt\include\orc\*.h" "%TARGET_RESOURCE_INC_DIR%\orc\" >nul
)
if exist "%REPO_ROOT%\compiler-rt\include\profile\InstrProfData.inc" (
    mkdir "%TARGET_RESOURCE_INC_DIR%\profile" 2>nul
    copy /Y "%REPO_ROOT%\compiler-rt\include\profile\InstrProfData.inc" "%TARGET_RESOURCE_INC_DIR%\profile\InstrProfData.inc" >nul
)

REM Restore preserved OpenMP headers (omp.h, ompt.h, omp-tools.h)
if exist "%OMP_BACKUP_DIR%\omp*.h" (
    xcopy /Y /Q "%OMP_BACKUP_DIR%\omp*.h" "%TARGET_RESOURCE_INC_DIR%\" >nul
)
rmdir /S /Q "%OMP_BACKUP_DIR%" 2>nul

REM 3. Copy Windows x64 libraries -> dependencies/llvm/prebuilt/Windows/x64
echo       Copying Windows x64 binaries/libraries to "%TARGET_WIN_X64_DIR%"...
copy /Y "%BUILT_LIB%" "%TARGET_WIN_X64_DIR%\libclang.lib" >nul
if errorlevel 1 (
    echo [ERROR] Failed to copy libclang.lib!
    goto :error
)

copy /Y "%BUILT_DLL%" "%TARGET_WIN_X64_DIR%\libclang.dll" >nul
if errorlevel 1 (
    echo [ERROR] Failed to copy libclang.dll!
    goto :error
)

echo.
echo ============================================================================
echo [SUCCESS] LLVM Windows x64 Release build and deployment completed!
echo   Static Libs (Build) : %BUILD_DIR%\lib\*.lib
echo   Target Headers      : %TARGET_INC_DIR%
echo   Target Resource Dir : %TARGET_RESOURCE_INC_DIR%
echo   Target Windows x64  : %TARGET_WIN_X64_DIR%\libclang.lib, libclang.dll
echo ============================================================================
popd
endlocal
exit /b 0

:error
echo.
echo ============================================================================
echo [FAILED] Build or deployment aborted due to errors above!
echo ============================================================================
popd
endlocal
exit /b 1
