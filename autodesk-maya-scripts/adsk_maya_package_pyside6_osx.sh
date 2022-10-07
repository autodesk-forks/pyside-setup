# Exit bash script if return codes from commands are nonzero
set -e

if [ ! -e README.pyside6.md ] ; then
    echo "Pyside6 packaging script not in correct current directory"
    echo "ABORTING: Current directory incorrect."
    exit 1
fi

# Parameter 1 - Absolute path to workspace directory
if [ $# -eq 0 ]; then
    echo "Need to pass workspace directory to the script"
    exit 1
fi

# Environment Variable - QTVERSION - Version of Qt used to build PySide6
if [[ -z "$QTVERSION" ]]; then
    echo "QTVERSION is undefined. Example: export QTVERSION=6.2.3"
    exit 1
else
    echo "QTVERSION=$QTVERSION"
fi

# Environment Variable - PYSIDEVERSION - Version of PySide6 built
if [[ -z "$PYSIDEVERSION" ]]; then
    echo "PYSIDEVERSION is undefined. Example: export PYSIDEVERSION=6.2.3"
    exit 1
else
    echo "PYSIDEVERSION=$PYSIDEVERSION"
fi

# Environment Variable - PYTHONVERSION - Version of Python for which PySide6 is built
if [[ -z "$PYTHONVERSION" ]]; then
    echo "PYTHONVERSION is undefined. Example: export PYTHONVERSION=3.9.7"
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
if [[ ! ("$PYTHONVERSION_A" == "2" || "$PYTHONVERSION_A" == "3") ]]; then
    echo "Python major version should be '2' or '3'. Example: export PYTHONVERSION=3.9.7"
    exit 1
fi


# Location of the workspace directory (root), made absolute so RPATHs can be detected properly.
export WORKSPACE_DIR=$(python3 -c "import os,sys; print(os.path.abspath(sys.argv[1]))" $1)

# Exit bash script if the script expands variables that were never set.
set -u

# Location of the install directory within the workspace (where the builds will be located)
export INSTALL_DIR="$WORKSPACE_DIR/install"

# Location of the pyside6-uic and pyside6-rcc wrappers (determined by the --prefix option in the build script)
export PREFIX_DIR="$WORKSPACE_DIR/build"

# Location of the pyside6-uic and pyside6-rcc .dist-info metadata folders (determined by the --dist-dir option in the build script)
export DIST_DIR="$WORKSPACE_DIR/dist"

mkdir -p "$INSTALL_DIR"

# Determine if it is a Python 2 or Python 3 build
export PATH_TO_MAYAPY_REGEX='1s/.*/\#\!\/usr\/bin\/env python2_unused_in_maya2022plus_on_macOS/'
if [ -e "pyside3_install" ]; then
    export PATH_TO_MAYAPY_REGEX='1s/.*/\#\!\/usr\/bin\/env mayapy/'
fi
echo "Built for Python $PYTHONVERSION_A"



# Write PySide6 build information to a "pyside6_version" file
# instead of encoding the pyside version number in a directory name
cat <<EOF >"$INSTALL_DIR/pyside6_version"
pyside6 $PYSIDEVERSION
qt $QTVERSION
python version $PYTHONVERSION_A
EOF

# Copy, setup and package
for BUILDTYPE in release debug
do
    export DEBUG_SUFFIX=""
    if [ "$BUILDTYPE" == "debug" ]; then
        export DEBUG_SUFFIX="d"
    fi

    export BUILDTYPE_INSTALL_DIR="pyside${PYTHONVERSION_A}${DEBUG_SUFFIX}_install"

    if [[ -e "$BUILDTYPE_INSTALL_DIR" ]]; then
        echo "Copying the build (release, debug) to the installation directory"
        cp -R "$BUILDTYPE_INSTALL_DIR" "$INSTALL_DIR/"

        # Define the path to the directory of the PySide6 build (bin, include, lib, share) in the installation directory
        export PYSIDE6_ROOT_DIR="$INSTALL_DIR/$BUILDTYPE_INSTALL_DIR/py${PYTHONVERSION_AdotB}-qt${QTVERSION}-64bit-${BUILDTYPE}"

        # Workaround: Since the pyside6-uic and pyside6-rcc wrappers are not installed in the build directory, we need to copy them from
        # the --prefix directory into the artifact's /bin folder
        for wrapper in pyside6-rcc pyside6-uic
        do
            echo "Copying \"$PREFIX_DIR/$BUILDTYPE/bin/$wrapper\" to \"$PYSIDE6_ROOT_DIR/bin/\""
            cp "$PREFIX_DIR/$BUILDTYPE/bin/$wrapper" "$PYSIDE6_ROOT_DIR/bin/"

            # Replace interpreter path for relative path to mayapy
            echo "Updating $wrapper script's shebang line with regex $PATH_TO_MAYAPY_REGEX"
            sed -i -e "$PATH_TO_MAYAPY_REGEX" "$PYSIDE6_ROOT_DIR/bin/$wrapper"
        done

        # Copy the .dist-info metadata folders, since the pyside6-uic and pyside6-rcc wrappers rely on [console_scripts] entrypoints.
        for distfolder in PySide6 shiboken6 shiboken6_generator
        do
            echo "Copying $distfolder-PYSIDEVERSION.dist-info to .../site-packages"
            cp -R "$DIST_DIR/$BUILDTYPE/$distfolder-$PYSIDEVERSION/$distfolder-$PYSIDEVERSION.dist-info" "$PYSIDE6_ROOT_DIR/lib/python$PYTHONVERSION_AdotB/site-packages/$distfolder-$PYSIDEVERSION.dist-info"

            echo "Renaming $distfolder-PYSIDEVERSION.dist-info/RECORD so package cannot be pip uninstalled"
            mv "$PYSIDE6_ROOT_DIR/lib/python$PYTHONVERSION_AdotB/site-packages/$distfolder-$PYSIDEVERSION.dist-info/RECORD" "$PYSIDE6_ROOT_DIR/lib/python$PYTHONVERSION_AdotB/site-packages/$distfolder-$PYSIDEVERSION.dist-info/RECORD-DONOTUNINSTALL"
        done

        # Copy uic and rcc executable files into site-packages/PySide6, since it is the first search location for pyside6-uic that is used by loadUiType.
        for sitepackagesfile in rcc uic
        do
            cp "$PREFIX_DIR/$BUILDTYPE/lib/python$PYTHONVERSION_AdotB/site-packages/PySide6/$sitepackagesfile" "${PYSIDE6_ROOT_DIR}/lib/python$PYTHONVERSION_AdotB/site-packages/PySide6/$sitepackagesfile"
        done

        # Remove incorrect RPATHs of installed site-packages/PySide6/uic
        install_name_tool -delete_rpath "$WORKSPACE_DIR/external_dependencies/qt_$QTVERSION/lib" -delete_rpath '@loader_path' "${PYSIDE6_ROOT_DIR}/lib/python$PYTHONVERSION_AdotB/site-packages/PySide6/uic"

        # Copy the 'scripts' PySide6 sudmodules folder manually, since the pyside6-uic and pyside6-rcc wrappers invoke
        # pyside_tool.py through [console_scripts] entrypoints.
        echo "Copying site-packages/PySide6/scripts from $PREFIX_DIR to $PYSIDE6_ROOT_DIR"
        cp -R "$PREFIX_DIR/$BUILDTYPE/lib/python$PYTHONVERSION_AdotB/site-packages/PySide6/scripts" "$PYSIDE6_ROOT_DIR/lib/python$PYTHONVERSION_AdotB/site-packages/PySide6/"

        # Workaround: Until the issue is addressed within PySide6 build scripts, we manually copy the 'support' PySide6 submodule
        # into the build to prevent the "__feature__ could not be imported" error.
        echo "Copying site-packages/PySide6/support from $PREFIX_DIR to $PYSIDE6_ROOT_DIR"
        cp -R "$PREFIX_DIR/$BUILDTYPE/lib/python$PYTHONVERSION_AdotB/site-packages/PySide6/support" "$PYSIDE6_ROOT_DIR/lib/python$PYTHONVERSION_AdotB/site-packages/PySide6/"

        # Delete __pycache folders
        echo "Deleting __pycache__ folders from install"
        find "$PYSIDE6_ROOT_DIR/lib/python$PYTHONVERSION_AdotB/site-packages/PySide6/" -type d -name "__pycache__" -exec rm -r {} +

        # Change RPATHs of shiboken6 executable
        echo "install_name_tool -delete_rpath \"$WORKSPACE_DIR/external_dependencies/libclang/lib\" \"$PYSIDE6_ROOT_DIR/bin/shiboken6\""
        install_name_tool -delete_rpath "$WORKSPACE_DIR/external_dependencies/libclang/lib" "$PYSIDE6_ROOT_DIR/bin/shiboken6"
        echo "install_name_tool -delete_rpath \"$WORKSPACE_DIR/external_dependencies/qt_$QTVERSION/lib\" \"$PYSIDE6_ROOT_DIR/bin/shiboken6\""
        install_name_tool -delete_rpath "$WORKSPACE_DIR/external_dependencies/qt_$QTVERSION/lib" "$PYSIDE6_ROOT_DIR/bin/shiboken6"
        set +e # don't bail if commands return nonzero exit codes, since we're explicitly checking this one.
        echo "install_name_tool -add_rpath @loader_path/../MacOS \"$PYSIDE6_ROOT_DIR/bin/shiboken6\""
        install_name_tool -add_rpath @loader_path/../MacOS "$PYSIDE6_ROOT_DIR/bin/shiboken6"
        if [[ $? -ne 0 ]]; then
            echo "**** Error: Failed setting rpath. Calling otool -l */shiboken6"
            set -e
            echo "otool -l \"$PYSIDE6_ROOT_DIR/bin/shiboken6\""
            otool -l "$PYSIDE6_ROOT_DIR/bin/shiboken6"
        fi
        set -e
    fi
done
echo "==== Success ===="
