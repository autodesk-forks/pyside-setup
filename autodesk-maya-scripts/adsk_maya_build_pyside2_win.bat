@echo off
REM Parameter 1 - Absolute path to workspace directory
if [%1]==[] (
    echo "error: need to pass workspace directory to the script"
    echo "aborting."
    exit /b 1
)
REM Validate that the workspace directory exists
if not exist %1 (
    echo "error: workspace directory does not exist. Please pass a valid directory to the script."
    echo "aborting."
    exit /b 1
)

REM Environment Variable - QTVERSION - Version of Qt used to build PySide2
if not defined QTVERSION (
    echo "QTVERSION is NOT defined. Example: SET QTVERSION=5.15.2"
    echo "aborting."
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

REM Environment Variable - PYTHONMAJORVERSION - Version of Python for which PySide2 is built
if not defined PYTHONMAJORVERSION (
    echo "PYTHONMAJORVERSION is NOT defined. Example: SET PYTHONMAJORVERSION=3"
    echo "aborting."
    exit /b 1
)

REM Validate that the Python version given is within the accepted values
setlocal EnableDelayedExpansion
set pymajorver_acceptable_values=2,3
if "!pymajorver_acceptable_values:%PYTHONMAJORVERSION%=!" == "!pymajorver_acceptable_values!" (
    echo "PYTHONMAJORVERSION should be '2' or '3'.  Example: SET PYTHONMAJORVERSION=3"
    echo "aborting."
    exit /b 1
) else (
    echo PYTHONMAJORVERSION=%PYTHONMAJORVERSION%
)


REM Activate Visual Studio compiler for amd64 architecture (at default install location) 
call "C:\Program Files (x86)\Microsoft Visual Studio\2019\Professional\VC\Auxiliary\Build\vcvarsall.bat" amd64


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

REM Location of Jom (optional) - Jom is automatically used to build if it is present in the PATH environment variable
set JOM_DIR=%EXTERNAL_DEPENDENCIES_DIR%\


REM By default, the pyside2-uic and pyside2-rcc wrappers are installed in the Python directory during the install step.
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
REM To be able to use pyside2-uic.exe and pyside2-rcc.exe, we need the metadata from the .dist-info folders, 
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


REM Location of python 2 directory (in external dependencies)
set PYTHON_DIR=%EXTERNAL_DEPENDENCIES_DIR%\python-2.7.11-Maya-2020+-win

REM In Maya's Python 2 module, the executables are located in libs/
set PYTHON_EXE=python.exe
set PYTHON_D_EXE=python_d.exe
set PYTHONEXEPATH=%PYTHON_DIR%\libs;%PYTHON_DIR%\Scripts
set WHEEL_EXE=%PYTHON_DIR%\libs\python.exe -m wheel

if not "%PYTHONMAJORVERSION%" == "3" goto PYTHON3_HANDLING_DONE
    REM Location of python 3 directory (in external dependencies)
    set PYTHON_DIR=%EXTERNAL_DEPENDENCIES_DIR%\cpython\3.7.7

    REM In Maya's python 3 module, the executables are located at the root of their respective build type folder (release or debug)
    set PYTHON_EXE=%PYTHON_DIR%\RelWithDebInfo\python.exe
    set PYTHON_D_EXE=%PYTHON_DIR%\Debug\python_d.exe
    set PYTHONEXEPATH=%PYTHON_DIR%\RelWithDebInfo;%PYTHON_DIR%\RelWithDebInfo\DLLs
    set WHEEL_EXE=%PYTHON_DIR%\RelWithDebInfo\Scripts\wheel.exe
:PYTHON3_HANDLING_DONE


REM Add paths to libclang, jom and python executables to the PATH environment variable
set PATH=%PYTHONEXEPATH%;%LLVM_INSTALL_DIR%\bin;%JOM_DIR%;%PATH%;
echo PATH=%PATH%


REM Validate that the directories of the external dependencies exist
if not exist %LLVM_INSTALL_DIR% (
    echo error: LLVM_INSTALL_DIR %LLVM_INSTALL_DIR% does not exist.
    echo "aborting."
    exit /b 1
)
if not exist %QTPATH% (
    echo error: Qt path %QTPATH% does not exist.
    echo "aborting."
    exit /b 1
)
if not exist %OPENSSLPATH% (
    echo error: OPENSSLPATH %OPENSSLPATH% does not exist.
    echo "aborting."
    exit /b 1
)
if not exist %JOM_DIR% (
    echo error: JOM_DIR %JOM_DIR% does not exist.
    echo "aborting."
    exit /b 1
)


REM Create qt.conf file
echo [Paths] > %QTPATH%\bin\qt.conf
echo Prefix=.. >> %QTPATH%\bin\qt.conf


REM Build PySide2 release version
%PYTHON_EXE% -V

if not "%PYTHONMAJORVERSION%" == "2" goto PYTHON2_INSTALL_REL_DONE
    REM Ensure that pip and its required modules are installed for Python 2 (release version)
    %PYTHON_EXE% -m pip install packaging
:PYTHON2_INSTALL_REL_DONE

if not "%PYTHONMAJORVERSION%" == "3" goto PYTHON3_INSTALL_REL_DONE	
    REM Ensure that pip and its required modules are installed for Python 3 (release version)
    %PYTHON_EXE% -m ensurepip
    %PYTHON_EXE% -m pip install pip
    %PYTHON_EXE% -m pip install setuptools
    %PYTHON_EXE% -m pip install wheel==0.34.1
    %PYTHON_EXE% -m pip install packaging

    REM Before setting up, make sure that `slots` keyword is properly defined
    sed -i -e 's/\(PyType_Slot\ \*slots\)_/\1/' %PYTHON_DIR%/RelWithDebInfo/include/object.h
:PYTHON3_INSTALL_REL_DONE
%PYTHON_EXE% setup.py install --relwithdebinfo --qmake=%QTPATH%\bin\qmake.exe --openssl=%OPENSSLPATH%\RelWithDebInfo\bin --build-tests --ignore-git --parallel=%NUMBER_OF_PROCESSORS% --prefix=%PREFIX_DIR_RELWITHDEBINFO% || echo "**** Failed to build Pyside2 Release ****" && exit /b 1
%PYTHON_EXE% setup.py bdist_wheel --relwithdebinfo --qmake=%QTPATH%\bin\qmake.exe --openssl=%OPENSSLPATH%\RelWithDebInfo\bin --build-tests --ignore-git --parallel=%NUMBER_OF_PROCESSORS% --dist-dir=%DIST_DIR_RELWITHDEBINFO% || echo "**** Failed to build Pyside2 Release ****" && exit /b 1

REM Unpack the wheels
set PYSIDE2_WHEEL=PySide2-%QTVERSION%-%PYSIDEVERSION%-cp%PYTHONMAJORVERSION%7-cp%PYTHONMAJORVERSION%7m-win_amd64.whl
set SHIBOKEN2_WHEEL=shiboken2-%QTVERSION%-%PYSIDEVERSION%-cp%PYTHONMAJORVERSION%7-cp%PYTHONMAJORVERSION%7m-win_amd64.whl
set SHIBOKEN2_GEN_WHEEL=shiboken2_generator-%QTVERSION%-%PYSIDEVERSION%-cp%PYTHONMAJORVERSION%7-cp%PYTHONMAJORVERSION%7m-win_amd64.whl

%WHEEL_EXE% unpack %DIST_DIR_RELWITHDEBINFO%\%PYSIDE2_WHEEL% --dest=%DIST_DIR_RELWITHDEBINFO%\
%WHEEL_EXE% unpack %DIST_DIR_RELWITHDEBINFO%\%SHIBOKEN2_WHEEL% --dest=%DIST_DIR_RELWITHDEBINFO%\
%WHEEL_EXE% unpack %DIST_DIR_RELWITHDEBINFO%\%SHIBOKEN2_GEN_WHEEL% --dest=%DIST_DIR_RELWITHDEBINFO%\


REM Build PySide2 debug version
%PYTHON_D_EXE% -V

if not "%PYTHONMAJORVERSION%" == "2" goto PYTHON2_INSTALL_DEB_DONE
    REM Ensure that pip and its required modules are installed for Python 2 (debug version)
    %PYTHON_D_EXE% -m pip install packaging
:PYTHON2_INSTALL_DEB_DONE

if not "%PYTHONMAJORVERSION%" == "3" goto PYTHON3_INSTALL_DEB_DONE
    REM Ensure that pip and its required modules are installed for Python 3 (debug version)
    %PYTHON_D_EXE% -m ensurepip
    %PYTHON_D_EXE% -m pip install pip
    %PYTHON_D_EXE% -m pip install setuptools
    %PYTHON_D_EXE% -m pip install wheel==0.34.1
    %PYTHON_D_EXE% -m pip install packaging

    REM Note: the `slots` keyword is already properly defined in the debug version
:PYTHON3_INSTALL_DEB_DONE
%PYTHON_D_EXE% setup.py install --debug --qmake=%QTPATH%\bin\qmake.exe --openssl=%OPENSSLPATH%\Debug\bin --ignore-git --parallel=%NUMBER_OF_PROCESSORS% --prefix=%PREFIX_DIR_DEBUG% || echo "**** Failed to build Pyside2 Debug ****" && exit /b 1
%PYTHON_D_EXE% setup.py bdist_wheel --debug --qmake=%QTPATH%\bin\qmake.exe --openssl=%OPENSSLPATH%\Debug\bin --ignore-git --parallel=%NUMBER_OF_PROCESSORS% --dist-dir=%DIST_DIR_DEBUG% || echo "**** Failed to build Pyside2 Debug ****" && exit /b 1

REM Unpack the wheels
set PYSIDE2_WHEEL=PySide2-%QTVERSION%-%PYSIDEVERSION%-cp%PYTHONMAJORVERSION%7-cp%PYTHONMAJORVERSION%7dm-win_amd64.whl
set SHIBOKEN2_WHEEL=shiboken2-%QTVERSION%-%PYSIDEVERSION%-cp%PYTHONMAJORVERSION%7-cp%PYTHONMAJORVERSION%7dm-win_amd64.whl
set SHIBOKEN2_GEN_WHEEL=shiboken2_generator-%QTVERSION%-%PYSIDEVERSION%-cp%PYTHONMAJORVERSION%7-cp%PYTHONMAJORVERSION%7dm-win_amd64.whl

%WHEEL_EXE% unpack %DIST_DIR_DEBUG%\%PYSIDE2_WHEEL% --dest=%DIST_DIR_DEBUG%\
%WHEEL_EXE% unpack %DIST_DIR_DEBUG%\%SHIBOKEN2_WHEEL% --dest=%DIST_DIR_DEBUG%\
%WHEEL_EXE% unpack %DIST_DIR_DEBUG%\%SHIBOKEN2_GEN_WHEEL% --dest=%DIST_DIR_DEBUG%\

echo ==== Success ====
