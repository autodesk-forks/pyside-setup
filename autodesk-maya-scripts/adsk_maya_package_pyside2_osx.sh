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

mkdir -p $INSTALL_DIR

# Determine if it is a Python 2 or Python 3 build
export PY_MAJORVER=2
if [ -e "pyside3_install" ]; then
    export PY_MAJORVER=3
fi
echo "Built for Python v${PY_MAJORVER}"



# Write PySide2 build information to a "pyside2_version" file 
# instead of encoding the pyside version number in a directory name
cat <<EOF >${INSTALL_DIR}/pyside2_version
pyside2 $PYSIDEVERSION
qt $QTVERSION
python major version $PY_MAJORVER
EOF

# Copy, setup and package release version
if [[ -e "pyside${PY_MAJORVER}_install" ]]; then
    cp -R "pyside${PY_MAJORVER}_install" $INSTALL_DIR/

    # Workaround: Until the issue is addressed within PySide2 build scripts, we manually copy the 'support' PySide2 submodule
    # into the build to prevent the "__feature__ could not be imported" error.
    export BUILDTYPE_INSTALL_DIR=pyside${PY_MAJORVER}_install
    export PYSIDE2_ROOT_DIR=${INSTALL_DIR}/${BUILDTYPE_INSTALL_DIR}/py${PY_MAJORVER}.7-qt${QTVERSION}-64bit-release
    cp -R "sources/pyside2/PySide2/support" "${PYSIDE2_ROOT_DIR}/lib/python${PY_MAJORVER}.7/site-packages/PySide2/"

    # Change RUNPATHs
    install_name_tool -delete_rpath $WORKSPACE_DIR/external_dependencies/libclang/lib $INSTALL_DIR/pyside${PY_MAJORVER}_install/py${PY_MAJORVER}.7-qt${QTVERSION}-64bit-release/bin/shiboken2
    install_name_tool -delete_rpath $WORKSPACE_DIR/external_dependencies/qt_${QTVERSION}/lib $INSTALL_DIR/pyside${PY_MAJORVER}_install/py${PY_MAJORVER}.7-qt${QTVERSION}-64bit-release/bin/shiboken2
    install_name_tool -add_rpath @loader_path/../MacOS $INSTALL_DIR/pyside${PY_MAJORVER}_install/py${PY_MAJORVER}.7-qt${QTVERSION}-64bit-release/bin/shiboken2
    if [[ $? -ne 0 ]]; then
        echo "**** Error: Failed setting rpath. Calling otool -l */shiboken2"
        otool -l $INSTALL_DIR/pyside${PY_MAJORVER}_install/py${PY_MAJORVER}.7-qt${QTVERSION}-64bit-release/bin/shiboken2
    fi
fi

# Copy, setup and package debug version
if [[ -e "pyside${PY_MAJORVER}d_install" ]]; then
    cp -R "pyside${PY_MAJORVER}d_install" $INSTALL_DIR/

    # Workaround: Until the issue is addressed within PySide2 build scripts, we manually copy the 'support' PySide2 submodule
    # into the build to prevent the "__feature__ could not be imported" error.
    export BUILDTYPE_INSTALL_DIR=pyside${PY_MAJORVER}d_install
    export PYSIDE2_ROOT_DIR=${INSTALL_DIR}/${BUILDTYPE_INSTALL_DIR}/py${PY_MAJORVER}.7-qt${QTVERSION}-64bit-debug
    cp -R "sources/pyside2/PySide2/support" "${PYSIDE2_ROOT_DIR}/lib/python${PY_MAJORVER}.7/site-packages/PySide2/"

    # Change RUNPATHs
    install_name_tool -delete_rpath $WORKSPACE_DIR/external_dependencies/libclang/lib $INSTALL_DIR/pyside${PY_MAJORVER}d_install/py${PY_MAJORVER}.7-qt${QTVERSION}-64bit-debug/bin/shiboken2
    install_name_tool -delete_rpath $WORKSPACE_DIR/external_dependencies/qt_${QTVERSION}/lib $INSTALL_DIR/pyside${PY_MAJORVER}d_install/py${PY_MAJORVER}.7-qt${QTVERSION}-64bit-debug/bin/shiboken2
    install_name_tool -add_rpath @loader_path/../MacOS $INSTALL_DIR/pyside${PY_MAJORVER}d_install/py${PY_MAJORVER}.7-qt${QTVERSION}-64bit-debug/bin/shiboken2
    if [[ $? -ne 0 ]]; then
        echo "**** Error: Failed setting rpath. Calling otool -l */shiboken2"
        otool -l $INSTALL_DIR/pyside${PY_MAJORVER}d_install/py${PY_MAJORVER}.7-qt${QTVERSION}-64bit-debug/bin/shiboken2
    fi
fi
echo "==== Success ===="

