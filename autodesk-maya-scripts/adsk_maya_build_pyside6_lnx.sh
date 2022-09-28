#!/usr/bin/env bash

# Bash script safety
set -e # Terminate with error if any external command returns nonzero exit status (use || true to accept nonzero exit statuses)
set -u # Terminate with error if any undefined variable is dereferenced.

if [[ ! -f README.pyside6.md ]]; then
    echo >&2 "Please execute from the root of the pyside-setup repository."
    exit 1
fi

# Parameter 1 - Absolute path to workspace directory
if [ $# -eq 0 ]; then
    echo >&2 "Need to pass workspace directory to the script"
    exit 1
fi

# Environment Variable - QTVERSION - Version of Qt used to build PySide6
if [[ -z "${QTVERSION}" ]]; then
    echo >&2 "QTVERSION is undefined. Example: export QTVERSION=6.2.3"
    exit 1
else
    echo "QTVERSION=${QTVERSION}"
fi

# Environment Variable - PYSIDEVERSION - Version of PySide6 built
if [[ -z "${PYSIDEVERSION}" ]]; then
    echo >&2 "PYSIDEVERSION is undefined. Example: export PYSIDEVERSION=6.2.3"
    exit 1
else
    echo "PYSIDEVERSION=${PYSIDEVERSION}"
fi


# Location of the workspace directory (root)
export WORKSPACE_DIR=$1
# Location of external dependencies directory
export EXTERNAL_DEPENDENCIES_DIR=$WORKSPACE_DIR/external_dependencies

# Environment Variable - PYTHONVERSION - Version of Python for which PySide6 is built
if [[ -z "$PYTHONVERSION" && -d $EXTERNAL_DEPENDENCIES_DIR/cpython ]]; then
    GUESSED_PYVER=$(ls -1 $EXTERNAL_DEPENDENCIES_DIR/cpython)
    read -p "Is python version $GUESSED_PYVER (y/N)? " -n 1 query
    if [[ "$query" == "Y" || "$query" == "y" ]]; then
        PYTHONVERSION=$GUESSED_PYVER
    fi
fi

if [[ -z "$PYTHONVERSION" ]]; then
    echo >&2 "PYTHONVERSION is undefined. Example: export PYTHONVERSION=3.9.7"
    exit 1
else
    echo "PYTHONVERSION=${PYTHONVERSION}"
fi

# Extract MAJOR(A), MINOR(B), and REVISION(C) from PYTHONVERSION
PYTHONVERSION_ARRAY=($(echo $PYTHONVERSION | tr "." "\n"))
PYTHONVERSION_A=${PYTHONVERSION_ARRAY[0]}
PYTHONVERSION_B=${PYTHONVERSION_ARRAY[1]}
PYTHONVERSION_C=${PYTHONVERSION_ARRAY[2]}

# Define Python Version Shortcuts (AB and A.B)
PYTHONVERSION_AB=${PYTHONVERSION_A}${PYTHONVERSION_B}
PYTHONVERSION_AdotB=${PYTHONVERSION_A}.${PYTHONVERSION_B}

# Validate that the Python version given is within the accepted values
if [[ ! "$PYTHONVERSION_A" == "3" ]]; then
    echo >&2 "Only Python 3 is supported, please specify a Python 3 version."
    echo >&2 "Example: export PYTHONVERSION=3.9.7"
    exit 1
fi

# Python 3.9.7 artifacts don't have any pymalloc suffix, but future python builds might. Leaving this in place.
export PYMALLOC_SUFFIX=

# Location of Qt build directory (in external dependencies)
export QTPATH=$EXTERNAL_DEPENDENCIES_DIR/qt_$QTVERSION

# Location of Python directory (in external dependencies)
export PYTHONEXE_DIR=$EXTERNAL_DEPENDENCIES_DIR/cpython/${PYTHONVERSION}/RelWithDebInfo/bin
export PYTHONEXE_D_DIR=$EXTERNAL_DEPENDENCIES_DIR/cpython/${PYTHONVERSION}/Debug/bin

# Name of the Python executable
export PYTHON_EXE=python${PYTHONVERSION_AdotB}

# Allow PySide6 build to find libclang/llvm directory (same way Coin does it)
export LLVM_INSTALL_DIR=$LLVM_DYNAMIC_LIBS_100

# Cleanup PREFIX and DIST dirs. See below for their definition.
export PREFIX_DIR=$WORKSPACE_DIR/build
export DIST_DIR=$WORKSPACE_DIR/dist
for BUILDTYPE in release debug;
do
    if [ -e "${PREFIX_DIR}/${BUILDTYPE}" ]; then
        rm -rf "${PREFIX_DIR}/${BUILDTYPE}"
    fi

    if [ -e "${DIST_DIR}/${BUILDTYPE}" ]; then
        rm -rf "${DIST_DIR}/${BUILDTYPE}"
    fi
done


# Create qt.conf file
touch $EXTERNAL_DEPENDENCIES_DIR/qt_$QTVERSION/bin/qt.conf
echo [Paths] > $EXTERNAL_DEPENDENCIES_DIR/qt_$QTVERSION/bin/qt.conf
echo Prefix=.. >> $EXTERNAL_DEPENDENCIES_DIR/qt_$QTVERSION/bin/qt.conf

# Store current PATH to be able to restore it later
export OLDPATH=$PATH

# Get the number of processors available to build PySide6
export NUMBER_OF_PROCESSORS=`cat /proc/cpuinfo | grep processor | wc -l`


for BUILDTYPE in release debug;
do
    if [ "$BUILDTYPE" == "debug" ]; then
        export BUILDTYPE_STR="Debug"
        export PYTHONEXEPATH=$PYTHONEXE_D_DIR
        export EXTRA_SETUP_PY_OPTS="--debug"
        export DEBUG_SUFFIX=d
    else
        export BUILDTYPE_STR="Release"
        export PYTHONEXEPATH=$PYTHONEXE_DIR
        export EXTRA_SETUP_PY_OPTS=""
        export DEBUG_SUFFIX=
    fi

    # Add Python executable to the PATH
    export PATH=$PYTHONEXEPATH:$OLDPATH

    # By default, the pyside6-uic and pyside6-rcc wrappers are installed in the Python directory during the install step.
    # Using the --prefix option, we specify a different location where to output the files, which makes it easier to copy
    # the wrappers in the /bin folder when packaging.
    export PREFIX_DIR_BUILDTYPE="${PREFIX_DIR}/${BUILDTYPE}"
    mkdir -p "$PREFIX_DIR_BUILDTYPE"

    # Location where the built wheels will be outputted
    # To be able to use pyside6-uic and pyside6-rcc, we need the metadata from the .dist-info folders,
    # which can be obtained by unpacking the wheels.
    export DIST_DIR_BUILDTYPE="${DIST_DIR}/${BUILDTYPE}"
    mkdir -p "$DIST_DIR_BUILDTYPE"

    # Ensure that pip and its required modules are installed for Python 3 (release version)
    $PYTHON_EXE -m ensurepip
    $PYTHON_EXE -m pip install --upgrade pip
    $PYTHON_EXE -m pip install setuptools wheel

    # Now install all required Python modules for building from pyside-setup's requirements.txt file.
    $PYTHON_EXE -m pip install -r requirements.txt

    if [ "$BUILDTYPE" == "release" ]; then
        # Maya redefines `slots` so it is called `slots_` in the file. Rename it so it can be detected again
        sed -i -e 's/\(PyType_Slot\ \*slots\)_/\1/' $EXTERNAL_DEPENDENCIES_DIR/cpython/${PYTHONVERSION}/RelWithDebInfo/include/python${PYTHONVERSION_AdotB}${PYMALLOC_SUFFIX}/object.h
    fi

    # CMake is now installed the same way Qt CI does it, which places it in the path in the build user's bashrc
    # So it no longer needs to be explicitly added to the path.

    # Build PySide6
    $PYTHON_EXE setup.py install --qmake=$QTPATH/bin/qmake --ignore-git --parallel=$NUMBER_OF_PROCESSORS --prefix=$PREFIX_DIR_BUILDTYPE $EXTRA_SETUP_PY_OPTS
    if [ $? -eq 0 ]; then
        echo "==== Success ==== $BUILDTYPE_STR Build"
    else
        echo >&2 "**** Failed to build **** $BUILDTYPE_STR Build"
        exit 1
    fi
    $PYTHON_EXE setup.py bdist_wheel --qmake=$QTPATH/bin/qmake --ignore-git --parallel=$NUMBER_OF_PROCESSORS --dist-dir=$DIST_DIR_BUILDTYPE $EXTRA_SETUP_PY_OPTS
    if [ $? -eq 0 ]; then
        echo "==== Success ==== $BUILDTYPE_STR Build Wheel"
    else
        echo >&2 "**** Failed to build **** $BUILDTYPE_STR Build Wheel"
        exit 1
    fi

    # Unpack the wheels
    export WHEEL_SUFFIX=${QTVERSION}-${PYSIDEVERSION}-cp${PYTHONVERSION_AB}-cp${PYTHONVERSION_AB}
    export WHEEL_SUFFIX=${WHEEL_SUFFIX}${DEBUG_SUFFIX}${PYMALLOC_SUFFIX}-linux_x86_64

    export PYSIDE6_WHEEL=PySide6-${WHEEL_SUFFIX}.whl
    export SHIBOKEN6_WHEEL=shiboken6-${WHEEL_SUFFIX}.whl
    export SHIBOKEN6_GEN_WHEEL=shiboken6_generator-${WHEEL_SUFFIX}.whl

    $PYTHON_EXE -m wheel unpack $DIST_DIR_BUILDTYPE/$PYSIDE6_WHEEL --dest=$DIST_DIR_BUILDTYPE
    $PYTHON_EXE -m wheel unpack $DIST_DIR_BUILDTYPE/$SHIBOKEN6_WHEEL --dest=$DIST_DIR_BUILDTYPE
    $PYTHON_EXE -m wheel unpack $DIST_DIR_BUILDTYPE/$SHIBOKEN6_GEN_WHEEL --dest=$DIST_DIR_BUILDTYPE
done
