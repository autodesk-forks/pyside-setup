@echo off

set SCRIPTDIR=%~dp0.

REM Parameter 1 - Absolute path to workspace directory
if [%1]==[] (
    echo error: need to pass workspace directory to the script
    echo aborting.
    exit /b 1
)
REM Validate that the workspace directory exists
if not exist %1 (
    echo error: workspace directory does not exist. Please pass a valid directory to the script.
    echo aborting.
    exit /b 1
)

if not exist setup.py (
    echo error: this script needs to be executed from the source directory
    echo aborting.
    exit /b 1
)

REM Environment Variable - QTVERSION - Version of Qt used to build PySide6
if not defined QTVERSION (
    echo QTVERSION is NOT defined. Example: SET QTVERSION=6.2.3
    echo aborting.
    exit /b 1
) else (
    echo QTVERSION=%QTVERSION%
)

REM Environment Variable - PYTHONVERSION - Version of Python for which PySide6 is built
if not defined PYTHONVERSION (
    echo PYTHONVERSION is NOT defined. Example: SET PYTHONVERSION=3.9.7
    echo aborting.
    exit /b 1
)

REM Extract MAJOR(A), MINOR(B), and REVISION(C) from PYTHONVERSION
setlocal EnableDelayedExpansion
FOR /f "tokens=1,2,3 delims=." %%a IN ("%PYTHONVERSION%") DO set PYTHONVERSION_A=%%a& set PYTHONVERSION_B=%%b& set PYTHONVERSION_C=%%c

REM Define Python Version Shortcuts (AB and A.B)
set PYTHONVERSION_AB=%PYTHONVERSION_A%%PYTHONVERSION_B%

REM Validate that the Python version given is within the accepted values
set pymajorver_acceptable_values=3
if "!pymajorver_acceptable_values:%PYTHONVERSION_A%=!" == "!pymajorver_acceptable_values!" (
    echo Python major version should be '3'.  Example: SET PYTHONVERSION=3.9.7
    echo aborting.
    exit /b 1
) else (
    echo PYTHONVERSION=%PYTHONVERSION%
)


if not defined VSCMD_VER (
    REM Activate Visual Studio compiler for amd64 architecture (at default install location)
    call "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvarsall.bat" amd64
) else (
    echo vcvarsall.bat already called
)


REM Location of the workspace directory (root)
set WORKSPACE_DIR=%1

REM Location of external dependencies directory
set EXTERNAL_DEPENDENCIES_DIR=%WORKSPACE_DIR%\external_dependencies

REM Location of libclang directory (in external dependencies)
set LLVM_INSTALL_DIR=%EXTERNAL_DEPENDENCIES_DIR%\libclang

REM Location of Qt build directory (in external dependencies)
set QTPATH=%EXTERNAL_DEPENDENCIES_DIR%\qt_%QTVERSION%

REM Location of openssl directory (optional) - (in external dependencies)
set OPENSSLPATH=%EXTERNAL_DEPENDENCIES_DIR%\openssl\1.1.1g


REM Location of python 3 directory (in external dependencies)
set PYTHON_DIR=%EXTERNAL_DEPENDENCIES_DIR%\cpython\%PYTHONVERSION%

REM In Maya's python 3 module, the executables are located at the root of their respective build type folder (release or debug)
set PYTHON_EXE=%PYTHON_DIR%\RelWithDebInfo\python.exe
set PYTHON_D_EXE=%PYTHON_DIR%\Debug\python_d.exe
set PYTHONEXEPATH=%PYTHON_DIR%\RelWithDebInfo;%PYTHON_DIR%\RelWithDebInfo\DLLs
set WHEEL_EXE=%PYTHON_DIR%\RelWithDebInfo\Scripts\wheel.exe

REM Environment Variable - PYSIDEVERSION - Version of PySide6 built
if not defined PYSIDEVERSION (
    REM Determine PYSIDEVERSION from the codebase.
    setlocal EnableDelayedExpansion
    FOR /F %%i IN ('%PYTHONEXE% %SCRIPT_DIR%\fetch-qt-version.py') DO set PYSIDEVERSION=%%i
)
echo PYSIDEVERSION=%PYSIDEVERSION%


REM By default, the pyside6-uic and pyside6-rcc wrappers are installed in the Python directory during the install step.
REM Using the --prefix option, we specify a different location where to output the files, which makes it easier to copy
REM the wrappers in the /bin folder when packaging.
set PREFIX_DIR=%WORKSPACE_DIR%\build
set PREFIX_DIR_RELWITHDEBINFO=%PREFIX_DIR%\RelWithDebInfo
set PREFIX_DIR_DEBUG=%PREFIX_DIR%\Debug

if exist %PREFIX_DIR_RELWITHDEBINFO% (
    rmdir /s /q "%PREFIX_DIR_RELWITHDEBINFO%"
)
if exist %PREFIX_DIR_DEBUG% (
    rmdir /s /q "%PREFIX_DIR_DEBUG%"
)
mkdir "%PREFIX_DIR_RELWITHDEBINFO%"
mkdir "%PREFIX_DIR_DEBUG%"

REM Location where the built wheels will be outputted
REM To be able to use pyside6-uic.exe and pyside6-rcc.exe, we need the metadata from the .dist-info folders,
REM which can be obtained by unpacking the wheels.
set DIST_DIR=%WORKSPACE_DIR%\dist
set DIST_DIR_RELWITHDEBINFO=%DIST_DIR%\RelWithDebInfo
set DIST_DIR_DEBUG=%DIST_DIR%\Debug

if exist %DIST_DIR_RELWITHDEBINFO% (
    rmdir /s /q "%DIST_DIR_RELWITHDEBINFO%"
)
if exist %DIST_DIR_DEBUG% (
    rmdir /s /q "%DIST_DIR_DEBUG%"
)
mkdir "%DIST_DIR_RELWITHDEBINFO%"
mkdir "%DIST_DIR_DEBUG%"

REM Python 3.9.7 artifacts don't have any pymalloc suffix, but future python builds might. Leaving this in place.
set PYMALLOC_SUFFIX=

REM Add paths to libclang and python executables to the PATH environment variable
set PATH=%PYTHONEXEPATH%;%LLVM_INSTALL_DIR%\bin;%PATH%
REM Add path to <qtdir>/bin - though this should not be necessary given that we provide a path to the qtpaths tool to setup.py. See PYSIDE-1844.
set PATH=%QTPATH%\bin;%PATH%
echo PATH=%PATH%

REM Add Python lib dir to the LIB environment variable so linking to python39.lib library works
set ORIGLIB=%LIB%


REM Validate that the directories of the external dependencies exist
if not exist %LLVM_INSTALL_DIR% (
    echo error: LLVM_INSTALL_DIR %LLVM_INSTALL_DIR% does not exist.
    echo aborting.
    exit /b 1
)
if not exist %QTPATH% (
    echo error: Qt path %QTPATH% does not exist.
    echo aborting.
    exit /b 1
)
if not exist %OPENSSLPATH% (
    echo error: OPENSSLPATH %OPENSSLPATH% does not exist.
    echo aborting.
    exit /b 1
)


REM Create qt.conf file
echo [Paths] > %QTPATH%\bin\qt.conf
echo Prefix=.. >> %QTPATH%\bin\qt.conf


REM Build PySide6 release version
%PYTHON_EXE% -V

set LIB=%ORIGLIB%;%PYTHON_DIR%\RelWithDebInfo\libs
echo LIB=%LIB%

REM Ensure that pip and its required modules are installed for Python 3 (release version)
%PYTHON_EXE% -m ensurepip
%PYTHON_EXE% -m pip install pip
%PYTHON_EXE% -m pip install setuptools
%PYTHON_EXE% -m pip install wheel==0.34.1
%PYTHON_EXE% -m pip install packaging

REM Before setting up, make sure that `slots` keyword is properly defined
sed -i -e 's/\(PyType_Slot\ \*slots\)_/\1/' %PYTHON_DIR%/RelWithDebInfo/include/object.h

%PYTHON_EXE% setup.py install --relwithdebinfo --qtpaths=%QTPATH%\bin\qtpaths.exe --openssl=%OPENSSLPATH%\RelWithDebInfo\bin --ignore-git --parallel=%NUMBER_OF_PROCESSORS% --prefix=%PREFIX_DIR_RELWITHDEBINFO% || echo "**** Failed to build Pyside6 Release ****" && exit /b 1
%PYTHON_EXE% setup.py bdist_wheel --relwithdebinfo --qtpaths=%QTPATH%\bin\qtpaths.exe --openssl=%OPENSSLPATH%\RelWithDebInfo\bin --ignore-git --parallel=%NUMBER_OF_PROCESSORS% --dist-dir=%DIST_DIR_RELWITHDEBINFO% || echo "**** Failed to build Pyside6 bdist_wheel Release ****" && exit /b 1

REM Unpack the wheels
set WHEEL_SUFFIX=%PYSIDEVERSION%-%QTVERSION%-cp%PYTHONVERSION_AB%-cp%PYTHONVERSION_AB%%PYMALLOC_SUFFIX%-win_amd64

set PYSIDE6_WHEEL=PySide6-%WHEEL_SUFFIX%.whl
set SHIBOKEN6_WHEEL=shiboken6-%WHEEL_SUFFIX%.whl
set SHIBOKEN6_GEN_WHEEL=shiboken6_generator-%WHEEL_SUFFIX%.whl

%WHEEL_EXE% unpack %DIST_DIR_RELWITHDEBINFO%\%PYSIDE6_WHEEL% --dest=%DIST_DIR_RELWITHDEBINFO%\
%WHEEL_EXE% unpack %DIST_DIR_RELWITHDEBINFO%\%SHIBOKEN6_WHEEL% --dest=%DIST_DIR_RELWITHDEBINFO%\
%WHEEL_EXE% unpack %DIST_DIR_RELWITHDEBINFO%\%SHIBOKEN6_GEN_WHEEL% --dest=%DIST_DIR_RELWITHDEBINFO%\


REM Build PySide6 debug version
%PYTHON_D_EXE% -V

set LIB=%ORIGLIB%;%PYTHON_DIR%\Debug\libs

REM Ensure that pip and its required modules are installed for Python 3 (debug version)
%PYTHON_D_EXE% -m ensurepip
%PYTHON_D_EXE% -m pip install pip
%PYTHON_D_EXE% -m pip install setuptools
%PYTHON_D_EXE% -m pip install wheel==0.34.1
%PYTHON_D_EXE% -m pip install packaging

REM Note: the `slots` keyword is already properly defined in the debug version

%PYTHON_D_EXE% setup.py install --debug --qtpaths=%QTPATH%\bin\qtpaths.exe --openssl=%OPENSSLPATH%\Debug\bin --ignore-git --parallel=%NUMBER_OF_PROCESSORS% --prefix=%PREFIX_DIR_DEBUG% || echo "**** Failed to build Pyside2 Debug ****" && exit /b 1
%PYTHON_D_EXE% setup.py bdist_wheel --debug --qtpaths=%QTPATH%\bin\qtpaths.exe --openssl=%OPENSSLPATH%\Debug\bin --ignore-git --parallel=%NUMBER_OF_PROCESSORS% --dist-dir=%DIST_DIR_DEBUG% || echo "**** Failed to build Pyside2 Debug ****" && exit /b 1

REM Unpack the wheels
set WHEEL_SUFFIX=%PYSIDEVERSION%-%QTVERSION%-cp%PYTHONVERSION_AB%-cp%PYTHONVERSION_AB%d%PYMALLOC_SUFFIX%-win_amd64

set PYSIDE6_WHEEL=PySide6-%WHEEL_SUFFIX%.whl
set SHIBOKEN6_WHEEL=shiboken6-%WHEEL_SUFFIX%.whl
set SHIBOKEN6_GEN_WHEEL=shiboken6_generator-%WHEEL_SUFFIX%.whl

%WHEEL_EXE% unpack %DIST_DIR_DEBUG%\%PYSIDE6_WHEEL% --dest=%DIST_DIR_DEBUG%\
%WHEEL_EXE% unpack %DIST_DIR_DEBUG%\%SHIBOKEN6_WHEEL% --dest=%DIST_DIR_DEBUG%\
%WHEEL_EXE% unpack %DIST_DIR_DEBUG%\%SHIBOKEN6_GEN_WHEEL% --dest=%DIST_DIR_DEBUG%\

echo ==== Success ====
