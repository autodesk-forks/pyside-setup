@echo off

if not exist README.pyside6.md (
    echo PySide6 packaging script not running from pyside-setup directory.
    echo ABORTING: Current directory incorrect.
    exit 1
)

REM Parameter 1 - Absolute path to workspace directory
if [%1]==[] (
    echo Need to pass workspace directory to the script
    exit /b 1
)

REM Environment Variable - QTVERSION - Version of Qt used to build PySide6
if not defined QTVERSION (
    echo QTVERSION is undefined.  Example: SET QTVERSION=6.2.3
    exit /b 1
) else (
    echo QTVERSION=%QTVERSION%
)

REM Environment Variable - PYSIDEVERSION - Version of PySide6 built
if not defined PYSIDEVERSION (
    echo PYSIDEVERSION is undefined.  Example: SET PYSIDEVERSION=6.2.3
    exit /b 1
) else (
    echo PYSIDEVERSION=%PYSIDEVERSION%
)

REM Environment Variable - PYTHONVERSION - Version of Python for which PySide6 is built
if not defined PYTHONVERSION (
    echo "PYTHONVERSION is NOT defined. Example: SET PYTHONVERSION=3.9.7"
    echo "aborting."
    exit /b 1
)

REM Extract MAJOR(A), MINOR(B), and REVISION(C) from PYTHONVERSION
FOR /f "tokens=1,2,3 delims=." %%a IN ("%PYTHONVERSION%") DO set PYTHONVERSION_A=%%a& set PYTHONVERSION_B=%%b& set PYTHONVERSION_C=%%c

REM Define Python Version Shortcut (A.B)
set PYTHONVERSION_AdotB=%PYTHONVERSION_A%.%PYTHONVERSION_B%

REM Validate that the Python version given is within the accepted values
set pymajorver_acceptable_values=3
if "!pymajorver_acceptable_values:%PYTHONVERSION_A%=!" == "!pymajorver_acceptable_values!" (
    echo "Python major version should be '3'.  Example: SET PYTHONVERSION=3.9.7"
    echo "aborting."
    exit /b 1
) else (
    echo PYTHONVERSION=%PYTHONVERSION%
)

set PATH_TO_MAYAPY_REGEX="1s/.*/\#\!bin\/mayapy.exe/"

REM Location of the workspace directory (root)
set WORKSPACE_DIR=%1

REM Location of the source code directory within the workspace
set SOURCE_DIR=%WORKSPACE_DIR%\src

REM Location of the install directory within the workspace (where the builds will be located)
set INSTALL_DIR=%WORKSPACE_DIR%\install

REM Location of the pyside6-uic and pyside6-rcc wrappers (determined by the --prefix option in the build script)
set PREFIX_DIR=%WORKSPACE_DIR%\build

REM Location of the pyside6-uic and pyside6-rcc .dist-info metadata folders (determined by the --dist-dir option in the build script)
set DIST_DIR=%WORKSPACE_DIR%\dist
set DIST_DIR_R=%DIST_DIR%\RelWithDebInfo
set DIST_DIR_D=%DIST_DIR%\Debug

REM Remove the previous build from the install directory
if exist %INSTALL_DIR% (
    rmdir /s /q "%INSTALL_DIR%"
)
mkdir "%INSTALL_DIR%"


REM Write PySide6 build information to a "pyside6_version" file 
REM instead of encoding the pyside version number in a directory name
echo PySide6 %PYSIDEVERSION% > %INSTALL_DIR%\pyside6_version
echo Qt %QTVERSION% >> %INSTALL_DIR%\pyside6_version
echo Python version %PYTHONVERSION% >> %INSTALL_DIR%\pyside6_version


REM Location of the root of packaged PySide6 artifacts (RelWithDebInfo and Debug)
set BUILD_DIRNAME_R=qfp-py%PYTHONVERSION_AdotB%-qt%QTVERSION%-64bit-relwithdebinfo
set BUILD_DIRNAME_D=qfpdp-py%PYTHONVERSION_AdotB%-qt%QTVERSION%-64bit-debug
set ARTIFACT_ROOT_R=%INSTALL_DIR%\%BUILD_DIRNAME_R%
set ARTIFACT_ROOT_D=%INSTALL_DIR%\%BUILD_DIRNAME_D%

robocopy /mir /ns /nc /np %DIST_DIR_D% %ARTIFACT_ROOT_D%
REM robocopy retruns 1 on success, but jenkins takes 1 as a failure.
if %ERRORLEVEL% NEQ 1 exit /b 1

robocopy /mir /ns /nc /np %DIST_DIR_R% %ARTIFACT_ROOT_R%

REM robocopy retruns 1 on success, but jenkins takes 1 as a failure.
if %ERRORLEVEL% NEQ 1 exit /b 1

echo ==== Success ====
exit /b 0
