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
    echo "PYTHONVERSION is NOT defined. Example: SET PYTHONVERSION=3.9.5"
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
    echo "Python major version should be '3'.  Example: SET PYTHONVERSION=3.9.5"
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
echo pyside6 %PYSIDEVERSION% > %INSTALL_DIR%\pyside6_version
echo qt %QTVERSION% >> %INSTALL_DIR%\pyside6_version
echo python version %PYTHONVERSION% >> %INSTALL_DIR%\pyside6_version


REM Location of the root of packaged PySide6 artifacts (RelWithDebInfo and Debug)
set ARTIFACT_ROOT_R=%INSTALL_DIR%\pyside%PYTHONVERSION_A%_install\py%PYTHONVERSION_AdotB%-qt%QTVERSION%-64bit-relwithdebinfo
set ARTIFACT_ROOT_D=%INSTALL_DIR%\pyside%PYTHONVERSION_A%dp_install\py%PYTHONVERSION_AdotB%-qt%QTVERSION%-64bit-debug

if exist pyside6_install (

    REM Copy PySide6 release build into the install directory
    robocopy /mir /ns /nc /np pyside6_install %INSTALL_DIR%\pyside6_install /XD __pycache__

    REM Workaround: Since the pyside6-uic and pyside6-rcc wrappers are not installed in the build directory, we need to copy them from 
    REM the --prefix directory into the artifact's bin folder
    for %%R in (pyside6-uic.exe, pyside6-uic-script.py, pyside6-rcc.exe, pyside6-rcc-script.py) do (
        robocopy /ns /nc /np %PREFIX_DIR%\RelWithDebInfo\Scripts %ARTIFACT_ROOT_R%\bin %%R
    )

    REM Copy the .dist-info metadata folders, since the pyside6-uic and pyside6-rcc wrappers rely on [console_scripts] entrypoints.
    for %%R in (PySide6, shiboken6, shiboken6_generator) do (
        robocopy /mir /ns /nc /np %DIST_DIR_R%\%%R-%PYSIDEVERSION%\%%R-%PYSIDEVERSION%.dist-info %ARTIFACT_ROOT_R%\lib\site-packages\%%R-%PYSIDEVERSION%.dist-info
        rename %ARTIFACT_ROOT_R%\lib\site-packages\%%R-%PYSIDEVERSION%.dist-info\RECORD RECORD-DONOTUNINSTALL
    )

    REM Copy uic and rcc executable into site-packages/PySide6, since it is the first search location for loadUiType.
    for %%R in (uic.exe, rcc.exe) do (
        robocopy /ns /nc /np %PREFIX_DIR%\RelWithDebInfo\Lib\site-packages\PySide6\ %ARTIFACT_ROOT_R%\lib\site-packages\PySide6\ %%R
    )
    
    REM Copy the 'scripts' PySide6 sudmodules folder manually, since the pyside6-uic and pyside6-rcc wrappers invoke 
    REM pyside_tool.py through console_scripts entrypoints.
    robocopy /mir /ns /nc /np %PREFIX_DIR%\RelWithDebInfo\Lib\site-packages\PySide6\scripts %ARTIFACT_ROOT_R%\lib\site-packages\PySide6\scripts /XD __pycache__

    REM Workaround: Until the issue is addressed within PySide6 build scripts, we manually copy the 'support' PySide6 submodule
    REM into the build to prevent the "__feature__ could not be imported" error.
    robocopy /mir /ns /nc /np %PREFIX_DIR%\RelWithDebInfo\Lib\site-packages\PySide6\support %ARTIFACT_ROOT_R%\lib\site-packages\PySide6\support /XD __pycache__
    
    REM Replace interpreter path for relative path to mayapy
    sed -i -e %PATH_TO_MAYAPY_REGEX% %ARTIFACT_ROOT_R%\bin\pyside6-uic-script.py
    sed -i -e %PATH_TO_MAYAPY_REGEX% %ARTIFACT_ROOT_R%\bin\pyside6-rcc-script.py
)
if exist pyside6dp_install (

    REM Copy PySide6 debug build into the install directory
    robocopy /mir /ns /nc /np pyside6dp_install %INSTALL_DIR%\pyside6%dp_install /XD __pycache__

    REM Workaround: Since the pyside6-uic and pyside6-rcc wrappers are not installed in the build directory, we need to copy them from 
    REM the --prefix directory into the artifact's /bin folder
    for %%D in (pyside6-uic.exe, pyside6-uic-script.py, pyside6-rcc.exe, pyside6-rcc-script.py) do (
        robocopy /ns /nc /np %PREFIX_DIR%\RelWithDebInfo\Scripts %ARTIFACT_ROOT_D%\bin %%D
    )
    
    REM Copy the .dist-info metadata folders, since the pyside6-uic and pyside6-rcc wrappers entry_points rely on them.
    for %%D in (PySide6, shiboken6, shiboken6_generator) do (
        robocopy /mir /ns /nc /np %DIST_DIR_D%\%%D-%PYSIDEVERSION%\%%D-%PYSIDEVERSION%.dist-info %ARTIFACT_ROOT_D%\lib\site-packages\%%D-%PYSIDEVERSION%.dist-info
        rename %ARTIFACT_ROOT_D%\lib\site-packages\%%D-%PYSIDEVERSION%.dist-info\RECORD RECORD-DONOTUNINSTALL
    )
    
    REM Copy uic and rcc executable into site-packages/PySide6, since it is the first search location for loadUiType.
    for %%D in (uic.exe, rcc.exe) do (
        robocopy /ns /nc /np %PREFIX_DIR%\Debug\Lib\site-packages\PySide6\ %ARTIFACT_ROOT_D%\lib\site-packages\PySide6\ %%D
    )

    REM Copy the 'scripts' PySide6 sudmodules folder manually, since the pyside6-uic and pyside6-rcc wrappers invoke 
    REM pyside_tool.py through [console_scripts] entrypoints.
    robocopy /mir /ns /nc /np %PREFIX_DIR%\Debug\Lib\site-packages\PySide6\scripts %ARTIFACT_ROOT_D%\lib\site-packages\PySide6\scripts /XD __pycache__

    REM Workaround: Until the issue is addressed within PySide6 build scripts, we manually copy the 'support' PySide6 submodule
    REM into the build to prevent the "__feature__ could not be imported" error.
    robocopy /mir /ns /nc /np %PREFIX_DIR%\Debug\Lib\site-packages\PySide6\support %ARTIFACT_ROOT_D%\lib\site-packages\PySide6\support /XD __pycache__
    
    REM Replace interpreter path for relative path to mayapy
    sed -i -e %PATH_TO_MAYAPY_REGEX% %ARTIFACT_ROOT_D%\bin\pyside6-uic-script.py
    sed -i -e %PATH_TO_MAYAPY_REGEX% %ARTIFACT_ROOT_D%\bin\pyside6-rcc-script.py
)

echo ==== Success ====
