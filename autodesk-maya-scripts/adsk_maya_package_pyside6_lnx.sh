#!/usr/bin/env bash

set -e # Terminate with failure if any command returns nonzero
set -u # Terminate with failure any time an undefined variable is expanded

function in_list() {
    local list="$1"
    local item="$2"
    if [[ $list =~ (^|[[:space:]])"$item"($|[[:space:]]) ]] ; then
        ret=0; else ret=1
    fi
    return $ret
}

COMPRESS=0
kept_args=()
for arg in "$@"; do
  case $arg in
    -z|--compress)
        if [[ $COMPRESS -eq 0 ]]; then
            echo >&2 "Compressing like Jenkinsfile Packaging does."
            COMPRESS=1
        fi
        shift
        ;;
    -*|--*)
        echo >&2 "Unknown option $arg"
        exit 1
        ;;
    *)
        kept_args+=($arg)
        ;;
  esac
done
set -- "${kept_args[@]}"

if [[ ! -f README.pyside6.md ]] ; then
    echo >&2 "Please execute from the root of the pyside-setup repository."
    exit 1
fi

# Parameter 1 - Absolute path to workspace directory
if [[ $# -eq 0 ]]; then
    echo >&2 "Need to pass workspace directory to the script."
    exit 1
fi

set +u

isMacOS=0
isLinux=0
isWin=0
case $OSTYPE in
  darwin*)
    isMacOS=1
    ;;
  linux*)
    isLinux=1
    ;;
  msys*|cygwin*)
    isWin=1
    echo >&2 "error: Windows builds using this script are not supported yet"
    # Need a way to source vcvarsall.
    exit 1
    ;;
  *)
    echo >&2 "error: running on unknown OS"
    exit 1
esac

# Environment Variable - QTVERSION - Version of Qt used to build PySide6
if [[ -z "${QTVERSION}" ]]; then
    echo >&2 "QTVERSION is undefined, please set. Example: export QTVERSION=6.2.3"
    exit 1
else
    echo "QTVERSION=${QTVERSION}"
fi

# Environment Variable - PYSIDEVERSION - Version of PySide6 built
if [[ -z "${PYSIDEVERSION}" ]]; then
    echo >&2 "PYSIDEVERSION is undefined, please set. Example: export PYSIDEVERSION=6.2.3"
    exit 1
else
    echo "PYSIDEVERSION=${PYSIDEVERSION}"
fi
# Strip off any alpha/beta version parts ("a1", "b1" suffix typically -
# e.g. the `a1` in 6.4.0a1
PYSIDEVERSION_ARRAY=($(echo $PYSIDEVERSION | sed -e 's/[ab][0-9]\+//' | tr "." "\n"))
PYSIDEVERSION_A=${PYSIDEVERSION_ARRAY[0]}
PYSIDEVERSION_B=${PYSIDEVERSION_ARRAY[1]}
PYSIDEVERSION_C=${PYSIDEVERSION_ARRAY[2]}
PYSIDEVERSION_AdotBdotC=${PYSIDEVERSION_A}.${PYSIDEVERSION_B}.${PYSIDEVERSION_C}


# Location of the workspace directory (root), made absolute so RPATHs can be detected properly.
export WORKSPACE_DIR=$(cd $1; pwd)
if [[ ! -d "$WORKSPACE_DIR" ]]; then
    echo >&2 "Invalid WORKSPACE_DIR ${WORKSPACE_DIR}. aborting."
    exit 1
fi

# Location of external dependencies directory
export EXTERNAL_DEPENDENCIES_DIR=$WORKSPACE_DIR/external_dependencies

# Environment Variable - PYTHONVERSION - Version of Python for which PySide6 is built
if [[ -z "$PYTHONVERSION" && -d $EXTERNAL_DEPENDENCIES_DIR/cpython ]]; then
    GUESSED_PYVER=$(ls -1 $EXTERNAL_DEPENDENCIES_DIR/cpython)
    read -p "Is python version $GUESSED_PYVER (y/N)? " -n 1 -t 5 query || true
    echo
    if [[ "$query" == "Y" || "$query" == "y" ]]; then
        PYTHONVERSION=$GUESSED_PYVER
    fi
fi

if [[ -z "$PYTHONVERSION" ]]; then
    echo >&2 "PYTHONVERSION is undefined. Example: export PYTHONVERSION=3.7.7"
    exit 1
else
    echo "PYTHONVERSION=${PYTHONVERSION}"
fi
set -u

# Extract MAJOR(A), MINOR(B), and REVISION(C) from PYTHONVERSION
PYTHONVERSION_ARRAY=($(echo $PYTHONVERSION | tr "." "\n"))
PYTHONVERSION_A=${PYTHONVERSION_ARRAY[0]}
PYTHONVERSION_B=${PYTHONVERSION_ARRAY[1]}
PYTHONVERSION_C=${PYTHONVERSION_ARRAY[2]}

# Define Python Version Shortcuts (AB and A.B)
PYTHONVERSION_AB=${PYTHONVERSION_A}${PYTHONVERSION_B}
PYTHONVERSION_AdotB=${PYTHONVERSION_A}.${PYTHONVERSION_B}

# Validate that the Python version given is within the accepted values
if [[ ! "$PYTHONVERSION" =~ (3\.9\.7|3\.10\.[0-9]*) ]]; then
    # We expect the python version to be 3.9.7, or 3.10.x
    # right now. It will change in the future, and at that time this
    # check should be updated to reflect the newly supported python
    # versions.
    echo >&2 "Expecting Python 3.9.7, or 3.10.x. aborting."
    echo >&2 "Example: export PYTHONVERSION=3.9.7"
    exit 1
fi

tools=""
if [[ $isLinux -eq 1 ]]; then
    tools="patchelf"
elif [[ $isMacOS -eq 1 ]]; then
    tools="install_name_tool otool"
fi
# Check for rpath tools
for rptool in $tools ; do
    # Check for ne 127 because install_name_tool does not have a noop
    # option. 127 is the shell's return code for executable not found.
    set +e
    $rptool --version
    if [[ $? -eq 127 ]]; then
        echo >&2 "Couldn't find ${rptool}. aborting."
        exit 1
    fi
    set -e
done


# Location of the install directory within the workspace (where the builds will be located)
export INSTALL_DIR="${WORKSPACE_DIR}/install"

# Location of the pyside6-uic and pyside6-rcc wrappers (determined by the --prefix option in the build script)
export PREFIX_DIR="${WORKSPACE_DIR}/build"

# Location of the pyside6-uic and pyside6-rcc .dist-info metadata folders (determined by the --dist-dir option in the build script)
export DIST_DIR="${WORKSPACE_DIR}/dist"

# Validate that PREFIX_DIR and DIST_DIR exist.

for dir in "$PREFIX_DIR" "$DIST_DIR"; do
    if [[ ! -d "$dir" ]]; then
        echo >&2 "$dir does not exist. aborting."
        exit 1
    fi
done

if [[ -e "$INSTALL_DIR" ]]; then
    echo >&2 "It looks like packaging already happened."
    echo >&2 "Please remove ${INSTALL_DIR} and try again. aborting."
    exit 1
fi

mkdir "$INSTALL_DIR"

export PATH_TO_MAYAPY_REGEX='1s/.*/\#\!\/usr\/bin\/env mayapy/'


# Write PySide6 build information to a "pyside6_version" file
# instead of encoding the pyside version number in a directory name
cat <<EOF >"${INSTALL_DIR}/pyside6_version"
PySide6 $PYSIDEVERSION
Qt $QTVERSION
Python version $PYTHONVERSION
EOF


for BUILDTYPE in release debug;
do
    echo "Packaging $BUILDTYPE..."
    # Define folder names
    export BT_PREFIX=
    if [[ "$BUILDTYPE" == "debug" && $isLinux -eq 1 ]]; then
        export BT_PREFIX=dp
    elif [[ "$BUILDTYPE" == "debug" ]]; then
        export BT_PREFIX=d
    fi
    # the build directory name we are looking for is in the forms:
    # build/qfpdp-py3.9-qt6.3.1-64bit-debug/install
    # build/qfp-py3.9-qt6.3.1-64bit-release/install
    export BUILD_DIRNAME="qfp${BT_PREFIX}-py${PYTHONVERSION_AdotB}-qt${QTVERSION}-64bit-${BUILDTYPE}"
    export BUILDTYPE_INSTALL_DIR=build/${BUILD_DIRNAME}/install
    export BUILDTYPE_DIST_DIR=${DIST_DIR}/${BUILDTYPE}

    # Check if the user made a build, bail if not.
    if [[ ! -e "$BUILDTYPE_INSTALL_DIR" ]]; then
        echo "Couldn't find ${BUILDTYPE_INSTALL_DIR}. aborting."
        echo "Did you forget to make the build?"
        exit 1
    fi

    # Define the path to our install dir for the PySide6 install dir (bin, include, lib, share)
    export PYSIDE6_ROOT_DIR="${INSTALL_DIR}/${BUILD_DIRNAME}"
    cp -R "${BUILDTYPE_DIST_DIR}/" "$PYSIDE6_ROOT_DIR"
done
echo "==== Finished Assembling ===="

if [[ $COMPRESS -ne 0 ]]; then
    packageDate=$(date +%Y-%m-%d-%H-%M)
    buildID=$(date +%Y%m%d%H%M)
    gitCommitShort=$(git rev-parse HEAD | cut -c1-8)
    cd "$INSTALL_DIR"
    outdir=$(cd ../out; pwd)
    tarballPath="${outdir}/${buildID}-${gitCommitShort}-MANUAL-Maya-PySide6-Linux.tar.gz"
    mkdir -p "$outdir"
    echo -n "Creating tarball $tarballPath"
    tar -czvf "$tarballPath" * | python -c "
import sys
for line in sys.stdin:
    sys.stdout.write('.')
    sys.stdout.flush()
print()"
    echo
    echo "Tarball $tarballPath created."
    echo "Upload this to artifactory under:"
    echo "    team-maya-generic/pyside6/$PYSIDEVERSION/Maya/Qt$QTVERSION/Python$PYTHONVERSION_AdotB/$packageDate"
fi

echo "==== Finished ===="
