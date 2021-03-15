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

# Environment Variable - PYTHONMAJORVERSION - Version of Python for which PySide2 is built
if [[ -z "$PYTHONMAJORVERSION" ]]; then
	echo "PYTHONMAJORVERSION is undefined.  Example: export PYTHONMAJORVERSION=3"
	exit 1
elif [[ ! ("$PYTHONMAJORVERSION" == "2" || "$PYTHONMAJORVERSION" == "3") ]]; then
	echo "PYTHONMAJORVERSION should be '2' or '3'.  Example: export PYTHONMAJORVERSION=3"
	exit 1
fi

# Location of the workspace directory (root)
export WORKSPACE_DIR=$1

# Location of external dependencies directory
export EXTERNAL_DEPENDENCIES_DIR=$WORKSPACE_DIR/external_dependencies

# Location of Qt build directory (in external dependencies)
export QTPATH=$EXTERNAL_DEPENDENCIES_DIR/qt_$QTVERSION

# Location of liblang directory (in external dependencies)
export CLANG_INSTALL_DIR=$EXTERNAL_DEPENDENCIES_DIR/libclang

# Name of the Python executable
export PYTHONEXE=python
if [ $PYTHONMAJORVERSION -eq 3 ]; then
	export PYTHONEXE=python3.7
fi


# Create qt.conf file
touch $EXTERNAL_DEPENDENCIES_DIR/qt_$QTVERSION/bin/qt.conf
echo [Paths] > $EXTERNAL_DEPENDENCIES_DIR/qt_$QTVERSION/bin/qt.conf
echo Prefix=.. >> $EXTERNAL_DEPENDENCIES_DIR/qt_$QTVERSION/bin/qt.conf

# Print Python Version
$PYTHONEXE -V

# Get the number of processors available to build PySide2
export NUMBER_OF_PROCESSORS=`sysctl -n hw.ncpu`

# Note: Mac uses the python.org distribution of Python 3, so there is no need to modify `slots`.

$PYTHONEXE setup.py build --qmake=$QTPATH/bin/qmake --ignore-git --parallel=$NUMBER_OF_PROCESSORS
if [ $? -eq 0 ]; then
	echo "==== Success ==== Release Build"
else
    echo "**** Failed to build **** Release Build"
	exit 1
fi

$PYTHONEXE setup.py build --qmake=$QTPATH/bin/qmake --ignore-git --parallel=$NUMBER_OF_PROCESSORS --debug
if [ $? -eq 0 ]; then
	echo "==== Success ==== Debug Build"
else
    echo "**** Failed to build **** Debug Build"
	exit 1
fi
