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
set PATH_TO_MAYAPY_REGEX="1s/.*/\#\!bin\/mayapy2.exe/"
if exist "pyside3_install" (
    set PY_MAJORVER=3
    set PATH_TO_MAYAPY_REGEX="1s/.*/\#\!bin\/mayapy.exe/"
)


REM Location of the workspace directory (root)
set WORKSPACE_DIR=%1

REM Location of the source code directory within the workspace
set SOURCE_DIR=%WORKSPACE_DIR%\src

REM Location of the install directory within the workspace (where the builds will be located)
set INSTALL_DIR=%WORKSPACE_DIR%\install

REM Location of the pyside2-uic and pyside2-rcc wrappers (determined by the --prefix option in the build script)
set PREFIX_DIR=%WORKSPACE_DIR%\build

REM Location of the pyside2-uic and pyside2-rcc .dist-info metadata folders (determined by the --dist-dir option in the build script)
set DIST_DIR=%WORKSPACE_DIR%\dist
set DIST_DIR_R=%DIST_DIR%\RelWithDebInfo
set DIST_DIR_D=%DIST_DIR%\Debug

REM Remove the previous build from the install directory
if exist %INSTALL_DIR% (
    rmdir /s /q "%INSTALL_DIR%"
)
mkdir "%INSTALL_DIR%"


REM Write PySide2 build information to a "pyside2_version" file 
REM instead of encoding the pyside version number in a directory name
echo pyside2 %PYSIDEVERSION% > %INSTALL_DIR%\pyside2_version
echo qt %QTVERSION% >> %INSTALL_DIR%\pyside2_version
echo python major version %PY_MAJORVER% >> %INSTALL_DIR%\pyside2_version


REM Location of the root of packaged PySide2 artifacts (RelWithDebInfo and Debug)
set ARTIFACT_ROOT_R=%INSTALL_DIR%\pyside%PY_MAJORVER%_install\py%PY_MAJORVER%.7-qt%QTVERSION%-64bit-relwithdebinfo
set ARTIFACT_ROOT_D=%INSTALL_DIR%\pyside%PY_MAJORVER%dp_install\py%PY_MAJORVER%.7-qt%QTVERSION%-64bit-debug

if exist pyside%PY_MAJORVER%_install (

    REM Copy PySide2 release build into the install directory
    robocopy /mir /ns /nc /np pyside%PY_MAJORVER%_install %INSTALL_DIR%\pyside%PY_MAJORVER%_install /XD __pycache__

    REM Workaround: Since the pyside2-uic and pyside2-rcc wrappers are not installed in the build directory, we need to copy them from 
    REM the --prefix directory into the artifact's bin folder
    for %%R in (pyside2-uic.exe, pyside2-uic-script.py, pyside2-rcc.exe, pyside2-rcc-script.py) do (
        robocopy /ns /nc /np %PREFIX_DIR%\RelWithDebInfo\Scripts %ARTIFACT_ROOT_R%\bin %%R
    )

    REM Copy the .dist-info metadata folders, since the pyside2-uic and pyside2-rcc wrappers rely on [console_scripts] entrypoints.
    for %%R in (PySide2, shiboken2, shiboken2_generator) do (
        robocopy /mir /ns /nc /np %DIST_DIR_R%\%%R-%PYSIDEVERSION%\%%R-%PYSIDEVERSION%.dist-info %ARTIFACT_ROOT_R%\lib\site-packages\%%R-%PYSIDEVERSION%.dist-info
        rename %ARTIFACT_ROOT_R%\lib\site-packages\%%R-%PYSIDEVERSION%.dist-info\RECORD RECORD-DONOTUNINSTALL
    )

    REM Copy uic and rcc executable into site-packages/PySide2, since it is the first search location for loadUiType.
    for %%R in (uic.exe, rcc.exe) do (
        robocopy /ns /nc /np %PREFIX_DIR%\RelWithDebInfo\Lib\site-packages\PySide2\ %ARTIFACT_ROOT_R%\lib\site-packages\PySide2\ %%R
    )
    
    REM Copy the 'scripts' PySide2 sudmodules folder manually, since the pyside2-uic and pyside2-rcc wrappers invoke 
    REM pyside_tool.py through console_scripts entrypoints.
    robocopy /mir /ns /nc /np %PREFIX_DIR%\RelWithDebInfo\Lib\site-packages\PySide2\scripts %ARTIFACT_ROOT_R%\lib\site-packages\PySide2\scripts /XD __pycache__

    REM Workaround: Until the issue is addressed within PySide2 build scripts, we manually copy the 'support' PySide2 submodule
    REM into the build to prevent the "__feature__ could not be imported" error.
    robocopy /mir /ns /nc /np %PREFIX_DIR%\RelWithDebInfo\Lib\site-packages\PySide2\support %ARTIFACT_ROOT_R%\lib\site-packages\PySide2\support /XD __pycache__
    
    REM Replace interpreter path for relative path to mayapy
    sed -i -e %PATH_TO_MAYAPY_REGEX% %ARTIFACT_ROOT_R%\bin\pyside2-uic-script.py
    sed -i -e %PATH_TO_MAYAPY_REGEX% %ARTIFACT_ROOT_R%\bin\pyside2-rcc-script.py
)
if exist pyside%PY_MAJORVER%dp_install (

    REM Copy PySide2 debug build into the install directory
    robocopy /mir /ns /nc /np pyside%PY_MAJORVER%dp_install %INSTALL_DIR%\pyside%PY_MAJORVER%dp_install /XD __pycache__

    REM Workaround: Since the pyside2-uic and pyside2-rcc wrappers are not installed in the build directory, we need to copy them from 
    REM the --prefix directory into the artifact's /bin folder
    for %%D in (pyside2-uic.exe, pyside2-uic-script.py, pyside2-rcc.exe, pyside2-rcc-script.py) do (
        robocopy /ns /nc /np %PREFIX_DIR%\RelWithDebInfo\Scripts %ARTIFACT_ROOT_D%\bin %%D
    )
    
    REM Copy the .dist-info metadata folders, since the pyside2-uic and pyside2-rcc wrappers entry_points rely on them.
    for %%D in (PySide2, shiboken2, shiboken2_generator) do (
        robocopy /mir /ns /nc /np %DIST_DIR_D%\%%D-%PYSIDEVERSION%\%%D-%PYSIDEVERSION%.dist-info %ARTIFACT_ROOT_D%\lib\site-packages\%%D-%PYSIDEVERSION%.dist-info
        rename %ARTIFACT_ROOT_D%\lib\site-packages\%%D-%PYSIDEVERSION%.dist-info\RECORD RECORD-DONOTUNINSTALL
    )
    
    REM Copy uic and rcc executable into site-packages/PySide2, since it is the first search location for loadUiType.
    for %%D in (uic.exe, rcc.exe) do (
        robocopy /ns /nc /np %PREFIX_DIR%\Debug\Lib\site-packages\PySide2\ %ARTIFACT_ROOT_D%\lib\site-packages\PySide2\ %%D
    )

    REM Copy the 'scripts' PySide2 sudmodules folder manually, since the pyside2-uic and pyside2-rcc wrappers invoke 
    REM pyside_tool.py through [console_scripts] entrypoints.
    robocopy /mir /ns /nc /np %PREFIX_DIR%\Debug\Lib\site-packages\PySide2\scripts %ARTIFACT_ROOT_D%\lib\site-packages\PySide2\scripts /XD __pycache__

    REM Workaround: Until the issue is addressed within PySide2 build scripts, we manually copy the 'support' PySide2 submodule
    REM into the build to prevent the "__feature__ could not be imported" error.
    robocopy /mir /ns /nc /np %PREFIX_DIR%\Debug\Lib\site-packages\PySide2\support %ARTIFACT_ROOT_D%\lib\site-packages\PySide2\support /XD __pycache__
    
    REM Replace interpreter path for relative path to mayapy
    sed -i -e %PATH_TO_MAYAPY_REGEX% %ARTIFACT_ROOT_D%\bin\pyside2-uic-script.py
    sed -i -e %PATH_TO_MAYAPY_REGEX% %ARTIFACT_ROOT_D%\bin\pyside2-rcc-script.py
)

echo ==== Success ====
