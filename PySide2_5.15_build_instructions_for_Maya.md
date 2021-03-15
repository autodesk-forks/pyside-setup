# Building PySide2 5.15.2 for Maya <a name="top-header"></a>

This page describes how PySide2 was built for Maya.

PySide2 shares the same requirements as Qt5. The same platforms, tools and compiler need to be used for both (see Qt 5.15.2 for Maya Build Instructions at https://github.com/autodesk-forks/pyside-setup/tree/adsk-contrib/maya/5.15.2/Qt5_5.15_build_instructions_for_Maya.md).

For Maya versions with dual-python support, PySide2 must be built for Python 2 and Python 3. The same build steps apply for both Python versions by changing paths and version numbers. When building PySide2 on Windows and Linux, you must use Maya's customized Python artifacts. The Python 2 and Python 3 artifacts are available at https://www.autodesk.com/developer-network/platform-technologies/maya. On Mac, Python 2 and 3 must be installed on your machine.

Build Scripts:<a name="build-scripts-links"></a>

The following instructions make use of build scripts to configure build options, compile PySide2, and package it for Maya. These scripts are available at https://github.com/autodesk-forks/pyside-setup/tree/adsk-contrib/maya/5.15.2/autodesk-maya-scripts/.

**Directory Structure** <a name="directory-structure"></a>

For the provided build scripts to work, you'll need to use the following directory structure, where `workspace_root` refers to the top-level directory:
- `workspace_root/`: contains all folders related to the build
    - `external_dependencies/`: contains the dependencies required to build PySide2
        - `qt_5.15.2/`: contains the Qt 5.15.2 build used to compile PySide2 
            - `bin/`, `doc/`, `include/`, `lib/`, `libexec/`, `mkspecs/`, `phrasebooks/`, `plugins/`, `qml/`, `resources/` and `translations/` folders
        - `python2`: contains the Python 2 artifact (on Windows/Linux) (link in the section above)
        - `python3`: contains the Python 3 artifact (on Windows/Linux) (link in the section above)
        - `libclang`: contains the libclang artifact
        - `openssl`: contains the OpenSSL 1.1.1 artifact (on Windows)
    - `build/`: contains the intermediate PySide2 builds after building
    - `install/`: contains the final PySide2 builds after packaging (release and debug)
    - `src/`: contains the PySide2 source code from Autodesk public fork (top of git tree - the `pyside-setup.git` will be cloned into this directory)
        - `autodesk-maya-scripts/`: build scripts for each platform (Windows, Mac and Linux)

The Build Steps section provides a list of external dependencies for each platform.

**PySide2 Source Code** 

Once the directory structure is created, clone the PySide2 source code in the `src/` folder. For convenience, a public fork with all the necessary patches is available at https://github.com/autodesk-forks/pyside-setup/. 
```sh
# Go to the workspace_root directory
cd /path/to/workspace_root

# Create the src/ folder that will contain the PySide2 source code (top of git tree)
mkdir src

# Clone Autodesk's pyside-setup public fork (top of git tree) into the src/ directory
git clone https://github.com/autodesk-forks/pyside-setup.git src

# Checkout the branch that was used to build PySide2 5.15.2 for Maya
cd src
git checkout adsk-maya-pyside-5.15.2
```

Once the cloning process is complete, execute the following commands in a terminal to initialize the repository (in the `src/` directory):
```sh
# Clean each submodule
git submodule foreach --recursive && git clean -dfx

# Initialize/update each submodule
git submodule update --init --recursive
```

#### Build Steps <a name="build-steps-header"></a>

After completing the setup steps, use provided scripts to build PySide2. There are 3 sets of scripts; one pair of build and package scripts for each platform.

The build scripts do the following steps:
1. Define the locations of tools and external dependencies using variables
2. Build using `setup.py` (from the `src/` directory)

Then, the packaging scripts perform the following steps:
1. Define the locations of tools and external dependencies using variables
2. Copy files from the `build/` directory to the `install/` directory
3. Change RUNPATHS of resulting libraries (for Linux and Mac)

Before using provided scripts, please review and adjust them as needed.

> The commands used to invoke scripts send all output to a log file to ease debugging. It is normal not to see any output in the terminal until scripts complete.

#### Windows <a name="build-steps-windows-header"></a>

_Jom is a clone of nmake to support the execution of multiple independent commands in parallel_, as described in https://wiki.qt.io/Jom. It is an optional tool that can be used to accelerate the build process on Windows.

External Dependencies:
- Qt 5.15.2 (built using the Qt 5.15.2 for Maya Build Instructions)
- Maya Python 2.7.11 artifact
- Maya Python 3.7.7 artifact
- Libclang 10 (release)
- OpenSSL 1.1.1 (RelWithDebInfo) (must be the same artifact used to build Qt 5.15.2)

To run the build script on Windows, execute the following commands from the command-line:

```batch
REM Set the path to the root folder of the workspace
SET WORKSPACE_ROOT_PATH=LETTER:\\path\\to\\workspace_root

REM Set the Qt version used to build PySide2
SET QTVERSION=5.15.2

REM Set the Python version for which PySide2 will be built
SET PYTHONMAJORVERSION=3

REM Generate a unique name for the log file with the datetime at the end
SET _TIME_DIGITS=%TIME:~0,5%
SET _TIME=%_TIME_DIGITS::=%
SET LOGFILE_NAME=pyside2_5_15_2_build_log_%DATE%-%_TIME%

REM Execute the build script from the src/ directory
cd /D "%WORKSPACE_ROOT_PATH%\\src"
autodesk-maya-scripts\\adsk_maya_build_pyside2_win.bat %WORKSPACE_ROOT_PATH% > "%WORKSPACE_ROOT_PATH%\\%LOGFILE_NAME%.txt" 2>&1
```

Then, to run the package script:

```batch
REM Set the Python version for which PySide2 will be built
SET PYSIDEVERSION=5.15.2

REM Generate a unique name for the log file with the datetime at the end
SET _TIME_DIGITS=%TIME:~0,5%
SET _TIME=%_TIME_DIGITS::=%
SET LOGFILE_NAME=pyside2_5_15_2_package_log_%DATE%-%_TIME%

REM Execute the build script from the src/ directory
cd /D "%WORKSPACE_ROOT_PATH%\\src"
autodesk-maya-scripts\\adsk_maya_package_pyside2_win.bat %WORKSPACE_ROOT_PATH% > "%WORKSPACE_ROOT_PATH%\\%LOGFILE_NAME%.txt" 2>&1
```

#### Mac  <a name="build-steps-mac-header"></a>

When building PySide2 on Mac, you must have Python 2.7.15 and Python 3.7 installed on your machine.

External Dependencies:
- Qt 5.15.2 (built using the Qt 5.15.2 for Maya Build Instructions)
- Libclang 7 (release)

To run the build script on Mac, execute the following commands from the terminal:

```sh
# Set the path to the root folder of the workspace
export WORKSPACE_ROOT_PATH=/path/to/workspace_root

# Generate a unique name for the log file with the datetime at the end
export LOGFILE_NAME=pyside2_5_15_2_build_log_`date +%Y-%m-%d-%H%M`

# Execute the build script from the src/ directory
cd "$WORKSPACE_ROOT_PATH/src"
PYTHONMAJORVERSION=3 QTVERSION=5.15.2 bash $WORKSPACE_ROOT_PATH/src/autodesk-maya-scripts/adsk_maya_build_pyside2_osx.sh $WORKSPACE_ROOT_PATH &>$WORKSPACE_ROOT_PATH/$LOGFILE_NAME.txt
```

Then, to run the package script:

```sh
# Set the path to the root folder of the workspace (optional if still in the same terminal)
export WORKSPACE_ROOT_PATH=/path/to/workspace_root

# Generate a unique name for the log file with the datetime at the end
export LOGFILE_NAME=pyside2_5_15_2_package_log_`date +%Y-%m-%d-%H%M`

# Execute the package script from the src/ directory
cd "$WORKSPACE_ROOT_PATH/src"
PYTHONMAJORVERSION=3 PYSIDEVERSION=5.15.2 QTVERSION=5.15.2 $WORKSPACE_ROOT_PATH/src/autodesk-maya-scripts/adsk_maya_package_pyside2_osx.sh $WORKSPACE_ROOT_PATH &>$WORKSPACE_ROOT_PATH/$LOGFILE_NAME.txt
```

#### Linux  <a name="build-steps-linux-header"></a>

Similar to the Qt build process, the `patchelf` utility is needed to adjust the RUNPATHs of the libraries after the build is completed. The minimum `cmake` version on Linux is 3.1.

External Dependencies:
- Qt 5.15.2 (built using the Qt 5.15.2 for Maya Build Instructions)
- Maya Python 2.7.11 artifact
- Maya Python 3.7.7 artifact
- Libclang 7 (release)

Note: There is no `--openssl` option when building PySide2 5.15.2 on Linux. Nevertheless, PySide2 will build correctly even if Qt has `--openssl` enabled.

To run the build script on Linux, execute the following commands from the terminal:

```sh
# Set the path to the root folder of the workspace
export WORKSPACE_ROOT_PATH=/path/to/workspace_root

# Generate a unique name for the log file with the datetime at the end
export LOGFILE_NAME=pyside2_5_15_2_build_log_`date +%Y-%m-%d-%H%M`

# Execute the build script from the src/ directory
cd "$WORKSPACE_ROOT_PATH/src"
scl enable devtoolset-9 'PYTHONMAJORVERSION=3 QTVERSION=5.15.2 bash $WORKSPACE_ROOT_PATH/src/autodesk-maya-scripts/adsk_maya_build_pyside2_lnx.sh $WORKSPACE_ROOT_PATH'
```

Then, to run the package script:

```sh
# Set the path to the root folder of the workspace 
# Required since executing the build script with the previous command starts a new terminal session
export WORKSPACE_ROOT_PATH=/path/to/workspace_root

# Generate a unique name for the log file with the datetime at the end
export LOGFILE_NAME=pyside2_5_15_2_package_log_`date +%Y-%m-%d-%H%M`

# Execute the package script from the src/ directory
cd "$WORKSPACE_ROOT_PATH/src"
PYSIDEVERSION=5.15.2 QTVERSION=5.15.2 $WORKSPACE_ROOT_PATH/src/autodesk-maya-scripts/adsk_maya_package_pyside2_lnx.sh $WORKSPACE_ROOT_PATH
```

[[Back to Top]](#top-header)