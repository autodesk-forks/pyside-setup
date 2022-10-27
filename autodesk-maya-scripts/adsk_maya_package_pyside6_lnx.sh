#!/usr/bin/env bash

set -e # Terminate with failure if any command returns nonzero
set -u # Terminate with failure any time an undefined variable is expanded

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

# Location of the workspace directory (root)
export WORKSPACE_DIR=$1
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

# Check for patchelf
export PATCHELF=patchelf
set +e
$PATCHELF --version
if [[ $? -ne 0 ]]; then
    echo >&2 "Couldn't find patchelf. aborting."
    exit 1
fi
set -e

# Python 2.7.X and 3.7.X artifacts had files with the pymalloc suffix
# Since we do not support those with PySide6, no suffix is used.
# This variable is still present just in case a future python release
# used has a pymalloc suffix.
export PYMALLOC_SUFFIX=


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
    if [ "$BUILDTYPE" == "debug" ]; then
        export BT_PREFIX=dp
    fi
    # the build directory name we are looking for is in the forms:
    # build/qfpdp-py3.9-qt6.3.1-64bit-debug/install
    # build/qfp-py3.9-qt6.3.1-64bit-release/install
    export BUILD_DIRNAME="qfp${BT_PREFIX}-py${PYTHONVERSION_AdotB}-qt${QTVERSION}-64bit-${BUILDTYPE}"
    export BUILDTYPE_INSTALL_DIR=build/${BUILD_DIRNAME}/install

    # Check if the user made a build, bail if not.
    if [[ ! -e "$BUILDTYPE_INSTALL_DIR" ]]; then
        echo "Couldn't find ${BUILDTYPE_INSTALL_DIR}. aborting."
        echo "Did you forget to make the build?"
        exit 1
    fi

    # Define the path to our install dir for the PySide6 install dir (bin, include, lib, share)
    export PYSIDE6_ROOT_DIR="${INSTALL_DIR}/${BUILD_DIRNAME}"

    # Copy the build (release, debug) to the installation directory
    cp -R "${BUILDTYPE_INSTALL_DIR}/" "$PYSIDE6_ROOT_DIR"

    # Workaround: Since the pyside6-uic and pyside6-rcc wrappers are not installed in the build directory, we need to copy them from
    # the --prefix directory into the artifact's /bin folder
    wrappers=$(ls ${PREFIX_DIR}/${BUILDTYPE}/bin/pyside6-* ${PREFIX_DIR}/${BUILDTYPE}/bin/shiboken6*)
    for wrapper in ${wrappers} ; do
        cp "$wrapper" "$PYSIDE6_ROOT_DIR/bin/"

        # Replace interpreter path for relative path to mayapy
        sed -i -e "${PATH_TO_MAYAPY_REGEX}" "$PYSIDE6_ROOT_DIR/bin/$(basename $wrapper)"
    done

    # Copy the .dist-info metadata folders, since the pyside6-uic and pyside6-rcc wrappers rely on [console_scripts] entrypoints.
    for distfolder in PySide6 shiboken6 shiboken6_generator
    do
        cp -R "$DIST_DIR/$BUILDTYPE/$distfolder-$PYSIDEVERSION/$distfolder-$PYSIDEVERSION.dist-info" "$PYSIDE6_ROOT_DIR/lib/python$PYTHONVERSION_AdotB/site-packages/$distfolder-$PYSIDEVERSION.dist-info"
        mv "$PYSIDE6_ROOT_DIR/lib/python$PYTHONVERSION_AdotB/site-packages/$distfolder-$PYSIDEVERSION.dist-info/RECORD" "$PYSIDE6_ROOT_DIR/lib/python$PYTHONVERSION_AdotB/site-packages/$distfolder-$PYSIDEVERSION.dist-info/RECORD-DONOTUNINSTALL"
    done

    # Copy uic and rcc executable files into site-packages/PySide6, since it is the first search location for loadUiType.
    for sitepackagesfile in rcc uic
    do
        ln -s "../../../../bin/${sitepackagesfile}" "${PYSIDE6_ROOT_DIR}/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide6/$sitepackagesfile"
    done

    # Copy the 'scripts' PySide6 sudmodules folder manually, since the pyside6-uic and pyside6-rcc wrappers invoke
    # pyside_tool.py through [console_scripts] entrypoints.
    cp -R "$PREFIX_DIR/$BUILDTYPE/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide6/scripts" "${PYSIDE6_ROOT_DIR}/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide6/"

    # Workaround: Until the issue is addressed within PySide6 build scripts, we manually copy the 'support' PySide6 submodule
    # into the build to prevent the "__feature__ could not be imported" error.
    cp -R "$PREFIX_DIR/$BUILDTYPE/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide6/support" "${PYSIDE6_ROOT_DIR}/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide6/"

    # Delete __pycache folders
    find "${PYSIDE6_ROOT_DIR}/lib/python${PYTHONVERSION_AdotB}/site-packages/" -type d -name "__pycache__" -exec rm -r {} +

    echo "Changing RUNPATHs (Python 3 - ${BUILDTYPE})"
    export DEBUG_SUFFIX=
    if [[ "$BUILDTYPE" == "debug" ]]; then
        export DEBUG_SUFFIX=d
    fi

    binfiles=$(find "$PYSIDE6_ROOT_DIR/bin" -type f -exec sh -c "file {} | grep -Pi ': elf' > /dev/null 2>&1" \; -print)
    for binfile in ${binfiles}
    do
        export binfilepath="$PYSIDE6_ROOT_DIR/bin/$binfile"
        if [[ -e "$binfilepath" ]]; then
            $PATCHELF --set-rpath '$ORIGIN:$ORIGIN/../lib' "$binfilepath"
        fi
    done

    for libfile in pyside6 pyside6qml shiboken6
    do
        $PATCHELF --set-rpath '$ORIGIN:$ORIGIN/../lib' "$PYSIDE6_ROOT_DIR/lib/lib$libfile.cpython-${PYTHONVERSION_AB}${DEBUG_SUFFIX}${PYMALLOC_SUFFIX}-x86_64-linux-gnu.so.${PYSIDEVERSION}"
    done

    for sitepackagesfile in uic rcc
    do
        $PATCHELF --set-rpath '$ORIGIN:$ORIGIN/../../../../lib' "$PYSIDE6_ROOT_DIR/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide6/$sitepackagesfile"
    done

    $PATCHELF --set-rpath '$ORIGIN:$ORIGIN/../../../../lib' "$PYSIDE6_ROOT_DIR/lib/python${PYTHONVERSION_AdotB}/site-packages/shiboken6/Shiboken.cpython-${PYTHONVERSION_AB}${DEBUG_SUFFIX}${PYMALLOC_SUFFIX}-x86_64-linux-gnu.so"

    qtmodules=$(ls "$PYSIDE6_ROOT_DIR/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide6"/Qt*.so | sed -e 's/^.*\/PySide6\/\(Qt[^.]*\)\..*$/\1/')
    for qtmodule in ${qtmodules}
    do
        $PATCHELF --set-rpath '$ORIGIN:$ORIGIN/../../../../lib' "$PYSIDE6_ROOT_DIR/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide6/$qtmodule.cpython-${PYTHONVERSION_AB}${DEBUG_SUFFIX}${PYMALLOC_SUFFIX}-x86_64-linux-gnu.so"
    done
done
echo "==== Finished Assembling ===="

if [[ $COMPRESS -ne 0 ]]; then
    buildID=$(date +%Y%m%d%H%M)
    gitCommitShort=$(git rev-parse HEAD | cut -c1-8)
    cd "$INSTALL_DIR"
    outdir=$(realpath "../out")
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
