if [%1]==[] (
   echo "Need to pass workspace directory to the script"
   exit /b 1
)

if not defined QTVERSION (
	echo QTVERSION is NOT defined.  Example: SET QTVERSION=qt_5.12.2
	exit /b 1
)
else (
	echo QTVERSION=%QTVERSION%
)

call "C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\VC\Auxiliary\Build\vcvarsall.bat" amd64
@echo off

set WORKDIR=%1
set ARTIFACTORYDIR=%WORKDIR%\artifactory
set EXTERNALSDIR=%WORKDIR%\..\externals

set LLVM_INSTALL_DIR=%ARTIFACTORYDIR%\libclang

SET PATH=%LLVM_INSTALL_DIR%\bin;%EXTERNALSDIR%\jom_1_1_3;%PATH%;

rem Create qt.conf file
echo [Paths] > %ARTIFACTORYDIR%\%QTVERSION%\bin\qt.conf
echo Prefix=.. >> %ARTIFACTORYDIR%\%QTVERSION%\bin\qt.conf

rem Build release version
C:\Python27\python.exe setup.py build --relwithdebinfo --qmake=%ARTIFACTORYDIR%\%QTVERSION%\bin\qmake.exe --openssl=%ARTIFACTORYDIR%\openssl\1.0.2h\x64\bin --build-tests --ignore-git --parallel=%NUMBER_OF_PROCESSORS% || echo "**** Failed to build Pyside2 Release ****" && exit /b 1

rem Build debug version
rem C:\Python27\python.exe setup.py build --debug --qmake=%ARTIFACTORYDIR%\%QTVERSION%\bin\qmake.exe --openssl=%ARTIFACTORYDIR%\openssl\1.0.2h\x64\bin --ignore-git --parallel=%NUMBER_OF_PROCESSORS% || echo "**** Failed to build Pyside2 Debug ****" && exit /b 1

echo "==== Success ===="