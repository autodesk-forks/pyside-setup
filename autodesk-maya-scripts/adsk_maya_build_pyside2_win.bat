@echo off
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

REM Environment Variable - QTVERSION - Version of Qt used to build PySide2
if not defined QTVERSION (
    echo QTVERSION is NOT defined. Example: SET QTVERSION=5.15.2
    echo aborting.
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

REM Environment Variable - PYTHONVERSION - Version of Python for which PySide2 is built
if not defined PYTHONVERSION (
    echo PYTHONVERSION is NOT defined. Example: SET PYTHONVERSION=3.9.7
    echo aborting.
    exit /b 1
)

REM Environment Variable - PYTHONEXE - The release Python executable to use
if not defined PYTHONEXE (
    echo PYTHONEXE is NOT defined. Example: SET PYTHONEXE=%1/external_dependencies/cpython/3.9.5/RelWithdebInfo/python.exe
    echo aborting.
    exit /b 1
)
FOR /F "delims=" %%i IN ('%PYTHONEXE% -c "import sys; v=sys.version_info; print('{}.{}.{}'.format(v.major, v.minor, v.micro))"') DO set pythonexe_version=%%i
if not "%pythonexe_version%" == "%PYTHONVERSION%" (
    echo Expecting Python %PYTHONVERSION%, but the python executable %PYTHONEXE% is %pythonexe_version%.
    echo aborting.
    exit /b 1
)
REM Environment Variable - PYTHONDEXE - The debug Python executable to use
if not defined PYTHONDEXE (
    echo PYTHONDEXE is NOT defined. Example: SET PYTHONDEXE=%1/external_dependencies/cpython/3.9.5/Debug/python_d.exe
    echo aborting.
    exit /b 1
)
FOR /F "delims=" %%i IN ('%PYTHONDEXE% -c "import sys; v=sys.version_info; print('{}.{}.{}'.format(v.major, v.minor, v.micro))"') DO set pythonexe_version=%%i
if not "%pythonexe_version%" == "%PYTHONVERSION%" (
    echo Expecting Python %PYTHONVERSION%, but the python executable %PYTHONDEXE% is %pythonexe_version%.
    echo aborting.
    exit /b 1
)


REM Extract MAJOR(A), MINOR(B), and REVISION(C) from PYTHONVERSION
setlocal EnableDelayedExpansion
FOR /f "tokens=1,2,3 delims=." %%a IN ("%PYTHONVERSION%") DO set PYTHONVERSION_A=%%a& set PYTHONVERSION_B=%%b& set PYTHONVERSION_C=%%c

REM Define Python Version Shortcuts (AB and A.B)
set PYTHONVERSION_AB=%PYTHONVERSION_A%%PYTHONVERSION_B%

REM Validate that the Python version given is within the accepted values
set pymajorver_acceptable_values=2,3
if "!pymajorver_acceptable_values:%PYTHONVERSION_A%=!" == "!pymajorver_acceptable_values!" (
    echo Python major version should be '2' or '3'.  Example: SET PYTHONVERSION=3.9.7
    echo aborting.
    exit /b 1
) else (
    echo PYTHONVERSION=%PYTHONVERSION%
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

set WHEEL_EXE=%PYTHONEXE% -m wheel

REM Python 2.7.X and 3.7.X artifacts have files with the pymalloc suffix
set PYMALLOC_SUFFIX=
if not "%PYTHONVERSION_B%" == "7" goto PYMALLOC_HANDLING_DONE
    set PYMALLOC_SUFFIX=m
:PYMALLOC_HANDLING_DONE

REM Add paths to libclang, jom and python executables to the PATH environment variable
set PATH=%LLVM_INSTALL_DIR%\bin;%JOM_DIR%;%PATH%;
echo PATH=%PATH%


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
if not exist %JOM_DIR% (
    echo error: JOM_DIR %JOM_DIR% does not exist.
    echo aborting.
    exit /b 1
)


REM Create qt.conf file
echo [Paths] > %QTPATH%\bin\qt.conf
echo Prefix=.. >> %QTPATH%\bin\qt.conf


REM Build PySide2 release version
%PYTHONEXE% -V

if not "%PYTHONVERSION_A%" == "2" goto PYTHON2_INSTALL_REL_DONE
    REM Ensure that pip and its required modules are installed for Python 2 (release version)
    %PYTHONEXE% -m pip install packaging
:PYTHON2_INSTALL_REL_DONE

if not "%PYTHONVERSION_A%" == "3" goto PYTHON3_INSTALL_REL_DONE	
    REM Ensure that pip and its required modules are installed for Python 3 (release version)
    %PYTHONEXE% -m ensurepip
    %PYTHONEXE% -m pip install pip
    %PYTHONEXE% -m pip install setuptools
    %PYTHONEXE% -m pip install wheel==0.34.1
    %PYTHONEXE% -m pip install packaging
:PYTHON3_INSTALL_REL_DONE
%PYTHONEXE% setup.py install --relwithdebinfo --qmake=%QTPATH%\bin\qmake.exe --openssl=%OPENSSLPATH%\RelWithDebInfo\bin --build-tests --ignore-git --parallel=%NUMBER_OF_PROCESSORS% --prefix=%PREFIX_DIR_RELWITHDEBINFO% || echo "**** Failed to build Pyside2 Release ****" && exit /b 1
%PYTHONEXE% setup.py bdist_wheel --relwithdebinfo --qmake=%QTPATH%\bin\qmake.exe --openssl=%OPENSSLPATH%\RelWithDebInfo\bin --build-tests --ignore-git --parallel=%NUMBER_OF_PROCESSORS% --dist-dir=%DIST_DIR_RELWITHDEBINFO% || echo "**** Failed to build Pyside2 Release ****" && exit /b 1

REM Unpack the wheels
set WHEEL_SUFFIX=%PYSIDEVERSION%-%QTVERSION%-cp%PYTHONVERSION_AB%-cp%PYTHONVERSION_AB%%PYMALLOC_SUFFIX%-win_amd64

set PYSIDE2_WHEEL=PySide2-%WHEEL_SUFFIX%.whl
set SHIBOKEN2_WHEEL=shiboken2-%WHEEL_SUFFIX%.whl
set SHIBOKEN2_GEN_WHEEL=shiboken2_generator-%WHEEL_SUFFIX%.whl

%WHEEL_EXE% unpack %DIST_DIR_RELWITHDEBINFO%\%PYSIDE2_WHEEL% --dest=%DIST_DIR_RELWITHDEBINFO%\
%WHEEL_EXE% unpack %DIST_DIR_RELWITHDEBINFO%\%SHIBOKEN2_WHEEL% --dest=%DIST_DIR_RELWITHDEBINFO%\
%WHEEL_EXE% unpack %DIST_DIR_RELWITHDEBINFO%\%SHIBOKEN2_GEN_WHEEL% --dest=%DIST_DIR_RELWITHDEBINFO%\


REM Build PySide2 debug version
%PYTHONDEXE% -V

if not "%PYTHONVERSION_A%" == "2" goto PYTHON2_INSTALL_DEB_DONE
    REM Ensure that pip and its required modules are installed for Python 2 (debug version)
    %PYTHONDEXE% -m pip install packaging
:PYTHON2_INSTALL_DEB_DONE

if not "%PYTHONVERSION_A%" == "3" goto PYTHON3_INSTALL_DEB_DONE
    REM Ensure that pip and its required modules are installed for Python 3 (debug version)
    %PYTHONDEXE% -m ensurepip
    %PYTHONDEXE% -m pip install pip
    %PYTHONDEXE% -m pip install setuptools
    %PYTHONDEXE% -m pip install wheel==0.34.1
    %PYTHONDEXE% -m pip install packaging
:PYTHON3_INSTALL_DEB_DONE
%PYTHONDEXE% setup.py install --debug --qmake=%QTPATH%\bin\qmake.exe --openssl=%OPENSSLPATH%\Debug\bin --ignore-git --parallel=%NUMBER_OF_PROCESSORS% --prefix=%PREFIX_DIR_DEBUG% || echo "**** Failed to build Pyside2 Debug ****" && exit /b 1
%PYTHONDEXE% setup.py bdist_wheel --debug --qmake=%QTPATH%\bin\qmake.exe --openssl=%OPENSSLPATH%\Debug\bin --ignore-git --parallel=%NUMBER_OF_PROCESSORS% --dist-dir=%DIST_DIR_DEBUG% || echo "**** Failed to build Pyside2 Debug ****" && exit /b 1

REM Unpack the wheels
set WHEEL_SUFFIX=%PYSIDEVERSION%-%QTVERSION%-cp%PYTHONVERSION_AB%-cp%PYTHONVERSION_AB%d%PYMALLOC_SUFFIX%-win_amd64

set PYSIDE2_WHEEL=PySide2-%WHEEL_SUFFIX%.whl
set SHIBOKEN2_WHEEL=shiboken2-%WHEEL_SUFFIX%.whl
set SHIBOKEN2_GEN_WHEEL=shiboken2_generator-%WHEEL_SUFFIX%.whl

%WHEEL_EXE% unpack %DIST_DIR_DEBUG%\%PYSIDE2_WHEEL% --dest=%DIST_DIR_DEBUG%\
%WHEEL_EXE% unpack %DIST_DIR_DEBUG%\%SHIBOKEN2_WHEEL% --dest=%DIST_DIR_DEBUG%\
%WHEEL_EXE% unpack %DIST_DIR_DEBUG%\%SHIBOKEN2_GEN_WHEEL% --dest=%DIST_DIR_DEBUG%\

echo ==== Success ====
