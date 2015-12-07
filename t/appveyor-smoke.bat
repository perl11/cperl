@echo off

if "%MSVC_VERSION%" == "10" goto msvc_10
if "%MSVC_VERSION%" == "12" goto msvc_12

:msvc_12
if "%PLATFORM%" == "x64" set PLATFORM=amd64
call "C:\Program Files (x86)\Microsoft Visual Studio %MSVC_VERSION%.0\VC\vcvarsall.bat" %PLATFORM%

cd win32
nmake test CCTYPE=MSVC120 TEST_JOBS=4 || exit /b
exit /b

:msvc_10
call "C:\Program Files\Microsoft SDKs\Windows\v7.1\Bin\SetEnv.cmd" /%PLATFORM%

cd win32
nmake test CCTYPE=MSVC100 TEST_JOBS=4 || exit /b
exit /b
