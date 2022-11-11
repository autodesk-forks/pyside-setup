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

    # Check if the user made a build, bail if not.
    if [[ ! -e "$BUILDTYPE_INSTALL_DIR" ]]; then
        echo "Couldn't find ${BUILDTYPE_INSTALL_DIR}. aborting."
        echo "Did you forget to make the build?"
        exit 1
    fi

    # Define the path to our install dir for the PySide6 install dir (bin, include, lib, share)
    export PYSIDE6_ROOT_DIR="${INSTALL_DIR}/${BUILD_DIRNAME}"

    # Copy the build (release, debug) to the installation directory
    echo "Copying the build (release, debug) to the installation directory ${PYSIDE6_ROOT_DIR}"
    cp -R "${BUILDTYPE_INSTALL_DIR}/" "$PYSIDE6_ROOT_DIR"

    # Workaround: Since the pyside6-uic and pyside6-rcc wrappers are not installed in the build directory, we need to copy them from
    # the --prefix directory into the artifact's /bin folder
    wrappers=$(ls ${PREFIX_DIR}/${BUILDTYPE}/bin/pyside6-* ${PREFIX_DIR}/${BUILDTYPE}/bin/shiboken6*)
    for wrapper in ${wrappers}
    do
        echo "Copying \"$wrapper\" to \"$PYSIDE6_ROOT_DIR/bin/\""
        cp "$wrapper" "$PYSIDE6_ROOT_DIR/bin/"

        # Replace interpreter path for relative path to mayapy
        echo "Updating $wrapper script's shebang line with regex $PATH_TO_MAYAPY_REGEX"
        sed -i -e "${PATH_TO_MAYAPY_REGEX}" "$PYSIDE6_ROOT_DIR/bin/$(basename $wrapper)"
    done

    # Copy the .dist-info metadata folders, since the pyside6-uic and pyside6-rcc wrappers rely on [console_scripts] entrypoints.
    for distfolder in PySide6 shiboken6 shiboken6_generator
    do
        echo "Copying $distfolder-PYSIDEVERSION.dist-info to .../site-packages"
        cp -R "$DIST_DIR/$BUILDTYPE/$distfolder-$PYSIDEVERSION/$distfolder-$PYSIDEVERSION.dist-info" "$PYSIDE6_ROOT_DIR/lib/python$PYTHONVERSION_AdotB/site-packages/$distfolder-$PYSIDEVERSION.dist-info"

        echo "Renaming $distfolder-PYSIDEVERSION.dist-info/RECORD so package cannot be pip uninstalled"
        mv "$PYSIDE6_ROOT_DIR/lib/python$PYTHONVERSION_AdotB/site-packages/$distfolder-$PYSIDEVERSION.dist-info/RECORD" "$PYSIDE6_ROOT_DIR/lib/python$PYTHONVERSION_AdotB/site-packages/$distfolder-$PYSIDEVERSION.dist-info/RECORD-DONOTUNINSTALL"
    done

    # Link uic and rcc executable files into site-packages/PySide6, since it is the first search location for pyside6-uic that is used by loadUiType.
    for sitepackagesfile in rcc uic
    do
        ln -s "../../../../bin/${sitepackagesfile}" "${PYSIDE6_ROOT_DIR}/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide6/$sitepackagesfile"
    done

    # Copy the 'scripts' PySide6 folder manually, since the pyside6-uic and
    # pyside6-rcc wrappers invoke pyside_tool.py through [console_scripts]
    # entrypoints.
    echo "Copying site-packages/PySide6/scripts from $PREFIX_DIR to $PYSIDE6_ROOT_DIR"
    cp -R "$PREFIX_DIR/$BUILDTYPE/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide6/scripts" "${PYSIDE6_ROOT_DIR}/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide6/"

    # Workaround: Until the issue is addressed within PySide6 build scripts, we manually copy the 'support' PySide6 submodule
    # into the build to prevent the "__feature__ could not be imported" error.
    echo "Copying site-packages/PySide6/support from $PREFIX_DIR to $PYSIDE6_ROOT_DIR"
    cp -R "$PREFIX_DIR/$BUILDTYPE/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide6/support" "${PYSIDE6_ROOT_DIR}/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide6/"

    # Delete __pycache folders
    echo "Deleting __pycache__ folders from install"
    find "${PYSIDE6_ROOT_DIR}/lib/python${PYTHONVERSION_AdotB}/site-packages/" -type d -name "__pycache__" -exec rm -r {} +

    echo "Changing RPATHs of tools (${BUILDTYPE})"
    exe_format="ELF"
    if [[ $isMacOS -eq 1 ]]; then
        exe_format="Mach-O"
    fi
    binfilepaths=$(find "$PYSIDE6_ROOT_DIR/bin" -type f -exec sh -c "file {} \
               | grep -i ': ${exe_format}' > /dev/null 2>&1" \; -print)
    for binfilepath in ${binfilepaths}
    do
        # Just skip over the Assistant, Linguist and Designer - we're not using
        # them, and the existing rpaths are different.
        excludelist="Assistant Linguist Designer"
        if `in_list "$excludelist" "$(basename $binfilepath)"`; then
            echo >&2 "Skipping $(basename $binfilepath) RPATH change"
            continue;
        fi

        if [[ $isLinux -eq 1 ]]; then
            set +e
            patchelf --set-rpath '$ORIGIN:$ORIGIN/../lib' "$binfilepath"
            rpath_tool_ret=$?
            set -e
        elif [[ $isMacOS -eq 1 ]]; then
            set +e
            install_name_tool -delete_rpath '@loader_path/../lib' "$binfilepath"
            rpath_tool_ret=$?
            if [ $rpath_tool_ret -eq 0 ]; then
                install_name_tool -add_rpath '@loader_path/../MacOS' "$binfilepath"
                rpath_tool_ret=$?
            fi
            set -e
        fi

        if [[ $rpath_tool_ret -ne 0 ]]; then
            echo >&2 "**** Error: Failed setting rpath. ****"
            if [[ $isLinux -eq 1 ]]; then
                echo "RPATH dump for ${binfilepath}:"
                readelf -d "$binfilepath" | grep -i "runpath"
            elif [[ $isMacOS -eq 1 ]]; then
                echo "otool -l dump for ${binfilepath}:"
                otool -l "$binfilepath"
            fi
            exit 1
        fi
    done

    if [[ $isLinux -eq 1 ]]; then
        function set_rpath() {
            rpath=$1
            filepath=$2

            set +e
            patchelf --set-rpath "$1" "$2"
            if [[ $? -ne 0 ]]; then
                echo >&2 "**** Error: Failed setting rpath. ****"
                echo "RPATH dump for ${filepath}:"
                readelf -d "$filepath" | grep -i "runpath"
                exit 1
            fi
            set -e
        }

        echo "Changing RPATHs of libs (Linux only) (${BUILDTYPE})"
        export DEBUG_SUFFIX=
        if [[ "$BUILDTYPE" == "debug" ]]; then
            export DEBUG_SUFFIX=d
        fi

        for libfile in pyside6 pyside6qml shiboken6
        do
            set_rpath '$ORIGIN:$ORIGIN/../lib' \
                "${PYSIDE6_ROOT_DIR}/lib/lib${libfile}.abi3.so.${PYSIDEVERSION_AdotBdotC}"
        done

        for sitepackagesfile in uic rcc
        do
            set_rpath '$ORIGIN:$ORIGIN/../../../../lib' \
                "$PYSIDE6_ROOT_DIR/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide6/$sitepackagesfile"
        done

        set_rpath '$ORIGIN:$ORIGIN/../../../../lib' \
                "$PYSIDE6_ROOT_DIR/lib/python${PYTHONVERSION_AdotB}/site-packages/shiboken6/Shiboken.abi3.so"

        qtmodules=$(ls "$PYSIDE6_ROOT_DIR/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide6"/Qt*.so | sed -e 's/^.*\/PySide6\/\(Qt[^.]*\)\..*$/\1/')
        for qtmodule in ${qtmodules}
        do
            set_rpath '$ORIGIN:$ORIGIN/../../../../lib' \
                "$PYSIDE6_ROOT_DIR/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide6/$qtmodule.abi3.so"
        done
    fi
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
