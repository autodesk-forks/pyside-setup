#!/usr/bin/env bash

set -e # Terminate with failure if any command returns nonzero
set -u # Terminate with failure any time an undefined variable is expanded

SCRIPT_DIR="$(cd -P "$(dirname "$BASH_SOURCE")" >/dev/null 2>&1 && pwd)"

echo -n "Start timestamp: "; date

if [[ ! -f README.pyside6.md ]]; then
    echo >&2 "Please execute from the root of the pyside-setup repository."
    exit 1
fi

# Parameter 1 - Absolute path to workspace directory
if [[ $# -eq 0 ]]; then
    echo >&2 "Need to pass workspace directory to the script"
    exit 1
fi

set +u

isMacOS=0
isLinux=0
isWin=0
DISTRO=""
case $OSTYPE in
  darwin*)
    isMacOS=1
    ;;
  linux*)
    isLinux=1
    # Check for OS version in the same way that Jenkinsfile does.
    distro=$(hostnamectl | awk '/Operating System/ { print $3 }')
    if [[ "$distro" =~ "CentOS" ]]; then
        DISTRO="centos7"
    else
        # Assuming RHEL8
        DISTRO="rhel"
    fi
    ;;
  msys*|cygwin*)
    isWin=1
    echo >&2 "error: Windows builds using this script is not supported yet"
    # Need a way to source vcvarsall.
    exit 1
    ;;
  *)
    echo >&2 "error: running on unknown OS"
    exit 1
esac

# Environment Variable - QTVERSION - Version of Qt used to build PySide6
if [[ -z "${QTVERSION}" ]]; then
    echo >&2 "QTVERSION is undefined. Example: export QTVERSION=6.2.3"
    exit 1
else
    echo "QTVERSION=${QTVERSION}"
fi

# Environment Variable - PYTHONVERSION - Version of Python for which PySide6 is built
if [[ -z "${PYTHONVERSION}" ]]; then
    echo >&2 "PYTHONVERSION is undefined. Example: export PYTHONVERSION=3.9.7"
    exit 1
fi
set -u
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
if [[ ! "$PYTHONVERSION" =~ (3\.10\.6|3\.11\.[0-9]*) ]]; then
    # We expect the python version to be 3.10.6, or 3.11.x
    # right now. It will change in the future, and at that time this
    # check should be updated to reflect the newly supported python
    # versions.
    echo >&2 "Expecting Python 3.10.6, or 3.11.x. aborting."
    echo >&2 "Example: export PYTHONVERSION=3.11.4"
    exit 1
fi

set +u
if [[ $isMacOS -eq 1 ]]; then
    # On macOS we do not use a debug python.
    export PYTHONDEXE=$PYTHONEXE
fi
for pythonexe in "${PYTHONEXE}" "${PYTHONDEXE}"; do
    pythonexe_varname="PYTHONEXE"
    pythonconfig="RelWithDebInfo"
    if [[ "$pythonexe" == "$PYTHONDEXE" && "$PYTHONEXE" != "$PYTHONDEXE" ]]; then
        pythonexe_varname="PYTHONDEXE"
        pythonconfig="Debug"
    fi

    # Make sure the user has passed in a python executable to use
    if [[ -z "$pythonexe" || ! -e "$pythonexe" ]]; then
        if [[ -z "$pythonexe" ]]; then echo -n "${pythonexe_varname} is undefined. ";
        elif [[ ! -e "$pythonexe" ]]; then echo -n "${pythonexe} doesn't exist. ";
        elif [[ ! -x "$pythonexe" ]]; then echo -n "${pythonexe} isn't executable. "; fi
        echo "Example: export ${pythonexe_varname}=$1/external_dependencies/cpython/3.9.5/${pythonconfig}/bin/python"
        exit 1
    else
        eval export $pythonexe_varname=$(cd $(dirname $pythonexe); pwd)/$(basename $pythonexe)
        eval pythonexe=\$$pythonexe_varname
        echo "${pythonexe_varname}=${pythonexe}"
    fi

    pythonexe_version=$($pythonexe -c "import sys; v=sys.version_info; print('{}.{}.{}'.format(v.major, v.minor, v.micro))")
    if [[ ! "$pythonexe_version" == "$PYTHONVERSION" ]]; then
        echo >&2 "Expecting Python ${PYTHONVERSION}, but the python executable ${pythonexe} is ${pythonexe_version}. aborting."
        exit 1
    fi
done

# Environment Variable - PYSIDEVERSION - Version of PySide6 built
if [[ -z "${PYSIDEVERSION}" || "${PYSIDEVERSION}" == "PREFLIGHT" ]]; then
    # Figure out PYSIDEVERSION from the codebase.
    export PYSIDEVERSION=$($PYTHONEXE $SCRIPT_DIR/fetch-qt-version.py)
fi
if [[ ! ${PYSIDEVERSION} =~ ^[0-9]{1,2}\.[0-9]{1,3}\.[0-9]{1,3}(\.[1-9])?([ab][0-9])?$ ]]; then
    echo "PYSIDEVERSION is invalid. It should be a version number. Example: export PYSIDEVERSION=6.2.3"
    exit 1
fi
echo "PYSIDEVERSION=${PYSIDEVERSION}"
set -u

# Python 2.7.X and 3.7.X artifacts had files with the pymalloc suffix
# Since we do not support those with PySide6, no suffix is used.
# This variable is still present just in case a future python release
# used has a pymalloc suffix.
export PYMALLOC_SUFFIX=

# Location of the workspace directory (root)
export WORKSPACE_DIR=$(cd $1; pwd)

# Location of external dependencies directory
export EXTERNAL_DEPENDENCIES_DIR=$WORKSPACE_DIR/external_dependencies

# Location of Qt build directory (in external dependencies)
export QTPATH=$EXTERNAL_DEPENDENCIES_DIR/qt_$QTVERSION

if [[ $isLinux -eq 1 ]]; then
    # Location of libclang directory (in external dependencies)
    # Qt for Python will look for this environment variable.
    export CLANG_INSTALL_DIR=$EXTERNAL_DEPENDENCIES_DIR/libclang

    # Location of CMake directory (in external dependencies)
    # Platform cmake is probably good enough, but just in case, we will use an
    # artifact.
    export PATH=$EXTERNAL_DEPENDENCIES_DIR/cmake-3.22.1-linux-x86_64/bin:$PATH
elif [[ $isMacOS -eq 1 ]]; then
    # Location of libclang directory (in external dependencies)
    export CLANG_INSTALL_DIR=$EXTERNAL_DEPENDENCIES_DIR/libclang

    # Platform cmake is good enough.
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

# Get the number of processors available to build PySide6
if [[ $isMacOS -eq 1 ]]; then
    export NUMBER_OF_PROCESSORS=`sysctl -n hw.ncpu`
elif [[ $isLinux -eq 1 ]]; then
    export NUMBER_OF_PROCESSORS=`cat /proc/cpuinfo | grep processor | wc -l`
fi
echo "NUMBER_OF_PROCESSORS=$NUMBER_OF_PROCESSORS"

for BUILDTYPE in release debug;
do
    echo "Building $BUILDTYPE..."
    export DEBUG_SUFFIX=
    if [ "$BUILDTYPE" == "debug" ]; then
        export BUILDTYPE_STR="Debug"
        export PYTHON_EXE=$PYTHONDEXE
        export EXTRA_SETUP_PY_OPTS="--debug"
        if [[ $isLinux -eq 1 ]]; then
            export DEBUG_SUFFIX=d
        fi
    else
        export BUILDTYPE_STR="Release"
        export PYTHON_EXE=$PYTHONEXE
        export EXTRA_SETUP_PY_OPTS=""
    fi

    if [[ $isMacOS -eq 1 ]]; then
        # No need to set --macos-deployment-target=11.0, as Qt was already built
        # with 11 as minimum deployment target
        export EXTRA_SETUP_PY_OPTS="$EXTRA_SETUP_PY_OPTS --macos-arch='x86_64;arm64'"
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

    # Ensure that pip and its required modules are installed for Python 3 (release version)
    set -x
    $PYTHON_EXE -m ensurepip
    $PYTHON_EXE -m pip install --upgrade pip
    set +x

    # Now install all required Python modules for building from pyside-setup's requirements.txt file.
    set -x
    $PYTHON_EXE -m pip install -r requirements.txt
    $PYTHON_EXE -m pip install packaging
    set +x

    # Build PySide6
    set -x
    $PYTHON_EXE setup.py bdist_wheel --qtpaths=$QTPATH/bin/qtpaths --ignore-git --parallel=$NUMBER_OF_PROCESSORS --dist-dir=$DIST_DIR_BUILDTYPE $EXTRA_SETUP_PY_OPTS
    export setup_ret=$?
    set +x
    if [ $setup_ret -eq 0 ]; then
        echo "==== Success ==== $BUILDTYPE_STR Build Wheel"
    else
        echo >&2 "**** Failed to build **** $BUILDTYPE_STR Build Wheel"
        exit 1
    fi
    echo -n "End ${BUILDTYPE} python setup.py bdist_wheel timestamp: "; date

    # Unpack the wheels
    # export WHEEL_SUFFIX=${PYSIDEVERSION}-${QTVERSION}-cp${PYTHONVERSION_AB}-cp${PYTHONVERSION_AB}${DEBUG_SUFFIX}${PYMALLOC_SUFFIX}
    # if [[ $isMacOS -eq 1 ]]; then
    #     export WHEEL_SUFFIX=${WHEEL_SUFFIX}-macosx_11_0_universal2
    # elif [[ $isLinux -eq 1 ]]; then
    #     export WHEEL_SUFFIX=${WHEEL_SUFFIX}-linux_x86_64
    # fi

    # export PYSIDE6_WHEEL=PySide6-${WHEEL_SUFFIX}.whl
    # export SHIBOKEN6_WHEEL=shiboken6-${WHEEL_SUFFIX}.whl
    # export SHIBOKEN6_GEN_WHEEL=shiboken6_generator-${WHEEL_SUFFIX}.whl

    # set -x
    # $PYTHON_EXE -m wheel unpack "${DIST_DIR_BUILDTYPE}/${PYSIDE6_WHEEL}" --dest="${DIST_DIR_BUILDTYPE}"
    # $PYTHON_EXE -m wheel unpack "${DIST_DIR_BUILDTYPE}/${SHIBOKEN6_WHEEL}" --dest="${DIST_DIR_BUILDTYPE}"
    # $PYTHON_EXE -m wheel unpack "${DIST_DIR_BUILDTYPE}/${SHIBOKEN6_GEN_WHEEL}" --dest="${DIST_DIR_BUILDTYPE}"
    # set +x
    # echo -n "End ${BUILDTYPE} wheel unpack timestamp: "; date
done
echo -n "End timestamp: "; date
echo "==== Success ===="
