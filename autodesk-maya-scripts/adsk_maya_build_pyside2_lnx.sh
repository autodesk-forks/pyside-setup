#!/usr/bin/env bash

set -e # Terminate with failure if any command returns nonzero
set -u # Terminate with failure any time an undefined variable is expanded

if [[ ! -f README.pyside2.md ]]; then
    echo >&2 "Please execute from the root of the pyside-setup repository."
    exit 1
fi

# Parameter 1 - Absolute path to workspace directory
if [[ $# -eq 0 ]]; then
    echo >&2 "Need to pass workspace directory to the script"
    exit 1
fi

set +u
# Environment Variable - QTVERSION - Version of Qt used to build PySide2
if [[ -z "${QTVERSION}" ]]; then
    echo >&2 "QTVERSION is undefined. Example: export QTVERSION=5.15.2"
    exit 1
else
    echo "QTVERSION=${QTVERSION}"
fi

# Environment Variable - PYSIDEVERSION - Version of PySide2 built
if [[ -z "${PYSIDEVERSION}" || "${PYSIDEVERSION^^}" == "PREFLIGHT" ]]; then
    # Assume PYSIDEVERSION matches QTVERSION, as it should anyway...
    export PYSIDEVERSION=$QTVERSION
fi
if [[ ! ${PYSIDEVERSION} =~ ^[0-9]{1,2}\.[0-9]{1,3}\.[0-9]{1,3}(\.[1-9])?$ ]]; then
    echo "PYSIDEVERSION is invalid. It should be a version number. Example: export PYSIDEVERSION=5.15.2"
    exit 1
fi
echo "PYSIDEVERSION=${PYSIDEVERSION}"

# Check for OS version in the same way that Jenkinsfile does.
OS=
distro=$(hostnamectl | awk '/Operating System/ { print $3 }')
if [[ "$distro" =~ "CentOS" ]]; then
    OS="centos7"
else
    # Assuming RHEL8
    OS="rhel"
fi

for pythonexe in ${PYTHONEXE} ${PYTHONDEXE}; do
    pythonexe_varname="PYTHONEXE"
    pythonconfig="RelWithDebInfo"
    if [[ "$pythonexe" == "$PYTHONDEXE" ]]; then
        pythonexe_varname="PYTHONDEXE"
        pythonconfig="Debug"
    fi

    # Make sure the user has passed in a python executable to use
    if [[ -z "$pythonexe" || ! -e "$pythonexe" ]]; then
        if [[ -z "$pythonexe" ]]; then echo -n "${pythonexe_varname} is undefined. "; fi
        if [[ ! -e "$pythonexe" ]]; then echo -n "${pythonexe} doesn't exist. "; fi
        if [[ ! -x "$pythonexe" ]]; then echo -n "${pythonexe} isn't executable. "; fi
        echo "Example: export ${pythonexe_varname}=$1/external_dependencies/cpython/3.9.5/${pythonconfig}/bin/python3.9"
        exit 1
    else
        echo "${pythonexe_varname}=${pythonexe}"
    fi

    pythonexe_version=$($pythonexe -c "import sys; v=sys.version_info; print('{}.{}.{}'.format(v.major, v.minor, v.micro))")
    if [[ ! "$pythonexe_version" == "$PYTHONVERSION" ]]; then
        echo >&2 "Expecting Python ${PYTHONVERSION}, but the python executable ${pythonexe} is ${pythonexe_version}. aborting."
        exit 1
    fi
done

# Environment Variable - PYTHONVERSION - Version of Python for which PySide2 is built
echo "PYTHONVERSION=${PYTHONVERSION}"

# Extract MAJOR(A), MINOR(B), and REVISION(C) from PYTHONVERSION
PYTHONVERSION_ARRAY=($(echo $PYTHONVERSION | tr "." "\n"))
PYTHONVERSION_A=${PYTHONVERSION_ARRAY[0]}
PYTHONVERSION_B=${PYTHONVERSION_ARRAY[1]}
PYTHONVERSION_C=${PYTHONVERSION_ARRAY[2]}

# Define Python Version Shortcuts (AB and A.B)
PYTHONVERSION_AB=${PYTHONVERSION_A}${PYTHONVERSION_B}
PYTHONVERSION_AdotB=${PYTHONVERSION_A}.${PYTHONVERSION_B}

# Validate that the Python version given is within the accepted values
if [[ ! "$PYTHONVERSION" =~ (2\.7\.1[0-9]|3\.9\.5|3\.9\.7) ]]; then
    # We expect the python version to be 2.7.10+, 3.9.5 or 3.9.7 right now. It
    # will change in the future, and at that time this check should be updated
    # to reflect the newly supported python versions.
    echo >&2 "Expecting Python 2.7.1?, 3.9.5 or 3.9.7. aborting."
    echo >&2 "Example: export PYTHONVERSION=3.9.7"
    exit 1
fi

# Python 2.7.X and 3.7.X artifacts have files with the pymalloc suffix
export PYMALLOC_SUFFIX=
if [ $PYTHONVERSION_B -eq 7 ]; then
    export PYMALLOC_SUFFIX=m
fi


# Location of the workspace directory (root)
export WORKSPACE_DIR=$1

# Location of external dependencies directory
export EXTERNAL_DEPENDENCIES_DIR=$WORKSPACE_DIR/external_dependencies

# Location of Qt build directory (in external dependencies)
export QTPATH=$EXTERNAL_DEPENDENCIES_DIR/qt_$QTVERSION

if [[ "$OS" == "centos7" ]]; then
    # Location of liblang directory (in external dependencies)
    # Qt for Python will look for this environment variable.
    # Under RHEL8, PySide2 should be able to find LLVM from the path.
    export CLANG_INSTALL_DIR=$EXTERNAL_DEPENDENCIES_DIR/libclang

    # Location of CMake directory (in external dependencies)
    # Latest CMake version in CentOS 7.6 is 2.8.x.x, but PySide2 requires a minimum of CMake 3.1
    export PATH=$EXTERNAL_DEPENDENCIES_DIR/cmake-3.13.3-Linux-x86_64/bin:$PATH
fi

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

# Get the number of processors available to build PySide2
export NUMBER_OF_PROCESSORS=`cat /proc/cpuinfo | grep processor | wc -l`


for BUILDTYPE in release debug;
do
    if [ "$BUILDTYPE" == "debug" ]; then
        export BUILDTYPE_STR="Debug"
        export PYTHON_EXE=$PYTHONDEXE
        export EXTRA_SETUP_PY_OPTS="--debug"
        export DEBUG_SUFFIX=d
    else
        export BUILDTYPE_STR="Release"
        export PYTHON_EXE=$PYTHONEXE
        export EXTRA_SETUP_PY_OPTS=""
        export DEBUG_SUFFIX=
    fi

    # By default, the pyside2-uic and pyside2-rcc wrappers are installed in the Python directory during the install step.
    # Using the --prefix option, we specify a different location where to output the files, which makes it easier to copy 
    # the wrappers in the /bin folder when packaging.
    export PREFIX_DIR_BUILDTYPE="${PREFIX_DIR}/${BUILDTYPE}"
    mkdir -p "$PREFIX_DIR_BUILDTYPE"

    # Location where the built wheels will be outputted
    # To be able to use pyside2-uic.exe and pyside2-rcc.exe, we need the metadata from the .dist-info folders,
    # which can be obtained by unpacking the wheels.
    export DIST_DIR_BUILDTYPE="${DIST_DIR}/${BUILDTYPE}"
    mkdir -p "$DIST_DIR_BUILDTYPE"

    # Ensure that pip and its required modules are installed for Python 3 (release version)
    $PYTHON_EXE -m ensurepip
    $PYTHON_EXE -m pip install --upgrade pip

    # Now install all required Python modules for building from pyside-setup's requirements.txt file.
    $PYTHON_EXE -m pip install -r requirements.txt
    $PYTHON_EXE -m pip install packaging

    # Build PySide2
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
    export WHEEL_SUFFIX=${PYSIDEVERSION}-${QTVERSION}-cp${PYTHONVERSION_AB}-cp${PYTHONVERSION_AB}
    if [ $PYTHONVERSION_A -eq 3 ]; then
        export WHEEL_SUFFIX=${WHEEL_SUFFIX}${DEBUG_SUFFIX}${PYMALLOC_SUFFIX}-linux_x86_64
    else
        export WHEEL_SUFFIX=${WHEEL_SUFFIX}${PYMALLOC_SUFFIX}u-manylinux1_x86_64
    fi

    export PYSIDE2_WHEEL=PySide2-${WHEEL_SUFFIX}.whl
    export SHIBOKEN2_WHEEL=shiboken2-${WHEEL_SUFFIX}.whl
    export SHIBOKEN2_GEN_WHEEL=shiboken2_generator-${WHEEL_SUFFIX}.whl

    $PYTHON_EXE -m wheel unpack $DIST_DIR_BUILDTYPE/$PYSIDE2_WHEEL --dest=$DIST_DIR_BUILDTYPE
    $PYTHON_EXE -m wheel unpack $DIST_DIR_BUILDTYPE/$SHIBOKEN2_WHEEL --dest=$DIST_DIR_BUILDTYPE
    $PYTHON_EXE -m wheel unpack $DIST_DIR_BUILDTYPE/$SHIBOKEN2_GEN_WHEEL --dest=$DIST_DIR_BUILDTYPE
done
