if [ ! -e README.pyside6.md ] ; then
    echo "Pyside2 packaging script not in correct current directory"
    echo "ABORTING: Current directory incorrect."
    exit 1
fi

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

# Python 3.9.7 artifacts don't have any pymalloc suffix, but future python builds might. Leaving this in place.
export PYMALLOC_SUFFIX=

# Location of the workspace directory (root)
export WORKSPACE_DIR=$1

# Location of the install directory within the workspace (where the builds will be located)
export INSTALL_DIR=$WORKSPACE_DIR/install

# Location of the pyside6-uic and pyside6-rcc wrappers (determined by the --prefix option in the build script)
export PREFIX_DIR=$WORKSPACE_DIR/build

# Location of the pyside6-uic and pyside6-rcc .dist-info metadata folders (determined by the --dist-dir option in the build script)
export DIST_DIR=$WORKSPACE_DIR/dist


export PATCHELF=patchelf
mkdir -p $INSTALL_DIR

# Determine if it is a Python 2 or Python 3 build
export PATH_TO_MAYAPY_REGEX='1s/.*/\#\!\/usr\/bin\/env mayapy2/'
if [ -e "pyside3_install" ]; then
    export PATH_TO_MAYAPY_REGEX='1s/.*/\#\!\/usr\/bin\/env mayapy/'
fi
echo "Built for Python ${PYTHONVERSION_A}"


# Write PySide6 build information to a "pyside6_version" file
# instead of encoding the pyside version number in a directory name
cat <<EOF >${INSTALL_DIR}/pyside6_version
pyside6 $PYSIDEVERSION
qt $QTVERSION
python version $PYTHONVERSION
EOF


for BUILDTYPE in release debug;
do
    # Define folder names
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

    if [ -e "$BUILDTYPE_INSTALL_DIR" ]; then
        # Copy the build (release, debug) to the installation directory
        cp -R "$BUILDTYPE_INSTALL_DIR" $INSTALL_DIR/

        # Define the path to the directory of the PySide6 build (bin, include, lib, share) in the installation directory
        export PYSIDE6_ROOT_DIR=${INSTALL_DIR}/${BUILDTYPE_INSTALL_DIR}/py${PYTHONVERSION_AdotB}-qt${QTVERSION}-64bit-${BUILDTYPE}

        # Workaround: Since the pyside6-uic and pyside6-rcc wrappers are not installed in the build directory, we need to copy them from
        # the --prefix directory into the artifact's /bin folder
        for wrapper in pyside6-rcc pyside6-uic
        do
            cp $PREFIX_DIR/$BUILDTYPE/bin/$wrapper $PYSIDE6_ROOT_DIR/bin/

            # Replace interpreter path for relative path to mayapy
            sed -i -e "${PATH_TO_MAYAPY_REGEX}" $PYSIDE6_ROOT_DIR/bin/$wrapper
        done

        # Copy the .dist-info metadata folders, since the pyside6-uic and pyside6-rcc wrappers rely on [console_scripts] entrypoints.
        for distfolder in PySide6 shiboken6 shiboken6_generator
        do
            cp -R $DIST_DIR/$BUILDTYPE/$distfolder-$PYSIDEVERSION/$distfolder-$PYSIDEVERSION.dist-info $PYSIDE6_ROOT_DIR/lib/python$PYTHONVERSION_AdotB/site-packages/$distfolder-$PYSIDEVERSION.dist-info
            mv $PYSIDE6_ROOT_DIR/lib/python$PYTHONVERSION_AdotB/site-packages/$distfolder-$PYSIDEVERSION.dist-info/RECORD $PYSIDE6_ROOT_DIR/lib/python$PYTHONVERSION_AdotB/site-packages/$distfolder-$PYSIDEVERSION.dist-info/RECORD-DONOTUNINSTALL
        done

        # Copy uic and rcc executable files into site-packages/PySide6, since it is the first search location for loadUiType.
        for sitepackagesfile in rcc uic
        do
            cp "$PREFIX_DIR/$BUILDTYPE/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide6/$sitepackagesfile" "${PYSIDE6_ROOT_DIR}/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide6/$sitepackagesfile"
        done

        # Copy the 'scripts' PySide6 sudmodules folder manually, since the pyside6-uic and pyside6-rcc wrappers invoke
        # pyside_tool.py through [console_scripts] entrypoints.
        cp -R "$PREFIX_DIR/$BUILDTYPE/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide6/scripts" "${PYSIDE6_ROOT_DIR}/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide6/"

        # Workaround: Until the issue is addressed within PySide6 build scripts, we manually copy the 'support' PySide6 submodule
        # into the build to prevent the "__feature__ could not be imported" error.
        cp -R "$PREFIX_DIR/$BUILDTYPE/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide6/support" "${PYSIDE6_ROOT_DIR}/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide6/"

        # Delete __pycache folders
        find "${PYSIDE6_ROOT_DIR}/lib/python${PYTHONVERSION_AdotB}/site-packages/" -type d -name "__pycache__" -exec rm -r {} +

        if [ $PYTHONVERSION_A -eq 3 ]; then
            echo "Changing RUNPATHs (Python 3 - ${BUILDTYPE})"
            export DEBUG_SUFFIX=
            if [ "$BUILDTYPE" == "debug" ]; then
                export DEBUG_SUFFIX=d
            fi

            for binfile in pyside6-lupdate uic rcc shiboken6
            do
                export binfilepath="$PYSIDE6_ROOT_DIR/bin/$binfile"
                if [ -e "$binfilepath" ]; then
                    $PATCHELF --set-rpath '$ORIGIN:$ORIGIN/../lib' "$binfilepath"
                fi
            done

            for libfile in pyside6 shiboken6
            do
                $PATCHELF --set-rpath '$ORIGIN:$ORIGIN/../lib' "$PYSIDE6_ROOT_DIR/lib/lib$libfile.cpython-${PYTHONVERSION_AB}${DEBUG_SUFFIX}${PYMALLOC_SUFFIX}-x86_64-linux-gnu.so.${PYSIDEVERSION}"
            done

            for sitepackagesfile in uic rcc
            do
                $PATCHELF --set-rpath '$ORIGIN:$ORIGIN/../../../../lib' "$PYSIDE6_ROOT_DIR/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide6/$sitepackagesfile"
            done

            $PATCHELF --set-rpath '$ORIGIN:$ORIGIN/../../../../lib' "$PYSIDE6_ROOT_DIR/lib/python${PYTHONVERSION_AdotB}/site-packages/shiboken6/shiboken6.cpython-${PYTHONVERSION_AB}${DEBUG_SUFFIX}${PYMALLOC_SUFFIX}-x86_64-linux-gnu.so"

            for qtmodule in Qt3DAnimation Qt3DCore Qt3DExtras Qt3DInput Qt3DLogic Qt3DRender QtConcurrent QtCore QtGui QtHelp QtLocation QtMultimedia QtMultimediaWidgets QtNetwork QtOpenGL QtOpenGLFunctions QtPositioning QtPrintSupport QtQml QtQuick QtQuickWidgets QtRemoteObjects QtScxml QtSensors QtSql QtSvg QtTest QtTextToSpeech QtUiTools QtWebChannel QtWebEngineCore QtWebEngine QtWebEngineWidgets QtWebSockets QtWidgets QtX11Extras QtXml QtXmlPatterns
            do
                $PATCHELF --set-rpath '$ORIGIN:$ORIGIN/../../../../lib' "$PYSIDE6_ROOT_DIR/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide6/$qtmodule.cpython-${PYTHONVERSION_AB}${DEBUG_SUFFIX}${PYMALLOC_SUFFIX}-x86_64-linux-gnu.so"
            done
        else
            echo "Changing RUNPATHs (Python 2 - ${BUILDTYPE})"

            for binfile in pyside6-lupdate uic rcc shiboken6
            do
                export binfilepath="$PYSIDE6_ROOT_DIR/bin/$binfile"
                if [ -e "$binfilepath" ]; then
                    $PATCHELF --set-rpath '$ORIGIN:$ORIGIN/../lib' "$binfilepath"
                fi
            done

            for libfile in pyside6 shiboken6
            do
                $PATCHELF --set-rpath '$ORIGIN:$ORIGIN/../lib' "$PYSIDE6_ROOT_DIR/lib/lib$libfile-python${PYTHONVERSION_AdotB}.so.${PYSIDEVERSION}"
            done

            for sitepackagesfile in uic rcc
            do
                $PATCHELF --set-rpath '$ORIGIN:$ORIGIN/../../../../lib' "$PYSIDE6_ROOT_DIR/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide6/$sitepackagesfile"
            done

            $PATCHELF --set-rpath '$ORIGIN:$ORIGIN/../../../../lib' "$PYSIDE6_ROOT_DIR/lib/python${PYTHONVERSION_AdotB}/site-packages/shiboken6/shiboken6.so"

            for qtmodule in Qt3DAnimation Qt3DCore Qt3DExtras Qt3DInput Qt3DLogic Qt3DRender QtConcurrent QtCore QtGui QtHelp QtLocation QtMultimedia QtMultimediaWidgets QtNetwork QtOpenGL QtOpenGLFunctions QtPositioning QtPrintSupport QtQml QtQuick QtQuickWidgets QtRemoteObjects QtScxml QtSensors QtSql QtSvg QtTest QtTextToSpeech QtUiTools QtWebChannel QtWebEngineCore QtWebEngine QtWebEngineWidgets QtWebSockets QtWidgets QtX11Extras QtXml QtXmlPatterns
            do
                $PATCHELF --set-rpath '$ORIGIN:$ORIGIN/../../../../lib' "$PYSIDE6_ROOT_DIR/lib/python${PYTHONVERSION_AdotB}/site-packages/PySide6/$qtmodule.so"
            done
        fi
    fi
done
echo "==== Finished ===="
