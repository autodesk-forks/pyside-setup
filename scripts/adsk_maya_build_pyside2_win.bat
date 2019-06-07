@echo off
if [%1]==[] (
   echo "Need to pass workspace directory to the script"
   exit /b 1
)

if not defined QTVERSION (
	echo QTVERSION is NOT defined.  Example: SET QTVERSION=qt_5.12.4
	exit /b 1
) else (
	echo QTVERSION=%QTVERSION%
)

call "C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\VC\Auxiliary\Build\vcvarsall.bat" amd64

set WORKDIR=%1
set ARTIFACTORYDIR=%WORKDIR%\artifactory
set EXTERNALSDIR=%WORKDIR%\..\externals

set LLVM_INSTALL_DIR=%ARTIFACTORYDIR%\libclang
SET PATH=%LLVM_INSTALL_DIR%\bin;%EXTERNALSDIR%\jom_1_1_3;%PATH%;
SET PATH=C:\Python27;%PATH%
set QTPATH=%ARTIFACTORYDIR%\qt_%QTVERSION%
set OPENSSLPATH=%ARTIFACTORYDIR%\openssl\1.0.2h\x64

REM FOR DEV MACHINE: set LLVM_INSTALL_DIR=%ARTIFACTORYDIR%\libclang\842d9245\libclang
REM FOR DEV MACHINE: set PATH=%PATH%;%USERPROFILE%\Build\jom-build\build-qmake-vs2017\bin;
REM FOR DEV MACHINE: set QTPATH=%ARTIFACTORYDIR%\qt\458437a9\qt_%QTVERSION%
REM FOR DEV MACHINE: set OPENSSLPATH=C:\OpenSSL-Win64

rem Create qt.conf file
echo [Paths] > %QTPATH%\bin\qt.conf
echo Prefix=.. >> %QTPATH%\bin\qt.conf

rem Build release version
python.exe setup.py build --relwithdebinfo --qmake=%QTPATH%\bin\qmake.exe --openssl=%OPENSSLPATH%\bin --build-tests --ignore-git --parallel=%NUMBER_OF_PROCESSORS% || echo "**** Failed to build Pyside2 Release ****" && exit /b 1

REM TODO: Must have debug version of Python, built with the same MSVC in order to build debug pyside.
rem Build debug version
rem python.exe setup.py build --debug --qmake=%QTPATH%\bin\qmake.exe --openssl=%OPENSSLPATH%\bin --ignore-git --parallel=%NUMBER_OF_PROCESSORS% || echo "**** Failed to build Pyside2 Debug ****" && exit /b 1

echo "==== Success ===="
