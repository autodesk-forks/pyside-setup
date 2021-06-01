@echo off

if not exist README.pyside2.md (
    echo PySide2 packaging script not running from pyside-setup directory.
    echo ABORTING: Current directory incorrect.
    exit 1
)

REM Parameter 1 - Absolute path to workspace directory
if [%1]==[] (
    echo Need to pass workspace directory to the script
    exit /b 1
)

REM Environment Variable - QTVERSION - Version of Qt used to build PySide2
if not defined QTVERSION (
	echo QTVERSION is undefined.  Example: SET QTVERSION=5.15.2
	exit /b 1
) else (
	echo QTVERSION=%QTVERSION%
)

REM Environment Variable - PYSIDEVERSION - Version of PySide2 built
if not defined PYSIDEVERSION (
	echo PYSIDEVERSION is undefined.  Example: SET PYSIDEVERSION=5.15.2
	exit /b 1
) else (
	echo PYSIDEVERSION=%PYSIDEVERSION%
)

REM Determine if it is a Python 2 or Python 3 build
set PY_MAJORVER=2
if exist "pyside3_install" (
    set PY_MAJORVER=3
)


REM Location of the workspace directory (root)
set WORKSPACE_DIR=%1

REM Location of the source code directory within the workspace
set SOURCE_DIR=%WORKSPACE_DIR%\src

REM Location of the install directory within the workspace (where the builds will be located)
set INSTALL_DIR=%WORKSPACE_DIR%\install


REM Store the current directory (required for a temporary fix to include the support submodule)
set STARTING_DIR=%CD%

REM Remove the previous build from the install directory
rmdir /s /q "%INSTALL_DIR%"
mkdir "%INSTALL_DIR%"


REM Write PySide2 build information to a "pyside2_version" file 
REM instead of encoding the pyside version number in a directory name
echo pyside2 %PYSIDEVERSION% > %INSTALL_DIR%\pyside2_version
echo qt %QTVERSION% >> %INSTALL_DIR%\pyside2_version
echo python major version %PY_MAJORVER% >> %INSTALL_DIR%\pyside2_version


if exist pyside%PY_MAJORVER%_install (
    REM Copy PySide2 release build into the install directory
    xcopy /e /i pyside%PY_MAJORVER%_install %INSTALL_DIR%\pyside%PY_MAJORVER%_install

    REM Workaround: Until the issue is addressed within PySide2 build scripts, we manually copy the 'support' PySide2 submodule
    REM into the build to prevent the "__feature__ could not be imported" error.
    cd %INSTALL_DIR%\pyside%PY_MAJORVER%_install\py*
    xcopy /e /i %SOURCE_DIR%\sources\pyside2\PySide2\support lib\site-packages\PySide2\support
    cd %STARTING_DIR%
)
if exist pyside%PY_MAJORVER%dp_install (
    REM Copy PySide2 debug build into the install directory
    xcopy /e /i pyside%PY_MAJORVER%dp_install %INSTALL_DIR%\pyside%PY_MAJORVER%dp_install

    REM Workaround: Until the issue is addressed within PySide2 build scripts, we manually copy the 'support' PySide2 submodule
    REM into the build to prevent the "__feature__ could not be imported" error.
    cd %INSTALL_DIR%\pyside%PY_MAJORVER%dp_install\py*
    xcopy /e /i %SOURCE_DIR%\sources\pyside2\PySide2\support lib\site-packages\PySide2\support
    cd %STARTING_DIR%
)

echo ==== Success ====
