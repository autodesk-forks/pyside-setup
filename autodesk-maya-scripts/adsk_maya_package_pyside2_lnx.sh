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
if [[ -z "${QTVERSION}" ]]; then
    echo "QTVERSION is undefined. Example: export QTVERSION=5.15.2"
    exit 1
else
    echo "QTVERSION=${QTVERSION}"
fi

# Environment Variable - PYSIDEVERSION - Version of PySide2 built
if [[ -z "${PYSIDEVERSION}" ]]; then
    echo "PYSIDEVERSION is undefined. Example: export PYSIDEVERSION=5.15.2"
    exit 1
else
    echo "PYSIDEVERSION=${PYSIDEVERSION}"
fi


# Location of the workspace directory (root)
export WORKSPACE_DIR=$1

# Location of the install directory within the workspace (where the builds will be located)
export INSTALL_DIR=$WORKSPACE_DIR/install

# Location of the pyside2-uic and pyside2-rcc wrappers (determined by the --prefix option in the build script)
export PREFIX_DIR=$WORKSPACE_DIR/build

# Location of the pyside2-uic and pyside2-rcc .dist-info metadata folders (determined by the --dist-dir option in the build script)
export DIST_DIR=$WORKSPACE_DIR/dist


export PATCHELF=patchelf
mkdir -p $INSTALL_DIR

# Determine if it is a Python 2 or Python 3 build
export PY_MAJORVER=2
export PATH_TO_MAYAPY_REGEX='1s/.*/\#\!\/usr\/bin\/env mayapy2/'
if [ -e "pyside3_install" ]; then
    export PY_MAJORVER=3
    export PATH_TO_MAYAPY_REGEX='1s/.*/\#\!\/usr\/bin\/env mayapy/'
fi
echo "Built for Python v${PY_MAJORVER}"


# Write PySide2 build information to a "pyside2_version" file
# instead of encoding the pyside version number in a directory name
cat <<EOF >${INSTALL_DIR}/pyside2_version
pyside2 $PYSIDEVERSION
qt $QTVERSION
python major version $PY_MAJORVER
EOF


for BUILDTYPE in release debug;
do
    # Define folder names
    # Python 2: pyside2_install, pyside2d_install
    # Python 3: pyside3_install, pyside3dp_install
    export BUILDTYPE_SUFFIX=
    if [ "$BUILDTYPE" == "debug" ]; then
        if [ $PY_MAJORVER -eq 3 ]; then
            export BUILDTYPE_SUFFIX=dp
        else
            export BUILDTYPE_SUFFIX=d
        fi
    fi
    export BUILDTYPE_INSTALL_DIR=pyside${PY_MAJORVER}${BUILDTYPE_SUFFIX}_install

    if [ -e "$BUILDTYPE_INSTALL_DIR" ]; then
        # Copy the build (release, debug) to the installation directory
        cp -R "$BUILDTYPE_INSTALL_DIR" $INSTALL_DIR/

        # Define the path to the directory of the PySide2 build (bin, include, lib, share) in the installation directory
        export PYSIDE2_ROOT_DIR=${INSTALL_DIR}/${BUILDTYPE_INSTALL_DIR}/py${PY_MAJORVER}.7-qt${QTVERSION}-64bit-${BUILDTYPE}

        # Workaround: Since the pyside2-uic and pyside2-rcc wrappers are not installed in the build directory, we need to copy them from
        # the --prefix directory into the artifact's /bin folder
        for wrapper in pyside2-rcc pyside2-uic
        do
            cp $PREFIX_DIR/$BUILDTYPE/bin/$wrapper $PYSIDE2_ROOT_DIR/bin/

            # Replace interpreter path for relative path to mayapy
            sed -i -e "${PATH_TO_MAYAPY_REGEX}" $PYSIDE2_ROOT_DIR/bin/$wrapper
        done

        # Copy the .dist-info metadata folders, since the pyside2-uic and pyside2-rcc wrappers rely on [console_scripts] entrypoints.
        for distfolder in PySide2 shiboken2 shiboken2_generator
        do
            cp -R $DIST_DIR/$BUILDTYPE/$distfolder-$PYSIDEVERSION/$distfolder-$PYSIDEVERSION.dist-info $PYSIDE2_ROOT_DIR/lib/python$PY_MAJORVER.7/site-packages/$distfolder-$PYSIDEVERSION.dist-info
            mv $PYSIDE2_ROOT_DIR/lib/python$PY_MAJORVER.7/site-packages/$distfolder-$PYSIDEVERSION.dist-info/RECORD $PYSIDE2_ROOT_DIR/lib/python$PY_MAJORVER.7/site-packages/$distfolder-$PYSIDEVERSION.dist-info/RECORD-DONOTUNINSTALL
        done

        # Copy uic and rcc executable files into site-packages/PySide2, since it is the first search location for loadUiType.
        for sitepackagesfile in rcc uic
        do
            cp "$PREFIX_DIR/$BUILDTYPE/lib/python$PY_MAJORVER.7/site-packages/PySide2/$sitepackagesfile" "${PYSIDE2_ROOT_DIR}/lib/python$PY_MAJORVER.7/site-packages/PySide2/$sitepackagesfile"
        done

        # Copy the 'scripts' PySide2 sudmodules folder manually, since the pyside2-uic and pyside2-rcc wrappers invoke
        # pyside_tool.py through [console_scripts] entrypoints.
        cp -R "$PREFIX_DIR/$BUILDTYPE/lib/python$PY_MAJORVER.7/site-packages/PySide2/scripts" "${PYSIDE2_ROOT_DIR}/lib/python$PY_MAJORVER.7/site-packages/PySide2/"

        # Workaround: Until the issue is addressed within PySide2 build scripts, we manually copy the 'support' PySide2 submodule
        # into the build to prevent the "__feature__ could not be imported" error.
        cp -R "$PREFIX_DIR/$BUILDTYPE/lib/python$PY_MAJORVER.7/site-packages/PySide2/support" "${PYSIDE2_ROOT_DIR}/lib/python$PY_MAJORVER.7/site-packages/PySide2/"

        # Delete __pycache folders
        find "${PYSIDE2_ROOT_DIR}/lib/python$PY_MAJORVER.7/site-packages/" -type d -name "__pycache__" -exec rm -r {} +

        if [ $PY_MAJORVER -eq 3 ]; then
            echo "Changing RUNPATHs (Python 3 - ${BUILDTYPE})"
            export DBGSUFFIX=
            if [ "$BUILDTYPE" == "debug" ]; then
                export DBGSUFFIX=d
            fi

            for binfile in pyside2-lupdate uic rcc shiboken2
            do
                export binfilepath="$PYSIDE2_ROOT_DIR/bin/$binfile"
                if [ -e "$binfilepath" ]; then
                    $PATCHELF --set-rpath '$ORIGIN:$ORIGIN/../lib' "$binfilepath"
                fi
            done

            for libfile in pyside2 shiboken2
            do
                $PATCHELF --set-rpath '$ORIGIN:$ORIGIN/../lib' "$PYSIDE2_ROOT_DIR/lib/lib$libfile.cpython-37${DBGSUFFIX}m-x86_64-linux-gnu.so.${PYSIDEVERSION}"
            done

            for sitepackagesfile in uic rcc
            do
                $PATCHELF --set-rpath '$ORIGIN:$ORIGIN/../../../../lib' "$PYSIDE2_ROOT_DIR/lib/python3.7/site-packages/PySide2/$sitepackagesfile"
            done

            $PATCHELF --set-rpath '$ORIGIN:$ORIGIN/../../../../lib' "$PYSIDE2_ROOT_DIR/lib/python3.7/site-packages/shiboken2/shiboken2.cpython-37${DBGSUFFIX}m-x86_64-linux-gnu.so"

            for qtmodule in Qt3DAnimation Qt3DCore Qt3DExtras Qt3DInput Qt3DLogic Qt3DRender QtConcurrent QtCore QtGui QtHelp QtLocation QtMultimedia QtMultimediaWidgets QtNetwork QtOpenGL QtOpenGLFunctions QtPositioning QtPrintSupport QtQml QtQuick QtQuickWidgets QtRemoteObjects QtScxml QtSensors QtSql QtSvg QtTest QtTextToSpeech QtUiTools QtWebChannel QtWebEngineCore QtWebEngine QtWebEngineWidgets QtWebSockets QtWidgets QtX11Extras QtXml QtXmlPatterns
            do
                $PATCHELF --set-rpath '$ORIGIN:$ORIGIN/../../../../lib' "$PYSIDE2_ROOT_DIR/lib/python3.7/site-packages/PySide2/$qtmodule.cpython-37${DBGSUFFIX}m-x86_64-linux-gnu.so"
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
                $PATCHELF --set-rpath '$ORIGIN:$ORIGIN/../lib' "$PYSIDE2_ROOT_DIR/lib/lib$libfile-python2.7.so.${PYSIDEVERSION}"
            done

            for sitepackagesfile in uic rcc
            do
                $PATCHELF --set-rpath '$ORIGIN:$ORIGIN/../../../../lib' "$PYSIDE2_ROOT_DIR/lib/python2.7/site-packages/PySide2/$sitepackagesfile"
            done

            $PATCHELF --set-rpath '$ORIGIN:$ORIGIN/../../../../lib' "$PYSIDE2_ROOT_DIR/lib/python2.7/site-packages/shiboken2/shiboken2.so"

            for qtmodule in Qt3DAnimation Qt3DCore Qt3DExtras Qt3DInput Qt3DLogic Qt3DRender QtConcurrent QtCore QtGui QtHelp QtLocation QtMultimedia QtMultimediaWidgets QtNetwork QtOpenGL QtOpenGLFunctions QtPositioning QtPrintSupport QtQml QtQuick QtQuickWidgets QtRemoteObjects QtScxml QtSensors QtSql QtSvg QtTest QtTextToSpeech QtUiTools QtWebChannel QtWebEngineCore QtWebEngine QtWebEngineWidgets QtWebSockets QtWidgets QtX11Extras QtXml QtXmlPatterns
            do
                $PATCHELF --set-rpath '$ORIGIN:$ORIGIN/../../../../lib' "$PYSIDE2_ROOT_DIR/lib/python2.7/site-packages/PySide2/$qtmodule.so"
            done
        fi
    fi
done
echo "==== Finished ===="
