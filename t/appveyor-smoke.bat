@echo off

if "%MSVC_VERSION%" == "10" goto msvc_10
if "%MSVC_VERSION%" == "12" goto msvc_12

:msvc_12
call "C:\Program Files (x86)\Microsoft Visual Studio %MSVC_VERSION%.0\VC\vcvarsall.bat" amd64
cd win32
nmake CCTYPE=MSVC120 && nmake test TEST_JOBS=4 || exit /b
exit /b

:msvc_10
call "C:\Program Files\Microsoft SDKs\Windows\v7.1\Bin\SetEnv.cmd" /x64
cd win32
nmake CCTYPE=MSVC100 && nmake test TEST_JOBS=4 || exit /b
exit /b

