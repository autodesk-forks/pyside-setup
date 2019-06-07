@echo off
REM Current Directory is assumed to be the base of the pyside-setup repository.

if not exist README.pyside2.md (
    echo PySide2 packaging script not running from pyside-setup directory.
    echo ABORTING: Current directory incorrect.
    exit 1
)

if [%1]==[] (
    echo Need to pass workspace directory to the script
    exit /b 1
)

REM TODO Break out the Qt version number from the prefix. We need the version # separate for a directory name (see below)
if not defined QTVERSION (
	echo QTVERSION is undefined.  Example: SET QTVERSION=5.12.4
	exit /b 1
) else (
	echo QTVERSION=%QTVERSION%
)

if not defined PYSIDEVERSION (
	echo PYSIDEVERSION is undefined.  Example: SET PYSIDEVERSION=5.12.4
	exit /b 1
) else (
	echo PYSIDEVERSION=%PYSIDEVERSION%
)

set WORKDIR=%1
set SRCDIR=%WORKDIR%\src
set INSTALLDIR=%WORKDIR%\install

rmdir /s /q "%INSTALLDIR%"
mkdir "%INSTALLDIR%"

REM Instead of encoding the pyside version number in a directory name
REM instead put it in a "pyside2_version" file.
echo pyside2 %PYSIDEVERSION% > %INSTALLDIR%\pyside2_version
echo qt %QTVERSION% >> %INSTALLDIR%\pyside2_version

if exist pyside2_install (
    xcopy /e /i pyside2_install %INSTALLDIR%\pyside2_install
)
if exist pyside2d_install (
    xcopy /e /i pyside2d_install %INSTALLDIR%\pyside2d_install
)
echo ==== Success ====
