@echo off

if not "%PLATFORM%" == "x64" set WIN64=undef
if "%MSVC_VERSION%" == "10" goto msvc_10
if "%MSVC_VERSION%" == "12" goto msvc_12

:msvc_12
if "%PLATFORM%" == "x64" set PLATFORM=amd64
call "C:\Program Files (x86)\Microsoft Visual Studio %MSVC_VERSION%.0\VC\vcvarsall.bat" %PLATFORM%
rem Env var PLATFORM changes, the X is really capitalized.
rem Trim PATH to the minimum to build cperl less IO and CPU by not searching
rem many dozens of dirs when loading DLLs and starting processes.
if "%PLATFORM%" == "X64" ( set "PATH=C:\windows\system32;C:\Program Files (x86)\Microsoft Visual Studio 12.0\VC\BIN\amd64;C:\Program Files (x86)\Windows Kits\8.1\bin\x64;C:\Program Files (x86)\Windows Kits\8.1\bin\x86;C:\windows;C:\Program Files\Git\cmd;C:\Program Files\Git\usr\bin" ) ELSE ( set "PATH=C:\windows\system32;C:\Program Files (x86)\Microsoft Visual Studio 12.0\VC\BIN;C:\Program Files (x86)\Windows Kits\8.1\bin\x86;C:\windows;C:\Program Files\Git\cmd;C:\Program Files\Git\usr\bin" )

cd win32
nmake test CCTYPE=MSVC120 USE_NO_REGISTRY=define TEST_JOBS=4 || exit /b
exit /b

:msvc_10
call "C:\Program Files\Microsoft SDKs\Windows\v7.1\Bin\SetEnv.cmd" /%PLATFORM%
if "%PLATFORM%" == "x64" ( set "PATH=C:\windows\system32;c:\Program Files (x86)\Microsoft Visual Studio 10.0\VC\Bin\amd64;C:\Program Files\Microsoft SDKs\Windows\v7.1\Bin\x64;C:\Program Files\Microsoft SDKs\Windows\v7.1\Bin;C:\windows;C:\Program Files\Git\cmd;C:\Program Files\Git\usr\bin" ) ELSE ( set "PATH=C:\windows\system32;c:\Program Files (x86)\Microsoft Visual Studio 10.0\VC\Bin;C:\Program Files (x86)\Microsoft Visual Studio 10.0\Common7\IDE;C:\Program Files\Microsoft SDKs\Windows\v7.1\Bin;C:\windows;C:\Program Files\Git\cmd;C:\Program Files\Git\usr\bin" )

cd win32
nmake test CCTYPE=MSVC100 USE_NO_REGISTRY=define TEST_JOBS=4 || exit /b
exit /b
