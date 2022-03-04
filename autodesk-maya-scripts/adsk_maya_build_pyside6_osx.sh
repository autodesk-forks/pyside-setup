# Exit bash script if return codes from commands are nonzero
set -u

# Parameter 1 - Absolute path to workspace directory
if [ $# -eq 0 ]; then
    echo "Need to pass workspace directory to the script"
    exit 1
fi

# Environment Variable - QTVERSION - Version of Qt used to build PySide6
if [[ -z "${QTVERSION}" ]]; then
    echo "QTVERSION is undefined. Example: export QTVERSION=6.2.3"
    exit 1
else
    echo "QTVERSION=${QTVERSION}"
fi

# Environment Variable - PYSIDEVERSION - Version of PySide6 built
if [[ -z "${PYSIDEVERSION}" ]]; then
    echo "PYSIDEVERSION is undefined. Example: export PYSIDEVERSION=6.2.3"
    exit 1
else
    echo "PYSIDEVERSION=${PYSIDEVERSION}"
fi

# Environment Variable - PYTHONVERSION - Version of Python for which PySide6 is built
# On macOS now, the python that is on the path is now used - so determine version from that.
export PYTHONVERSION=$(python --version | awk '{print $2}')

# Extract MAJOR(A), MINOR(B), and REVISION(C) from PYTHONVERSION
PYTHONVERSION_ARRAY=($(echo $PYTHONVERSION | tr "." "\n"))
PYTHONVERSION_A=${PYTHONVERSION_ARRAY[0]}
PYTHONVERSION_B=${PYTHONVERSION_ARRAY[1]}
PYTHONVERSION_C=${PYTHONVERSION_ARRAY[2]}

# Define Python Version Shortcuts (AB and A.B)
PYTHONVERSION_AB=${PYTHONVERSION_A}${PYTHONVERSION_B}
PYTHONVERSION_AdotB=${PYTHONVERSION_A}.${PYTHONVERSION_B}

# Validate that the Python version given is within the accepted values
if [[ ! ("$PYTHONVERSION_A" == "3") ]]; then
    echo "Python major version should be '3'. Example: export PYTHONVERSION=3.9.7"
    exit 1
fi

# Python 3.9.7 artifacts don't have any pymalloc suffix, but future python builds might. Leaving this in place.
export PYMALLOC_SUFFIX=

# Location of the workspace directory (root)
export WORKSPACE_DIR=$1

# Exit bash script if expanding vars that were never set.
set -e

# Location of external dependencies directory
export EXTERNAL_DEPENDENCIES_DIR=$WORKSPACE_DIR/external_dependencies

# Location of Qt build directory (in external dependencies)
export QTPATH=$EXTERNAL_DEPENDENCIES_DIR/qt_$QTVERSION

# Location of liblang directory (in external dependencies)
export CLANG_INSTALL_DIR=$EXTERNAL_DEPENDENCIES_DIR/libclang

# Name of the Python executable
export PYTHON_EXE=python${PYTHONVERSION_AdotB}


# Create qt.conf file
touch $EXTERNAL_DEPENDENCIES_DIR/qt_$QTVERSION/bin/qt.conf
echo [Paths] > $EXTERNAL_DEPENDENCIES_DIR/qt_$QTVERSION/bin/qt.conf
echo Prefix=.. >> $EXTERNAL_DEPENDENCIES_DIR/qt_$QTVERSION/bin/qt.conf

# Get the number of processors available to build PySide6
export NUMBER_OF_PROCESSORS=`sysctl -n hw.ncpu`

# Ensure that pip and its required modules are installed
$PYTHON_EXE -m ensurepip
$PYTHON_EXE -m pip install pip
$PYTHON_EXE -m pip install setuptools
$PYTHON_EXE -m pip install wheel==0.34.1
$PYTHON_EXE -m pip install packaging

# Note: Mac uses the python.org distribution of Python 3, so there is no need to modify `slots`.

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

for BUILDTYPE in release debug;
do
    export BUILDTYPE_STR="Release"
    export EXTRA_SETUP_PY_OPTS=""
    if [ "$BUILDTYPE" == "debug" ]; then
        export BUILDTYPE_STR="Debug"
        export EXTRA_SETUP_PY_OPTS="--debug"
    fi

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

    $PYTHON_EXE setup.py install --qmake=$QTPATH/bin/qmake --ignore-git --parallel=$NUMBER_OF_PROCESSORS --prefix=$PREFIX_DIR_BUILDTYPE $EXTRA_SETUP_PY_OPTS
    if [ $? -eq 0 ]; then
        echo "==== Success ==== $BUILDTYPE_STR Build"
    else
        echo "**** Failed to build **** $BUILDTYPE_STR Build"
        exit 1
    fi

    $PYTHON_EXE setup.py bdist_wheel --qmake=$QTPATH/bin/qmake --ignore-git --parallel=$NUMBER_OF_PROCESSORS --dist-dir=$DIST_DIR_BUILDTYPE $EXTRA_SETUP_PY_OPTS
    if [ $? -eq 0 ]; then
        echo "==== Success ==== $BUILDTYPE_STR Build Wheel"
    else
        echo "**** Failed to build **** $BUILDTYPE_STR Build Wheel"
        exit 1
    fi

    # Unpack the wheels
    export WHEEL_SUFFIX=${QTVERSION}-${PYSIDEVERSION}-cp${PYTHONVERSION_AB}-cp${PYTHONVERSION_AB}${PYMALLOC_SUFFIX}

    # Python 3.9.X was built with SDK version 10.14. Newer Python versions might be different.
    export WHEEL_SUFFIX=${WHEEL_SUFFIX}-macosx_10_14_x86_64
    export PYSIDE6_WHEEL=PySide6-${WHEEL_SUFFIX}.whl
    export SHIBOKEN6_WHEEL=shiboken6-${WHEEL_SUFFIX}.whl
    export SHIBOKEN6_GEN_WHEEL=shiboken6_generator-${WHEEL_SUFFIX}.whl

    $PYTHON_EXE -m wheel unpack "${DIST_DIR_BUILDTYPE}/${PYSIDE6_WHEEL}" --dest="${DIST_DIR_BUILDTYPE}"
    $PYTHON_EXE -m wheel unpack "${DIST_DIR_BUILDTYPE}/${SHIBOKEN6_WHEEL}" --dest="${DIST_DIR_BUILDTYPE}"
    $PYTHON_EXE -m wheel unpack "${DIST_DIR_BUILDTYPE}/${SHIBOKEN6_GEN_WHEEL}" --dest="${DIST_DIR_BUILDTYPE}"
done
echo "==== Finished ===="
