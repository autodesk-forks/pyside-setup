# Exit bash script if return codes from commands are nonzero
set -e

if [ ! -e README.pyside2.md ] ; then
    echo "Pyside2 packaging script not in correct current directory"
    echo "ABORTING: Current directory incorrect."
    exit 1
fi

# Parameter 1 - Absolute path to workspace directory
if [ $# -eq 0 ]; then
    echo "Need to pass workspace directory to the script"
	exit 1
fi

# Environment Variable - QTVERSION - Version of Qt used to build PySide2
if [[ -z "$QTVERSION" ]]; then
	echo "QTVERSION is undefined. Example: export QTVERSION=5.15.2"
	exit 1
else
	echo "QTVERSION=$QTVERSION"
fi

# Environment Variable - PYSIDEVERSION - Version of PySide2 built
if [[ -z "$PYSIDEVERSION" ]]; then
	echo "PYSIDEVERSION is undefined. Example: export PYSIDEVERSION=5.15.2"
	exit 1
else
	echo "PYSIDEVERSION=$PYSIDEVERSION"
fi

# Location of the workspace directory (root), made absolute so RPATHs can be detected properly.
export WORKSPACE_DIR=$(python3 -c "import os,sys; print(os.path.abspath(sys.argv[1]))" $1)

# Exit bash script if the script expands variables that were never set.
set -u

# Location of the install directory within the workspace (where the builds will be located)
export INSTALL_DIR="$WORKSPACE_DIR/install"

# Location of the pyside2-uic and pyside2-rcc wrappers (determined by the --prefix option in the build script)
export PREFIX_DIR="$WORKSPACE_DIR/build"

# Location of the pyside2-uic and pyside2-rcc .dist-info metadata folders (determined by the --dist-dir option in the build script)
export DIST_DIR="$WORKSPACE_DIR/dist"

mkdir -p "$INSTALL_DIR"

# Determine if it is a Python 2 or Python 3 build
export PY_MAJORVER=2
export PATH_TO_MAYAPY_REGEX='1s/.*/\#\!\/usr\/bin\/env python2_unused_in_maya2022plus_on_macOS/'
if [ -e "pyside3_install" ]; then
    export PY_MAJORVER=3
    export PATH_TO_MAYAPY_REGEX='1s/.*/\#\!\/usr\/bin\/env mayapy/'
fi
echo "Built for Python v$PY_MAJORVER"



# Write PySide2 build information to a "pyside2_version" file 
# instead of encoding the pyside version number in a directory name
cat <<EOF >"$INSTALL_DIR/pyside2_version"
pyside2 $PYSIDEVERSION
qt $QTVERSION
python major version $PY_MAJORVER
EOF

# Copy, setup and package
for BUILDTYPE in release debug
do
    export DEBUG_d=""
	if [ "$BUILDTYPE" == "debug" ]; then
        export DEBUG_d="d"
    fi

    export BUILDTYPE_INSTALL_DIR="pyside${PY_MAJORVER}${DEBUG_d}_install"

    if [[ -e "$BUILDTYPE_INSTALL_DIR" ]]; then
        echo "Copying the build (release, debug) to the installation directory"
        cp -R "$BUILDTYPE_INSTALL_DIR" "$INSTALL_DIR/"

        # Define the path to the directory of the PySide2 build (bin, include, lib, share) in the installation directory
        export PYSIDE2_ROOT_DIR="$INSTALL_DIR/$BUILDTYPE_INSTALL_DIR/py${PY_MAJORVER}.7-qt${QTVERSION}-64bit-${BUILDTYPE}"

        # Workaround: Since the pyside2-uic and pyside2-rcc wrappers are not installed in the build directory, we need to copy them from
        # the --prefix directory into the artifact's /bin folder
        for wrapper in pyside2-rcc pyside2-uic
        do
            echo "Copying \"$PREFIX_DIR/$BUILDTYPE/bin/$wrapper\" to \"$PYSIDE2_ROOT_DIR/bin/\""
            cp "$PREFIX_DIR/$BUILDTYPE/bin/$wrapper" "$PYSIDE2_ROOT_DIR/bin/"

            # Replace interpreter path for relative path to mayapy
            echo "Updating $wrapper script's shebang line with regex $PATH_TO_MAYAPY_REGEX"
            sed -i -e "$PATH_TO_MAYAPY_REGEX" "$PYSIDE2_ROOT_DIR/bin/$wrapper"
        done

        # Copy the .dist-info metadata folders, since the pyside2-uic and pyside2-rcc wrappers rely on [console_scripts] entrypoints.
        for distfolder in PySide2 shiboken2 shiboken2_generator
        do
            echo "Copying $distfolder-PYSIDEVERSION.dist-info to .../site-packages"
            cp -R "$DIST_DIR/$BUILDTYPE/$distfolder-$PYSIDEVERSION/$distfolder-$PYSIDEVERSION.dist-info" "$PYSIDE2_ROOT_DIR/lib/python$PY_MAJORVER.7/site-packages/$distfolder-$PYSIDEVERSION.dist-info"
            echo "Renaming $distfolder-PYSIDEVERSION.dist-info/RECORD so package cannot be pip uninstalled"
            mv "$PYSIDE2_ROOT_DIR/lib/python$PY_MAJORVER.7/site-packages/$distfolder-$PYSIDEVERSION.dist-info/RECORD" "$PYSIDE2_ROOT_DIR/lib/python$PY_MAJORVER.7/site-packages/$distfolder-$PYSIDEVERSION.dist-info/RECORD-DONOTUNINSTALL"
        done

        # Copy uic and rcc executable files into site-packages/PySide2, since it is the first search location for pyside2-uic that is used by loadUiType.
        for sitepackagesfile in rcc uic
        do
            cp "$PREFIX_DIR/$BUILDTYPE/lib/python$PY_MAJORVER.7/site-packages/PySide2/$sitepackagesfile" "${PYSIDE2_ROOT_DIR}/lib/python$PY_MAJORVER.7/site-packages/PySide2/$sitepackagesfile"
        done
        # Remove incorrect RPATHs of installed site-packages/PySide2/uic
        install_name_tool -delete_rpath "$WORKSPACE_DIR/external_dependencies/qt_5.15.2/lib" -delete_rpath '@loader_path' "${PYSIDE2_ROOT_DIR}/lib/python$PY_MAJORVER.7/site-packages/PySide2/uic"

        # Copy the 'scripts' PySide2 sudmodules folder manually, since the pyside2-uic and pyside2-rcc wrappers invoke
        # pyside_tool.py through [console_scripts] entrypoints.
        echo "Copying site-packages/PySide2/scripts from $PREFIX_DIR to $PYSIDE2_ROOT_DIR"
        cp -R "$PREFIX_DIR/$BUILDTYPE/lib/python$PY_MAJORVER.7/site-packages/PySide2/scripts" "$PYSIDE2_ROOT_DIR/lib/python$PY_MAJORVER.7/site-packages/PySide2/"

        # Workaround: Until the issue is addressed within PySide2 build scripts, we manually copy the 'support' PySide2 submodule
        # into the build to prevent the "__feature__ could not be imported" error.
        echo "Copying site-packages/PySide2/support from $PREFIX_DIR to $PYSIDE2_ROOT_DIR"
        cp -R "$PREFIX_DIR/$BUILDTYPE/lib/python$PY_MAJORVER.7/site-packages/PySide2/support" "$PYSIDE2_ROOT_DIR/lib/python$PY_MAJORVER.7/site-packages/PySide2/"

        # Delete __pycache folders
        echo "Deleting __pycache__ folders from install"
        find "$PYSIDE2_ROOT_DIR/lib/python$PY_MAJORVER.7/site-packages/PySide2/" -type d -name "__pycache__" -exec rm -r {} +

        # Change RPATHs of shiboken2 executable
        echo "install_name_tool -delete_rpath \"$WORKSPACE_DIR/external_dependencies/libclang/lib\" \"$PYSIDE2_ROOT_DIR/bin/shiboken2\""
        install_name_tool -delete_rpath "$WORKSPACE_DIR/external_dependencies/libclang/lib" "$PYSIDE2_ROOT_DIR/bin/shiboken2"
        echo "install_name_tool -delete_rpath \"$WORKSPACE_DIR/external_dependencies/qt_$QTVERSION/lib\" \"$PYSIDE2_ROOT_DIR/bin/shiboken2\""
        install_name_tool -delete_rpath "$WORKSPACE_DIR/external_dependencies/qt_$QTVERSION/lib" "$PYSIDE2_ROOT_DIR/bin/shiboken2"
        set +e # don't bail if commands return nonzero exit codes, since we're explicitly checking this one.
        echo "install_name_tool -add_rpath @loader_path/../MacOS \"$PYSIDE2_ROOT_DIR/bin/shiboken2\""
        install_name_tool -add_rpath @loader_path/../MacOS "$PYSIDE2_ROOT_DIR/bin/shiboken2"
        if [[ $? -ne 0 ]]; then
            echo "**** Error: Failed setting rpath. Calling otool -l */shiboken2"
            set -e
            echo "otool -l \"$PYSIDE2_ROOT_DIR/bin/shiboken2\""
            otool -l "$PYSIDE2_ROOT_DIR/bin/shiboken2"
        fi
        set -e
    fi
done
echo "==== Success ===="
