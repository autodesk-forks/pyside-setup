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

if [[ ! -f README.pyside2.md ]] ; then
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
if [[ -z "${PYSIDEVERSION}" ]]; then
    echo >&2 "PYSIDEVERSION is undefined. Example: export PYSIDEVERSION=5.15.2"
    exit 1
else
    echo "PYSIDEVERSION=${PYSIDEVERSION}"
fi

# Environment Variable - PYTHONVERSION - Version of Python for which PySide2 is built
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
if [[ ! "$PYTHONVERSION" =~ (2\.7\.1[0-9]|3\.9\.5|3\.9\.7|3\.10\.[0-9]*) ]]; then
    # We expect the python version to be 2.7.10+, 3.9.5, 3.9.7, or 3.10.x
    # right now. It will change in the future, and at that time this
    # check should be updated to reflect the newly supported python
    # versions.
    echo >&2 "Expecting Python 2.7.1?, 3.9.5, 3.9.7, or 3.10.x. aborting."
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

# Python 2.7.X and 3.7.X artifacts have files with the pymalloc suffix
export PYMALLOC_SUFFIX=
if [ $PYTHONVERSION_B -eq 7 ]; then
    export PYMALLOC_SUFFIX=m
fi


# Location of the workspace directory (root)
export WORKSPACE_DIR=$1

# Location of the install directory within the workspace (where the builds will be located)
export INSTALL_DIR="${WORKSPACE_DIR}/install"

# Location of the pyside2-uic and pyside2-rcc wrappers (determined by the --prefix option in the build script)
export PREFIX_DIR="${WORKSPACE_DIR}/build"

# Location of the pyside2-uic and pyside2-rcc .dist-info metadata folders (determined by the --dist-dir option in the build script)
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

# Determine if it is a Python 2 or Python 3 build
export PATH_TO_MAYAPY_REGEX='1s/.*/\#\!\/usr\/bin\/env mayapy2/'
if [ $PYTHONVERSION_A -eq 3 ]; then
    export PATH_TO_MAYAPY_REGEX='1s/.*/\#\!\/usr\/bin\/env mayapy/'
fi


# Write PySide2 build information to a "pyside2_version" file
# instead of encoding the pyside version number in a directory name
cat <<EOF >"${INSTALL_DIR}/pyside2_version"
pyside2 $PYSIDEVERSION
qt $QTVERSION
python version $PYTHONVERSION
EOF


for BUILDTYPE in release debug;
do
    # Define folder names
    # Python 2: pyside2_install, pyside2d_install
    # Python 3: pyside3_install, pyside3dp_install
    export BUILDTYPE_SUFFIX=
    if [ "$BUILDTYPE" == "debug" ]; then
        if [ $PYTHONVERSION_A -eq 3 ]; then
            export BUILDTYPE_SUFFIX=dp
        else
            export BUILDTYPE_SUFFIX=d
        fi
    fi
    export BUILDTYPE_INSTALL_DIR=pyside${PYTHONVERSION_A}${BUILDTYPE_SUFFIX}_install

    if [[ -e "$BUILDTYPE_INSTALL_DIR" ]]; then
        # Copy the build (release, debug) to the installation directory
        cp -R "$BUILDTYPE_INSTALL_DIR" "$INSTALL_DIR/"

        # Define the path to the directory of the PySide2 build (bin, include, lib, share) in the installation directory
        export PYSIDE2_ROOT_DIR="${INSTALL_DIR}/${BUILDTYPE_INSTALL_DIR}/py${PYTHONVERSION_AdotB}-qt${QTVERSION}-64bit-${BUILDTYPE}"

        # Workaround: Since the pyside2-uic and pyside2-rcc wrappers are not installed in the build directory, we need to copy them from
        # the --prefix directory into the artifact's /bin folder
        for wrapper in pyside2-rcc pyside2-uic
        do
            cp "$PREFIX_DIR/$BUILDTYPE/bin/$wrapper" "$PYSIDE2_ROOT_DIR/bin/"

            # Replace interpreter path for relative path to mayapy
            sed -i -e "${PATH_TO_MAYAPY_REGEX}" "$PYSIDE2_ROOT_DIR/bin/$wrapper"
        done

        # Copy the .dist-info metadata folders, since the pyside2-uic and pyside2-rcc wrappers rely on [console_scripts] entrypoints.
        for distfolder in PySide2 shiboken2 shiboken2_generator
        do
            cp -R "$DIST_DIR/$BUILDTYPE/$distfolder-$PYSIDEVERSION/$distfolder-$PYSIDEVERSION.dist-info" "$PYSIDE2_ROOT_DIR/lib/python$PYTHONVERSION_AdotB/site-packages/$distfolder-$PYSIDEVERSION.dist-info"
            mv "$PYSIDE2_ROOT_DIR/lib/python$PYTHONVERSION_AdotB/site-packages/$distfolder-$PYSIDEVERSION.dist-info/RECORD" "$PYSIDE2_ROOT_DIR/lib/python$PYTHONVERSION_AdotB/site-packages/$distfolder-$PYSIDEVERSION.dist-info/RECORD-DONOTUNINSTALL"
        done

        # Copy uic and rcc executable files into site-packages/PySide2, since it is the first search location for loadUiType.
        for sitepackagesfile in rcc uic
        do
            cp "$PREFIX_DIR/$BUILDTYPE/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide2/$sitepackagesfile" "${PYSIDE2_ROOT_DIR}/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide2/$sitepackagesfile"
        done

        # Copy the 'scripts' PySide2 sudmodules folder manually, since the pyside2-uic and pyside2-rcc wrappers invoke
        # pyside_tool.py through [console_scripts] entrypoints.
        cp -R "$PREFIX_DIR/$BUILDTYPE/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide2/scripts" "${PYSIDE2_ROOT_DIR}/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide2/"

        # Workaround: Until the issue is addressed within PySide2 build scripts, we manually copy the 'support' PySide2 submodule
        # into the build to prevent the "__feature__ could not be imported" error.
        cp -R "$PREFIX_DIR/$BUILDTYPE/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide2/support" "${PYSIDE2_ROOT_DIR}/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide2/"

        # Delete __pycache folders
        find "${PYSIDE2_ROOT_DIR}/lib/python${PYTHONVERSION_AdotB}/site-packages/" -type d -name "__pycache__" -exec rm -r {} +

        if [ $PYTHONVERSION_A -eq 3 ]; then
            echo "Changing RUNPATHs (Python 3 - ${BUILDTYPE})"
            export DEBUG_SUFFIX=
            if [[ "$BUILDTYPE" == "debug" ]]; then
                export DEBUG_SUFFIX=d
            fi

            for binfile in pyside2-lupdate uic rcc shiboken2
            do
                export binfilepath="$PYSIDE2_ROOT_DIR/bin/$binfile"
                if [[ -e "$binfilepath" ]]; then
                    $PATCHELF --set-rpath '$ORIGIN:$ORIGIN/../lib' "$binfilepath"
                fi
            done

            for libfile in pyside2 shiboken2
            do
                $PATCHELF --set-rpath '$ORIGIN:$ORIGIN/../lib' "$PYSIDE2_ROOT_DIR/lib/lib$libfile.cpython-${PYTHONVERSION_AB}${DEBUG_SUFFIX}${PYMALLOC_SUFFIX}-x86_64-linux-gnu.so.${PYSIDEVERSION}"
            done

            for sitepackagesfile in uic rcc
            do
                $PATCHELF --set-rpath '$ORIGIN:$ORIGIN/../../../../lib' "$PYSIDE2_ROOT_DIR/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide2/$sitepackagesfile"
            done

            $PATCHELF --set-rpath '$ORIGIN:$ORIGIN/../../../../lib' "$PYSIDE2_ROOT_DIR/lib/python${PYTHONVERSION_AdotB}/site-packages/shiboken2/shiboken2.cpython-${PYTHONVERSION_AB}${DEBUG_SUFFIX}${PYMALLOC_SUFFIX}-x86_64-linux-gnu.so"

            for qtmodule in Qt3DAnimation Qt3DCore Qt3DExtras Qt3DInput Qt3DLogic Qt3DRender QtConcurrent QtCore QtGui QtHelp QtLocation QtMultimedia QtMultimediaWidgets QtNetwork QtOpenGL QtOpenGLFunctions QtPositioning QtPrintSupport QtQml QtQuick QtQuickWidgets QtRemoteObjects QtScxml QtSensors QtSql QtSvg QtTest QtTextToSpeech QtUiTools QtWebChannel QtWebEngineCore QtWebEngine QtWebEngineWidgets QtWebSockets QtWidgets QtX11Extras QtXml QtXmlPatterns
            do
                $PATCHELF --set-rpath '$ORIGIN:$ORIGIN/../../../../lib' "$PYSIDE2_ROOT_DIR/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide2/$qtmodule.cpython-${PYTHONVERSION_AB}${DEBUG_SUFFIX}${PYMALLOC_SUFFIX}-x86_64-linux-gnu.so"
            done
        else
            echo "Changing RUNPATHs (Python 2 - ${BUILDTYPE})"

            for binfile in pyside2-lupdate uic rcc shiboken2
            do
                export binfilepath="$PYSIDE2_ROOT_DIR/bin/$binfile"
                if [ -e "$binfilepath" ]; then
                    $PATCHELF --set-rpath '$ORIGIN:$ORIGIN/../lib' "$binfilepath"
                fi
            done

            for libfile in pyside2 shiboken2
            do
                $PATCHELF --set-rpath '$ORIGIN:$ORIGIN/../lib' "$PYSIDE2_ROOT_DIR/lib/lib$libfile-python${PYTHONVERSION_AdotB}.so.${PYSIDEVERSION}"
            done

            for sitepackagesfile in uic rcc
            do
                $PATCHELF --set-rpath '$ORIGIN:$ORIGIN/../../../../lib' "$PYSIDE2_ROOT_DIR/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide2/$sitepackagesfile"
            done

            $PATCHELF --set-rpath '$ORIGIN:$ORIGIN/../../../../lib' "$PYSIDE2_ROOT_DIR/lib/python${PYTHONVERSION_AdotB}/site-packages/shiboken2/shiboken2.so"

            for qtmodule in Qt3DAnimation Qt3DCore Qt3DExtras Qt3DInput Qt3DLogic Qt3DRender QtConcurrent QtCore QtGui QtHelp QtLocation QtMultimedia QtMultimediaWidgets QtNetwork QtOpenGL QtOpenGLFunctions QtPositioning QtPrintSupport QtQml QtQuick QtQuickWidgets QtRemoteObjects QtScxml QtSensors QtSql QtSvg QtTest QtTextToSpeech QtUiTools QtWebChannel QtWebEngineCore QtWebEngine QtWebEngineWidgets QtWebSockets QtWidgets QtX11Extras QtXml QtXmlPatterns
            do
                $PATCHELF --set-rpath '$ORIGIN:$ORIGIN/../../../../lib' "$PYSIDE2_ROOT_DIR/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide2/$qtmodule.so"
            done
        fi
    fi
done

if [[ $COMPRESS -ne 0 ]]; then
    buildID=$(date +%Y%m%d%H%M)
    gitCommitShort=$(git rev-parse HEAD | cut -c1-8)
    cd "$INSTALL_DIR"
    outdir=$(realpath "../out")
    tarballPath="${outdir}/${buildID}-${gitCommitShort}-Maya-PySide2-Linux.tar.gz"
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
fi

echo "==== Finished ===="
