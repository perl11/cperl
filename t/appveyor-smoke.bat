rem @echo off

if not "%PLATFORM%" == "x64" set WIN64=undef
if "%MSVC_VERSION%" == "10" goto msvc_10
if "%MSVC_VERSION%" == "12" goto msvc_12
if "%MSVC_VERSION%" == "14" goto msvc_14

:msvc_10

call "C:\Program Files\Microsoft SDKs\Windows\v7.1\Bin\SetEnv.cmd" /%PLATFORM%
if "%PLATFORM%" == "x64" ( set "PATH=C:\windows\system32;c:\Program Files (x86)\Microsoft Visual Studio 10.0\VC\Bin\amd64;C:\Program Files\Microsoft SDKs\Windows\v7.1\Bin\x64;C:\Program Files\Microsoft SDKs\Windows\v7.1\Bin;C:\windows;C:\Program Files\Git\cmd;C:\Program Files\Git\usr\bin;C:\Program Files\7-Zip;" ) ELSE ( set "PATH=C:\windows\system32;c:\Program Files (x86)\Microsoft Visual Studio 10.0\VC\Bin;C:\Program Files (x86)\Microsoft Visual Studio 10.0\Common7\IDE;C:\Program Files\Microsoft SDKs\Windows\v7.1\Bin;C:\windows;C:\Program Files\Git\cmd;C:\Program Files\Git\usr\bin;C:\Windows\System32\WindowsPowerShell\v1.0\;C:\Program Files\7-Zip;" )

cd win32
rem if "%PLATFORM%" == "x64" exit /b
rem if "%PLATFORM%" == "x86" set PERL_ENCODE_DEBUG=1
nmake test CCTYPE=MSVC100 USE_NO_REGISTRY=define || exit 1

exit /b

:msvc_12
if "%PLATFORM%" == "x64" set PLATFORM=amd64
call "C:\Program Files (x86)\Microsoft Visual Studio %MSVC_VERSION%.0\VC\vcvarsall.bat" %PLATFORM%
rem Env var PLATFORM changes, the X is really capitalized.
rem Trim PATH to the minimum to build cperl less IO and CPU by not searching
rem many dozens of dirs when loading DLLs and starting processes.
if "%PLATFORM%" == "X64" ( set "PATH=C:\windows\system32;C:\Program Files (x86)\Microsoft Visual Studio 12.0\VC\BIN\amd64;C:\Program Files (x86)\Windows Kits\8.1\bin\x64;C:\Program Files (x86)\Windows Kits\8.1\bin\x86;C:\windows;C:\Program Files\Git\cmd;C:\Program Files\Git\usr\bin;C:\Program Files\7-Zip;" ) ELSE ( set "PATH=C:\windows\system32;C:\Program Files (x86)\Microsoft Visual Studio 12.0\VC\BIN;C:\Program Files (x86)\Windows Kits\8.1\bin\x86;C:\windows;C:\Program Files\Git\cmd;C:\Program Files\Git\usr\bin;C:\Windows\System32\WindowsPowerShell\v1.0\;C:\Program Files\7-Zip;" )

cd win32
rem if "%PLATFORM%" == "X64" exit /b
rem if "%PLATFORM%" == "x86" set PERL_ENCODE_DEBUG=1
nmake test CCTYPE=MSVC120 USE_NO_REGISTRY=define || exit 1

rem install on master/relprep/tag
if "%APPVEYOR_REPO_TAG%" == "true" goto tag
echo branch %APPVEYOR_REPO_BRANCH%
if "%APPVEYOR_REPO_BRANCH%" == "master" goto nightly
if "%APPVEYOR_REPO_BRANCH%" == "smoke/relprep" goto nightly
if "%APPVEYOR_REPO_BRANCH%" == "cperl-tag-deploy-test" goto nightly
exit /b

:nightly
nmake install CCTYPE=MSVC120 USE_NO_REGISTRY=undef
cd ..
set BITS=64
if %PLATFORM% == x86 set BITS=32
7z a -y -sfx cperl-%APPVEYOR_BUILD_VERSION%-win%BITS%.exe c:\cperl\
del /s /f /q C:\cperl
exit /b

:tag
nmake install CCTYPE=MSVC120 USE_NO_REGISTRY=undef
cd ..
set BITS=64
if %PLATFORM% == x86 set BITS=32
7z a -y -sfx %APPVEYOR_REPO_TAG_NAME%-win%BITS%.exe c:\cperl\
del /s /f /q C:\cperl

exit /b

:msvc_14
if "%PLATFORM%" == "x64" set PLATFORM=amd64
call "C:\Program Files (x86)\Microsoft Visual Studio %MSVC_VERSION%.0\VC\vcvarsall.bat" %PLATFORM%
if "%PLATFORM%" == "X64" ( set "PATH=C:\windows\system32;C:\Program Files (x86)\Microsoft Visual Studio 14.0\VC\BIN\amd64;C:\Program Files (x86)\Windows Kits\8.1\bin\x64;C:\Program Files (x86)\Windows Kits\8.1\bin\x86;C:\windows;C:\Program Files\Git\cmd;C:\Program Files\Git\usr\bin;C:\Program Files\7-Zip;" ) ELSE ( set "PATH=C:\windows\system32;C:\Program Files (x86)\Microsoft Visual Studio 14.0\VC\BIN;C:\Program Files (x86)\Windows Kits\8.1\bin\x86;C:\windows;C:\Program Files\Git\cmd;C:\Program Files\Git\usr\bin;C:\Windows\System32\WindowsPowerShell\v1.0\;C:\Program Files\7-Zip;" )

cd win32
nmake test CCTYPE=MSVC140 USE_NO_REGISTRY=define || exit 1
exit /b
