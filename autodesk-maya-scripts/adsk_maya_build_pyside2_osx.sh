# Exit bash script if return codes from commands are nonzero
set -u

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

# Exit bash script if expanding vars that were never set.
set -e

# Location of external dependencies directory
export EXTERNAL_DEPENDENCIES_DIR=$WORKSPACE_DIR/external_dependencies

# Location of Qt build directory (in external dependencies)
export QTPATH=$EXTERNAL_DEPENDENCIES_DIR/qt_$QTVERSION

# Location of liblang directory (in external dependencies)
export CLANG_INSTALL_DIR=$EXTERNAL_DEPENDENCIES_DIR/libclang

# Name of the Python executable
export PYTHON_EXE=python
if [ $PYTHONMAJORVERSION -eq 3 ]; then
	export PYTHON_EXE=python3.7
fi


# Create qt.conf file
touch $EXTERNAL_DEPENDENCIES_DIR/qt_$QTVERSION/bin/qt.conf
echo [Paths] > $EXTERNAL_DEPENDENCIES_DIR/qt_$QTVERSION/bin/qt.conf
echo Prefix=.. >> $EXTERNAL_DEPENDENCIES_DIR/qt_$QTVERSION/bin/qt.conf

# Get the number of processors available to build PySide2
export NUMBER_OF_PROCESSORS=`sysctl -n hw.ncpu`

# Ensure that pip and its required modules are installed
$PYTHON_EXE -m ensurepip
$PYTHON_EXE -m pip install pip
$PYTHON_EXE -m pip install setuptools
$PYTHON_EXE -m pip install wheel==0.34.1
$PYTHON_EXE -m pip install packaging

# Note: Mac uses the python.org distribution of Python 3, so there is no need to modify `slots`.

# Cleanup PREFIX and DIST dirs. See below for their definition.
export PREFIX_DIR=$WORKSPACE_DIR/build
export DIST_DIR=$WORKSPACE_DIR/dist
for BUILDTYPE in release debug;
do
	export PREFIX_DIR_RELEASE=$PREFIX_DIR/release
	export PREFIX_DIR_DEBUG=$PREFIX_DIR/debug

	if [ -e "${PREFIX_DIR}/${BUILDTYPE}" ]; then
	    rm -rf "${PREFIX_DIR}/${BUILDTYPE}"
	fi

	if [ -e "${DIST_DIR}/${BUILDTYPE}" ]; then
	    rm -rf "${DIST_DIR}/${BUILDTYPE}"
	fi
done

for BUILDTYPE in release debug;
do
	export BUILDTYPE_STR="Release"
    export EXTRA_SETUP_PY_OPTS=""
	if [ "$BUILDTYPE" == "debug" ]; then
	    export BUILDTYPE_STR="Debug"
		export EXTRA_SETUP_PY_OPTS="--debug"
	fi

	# By default, the pyside2-uic and pyside2-rcc wrappers are installed in the Python directory during the install step.
	# Using the --prefix option, we specify a different location where to output the files, which makes it easier to copy 
	# the wrappers in the /bin folder when packaging.
	export PREFIX_DIR_BUILDTYPE="${PREFIX_DIR}/${BUILDTYPE}"
	mkdir -p "$PREFIX_DIR_BUILDTYPE"

	# Location where the built wheels will be outputted
	# To be able to use pyside2-uic.exe and pyside2-rcc.exe, we need the metadata from the .dist-info folders, 
	# which can be obtained by unpacking the wheels.
	export DIST_DIR_BUILDTYPE="${DIST_DIR}/${BUILDTYPE}"
	mkdir -p "$DIST_DIR_BUILDTYPE"

	$PYTHON_EXE setup.py install --qmake=$QTPATH/bin/qmake --ignore-git --parallel=$NUMBER_OF_PROCESSORS $EXTRA_SETUP_PY_OPTS --prefix=$PREFIX_DIR_BUILDTYPE
	if [ $? -eq 0 ]; then
		echo "==== Success ==== $BUILDTYPE_STR Build"
	else
		echo "**** Failed to build **** $BUILDTYPE_STR Build"
		exit 1
	fi

	$PYTHON_EXE setup.py bdist_wheel --qmake=$QTPATH/bin/qmake --ignore-git --parallel=$NUMBER_OF_PROCESSORS $EXTRA_SETUP_PY_OPTS --dist-dir=$DIST_DIR_BUILDTYPE
	if [ $? -eq 0 ]; then
		echo "==== Success ==== $BUILDTYPE_STR Build Wheel"
	else
		echo "**** Failed to build **** $BUILDTYPE_STR Build Wheel"
		exit 1
	fi

	# Unpack the wheels - same suffix for both Python 2 and 3
	export WHEEL_SUFFIX=${QTVERSION}-${PYSIDEVERSION}-cp${PYTHONMAJORVERSION}7-cp${PYTHONMAJORVERSION}7m-macosx_10_13_x86_64

	export PYSIDE2_WHEEL=PySide2-${WHEEL_SUFFIX}.whl
	export SHIBOKEN2_WHEEL=shiboken2-${WHEEL_SUFFIX}.whl
	export SHIBOKEN2_GEN_WHEEL=shiboken2_generator-${WHEEL_SUFFIX}.whl

	$PYTHON_EXE -m wheel unpack "${DIST_DIR_BUILDTYPE}/${PYSIDE2_WHEEL}" --dest="${DIST_DIR_BUILDTYPE}"
	$PYTHON_EXE -m wheel unpack "${DIST_DIR_BUILDTYPE}/${SHIBOKEN2_WHEEL}" --dest="${DIST_DIR_BUILDTYPE}"
	$PYTHON_EXE -m wheel unpack "${DIST_DIR_BUILDTYPE}/${SHIBOKEN2_GEN_WHEEL}" --dest="${DIST_DIR_BUILDTYPE}"
done
echo "==== Finished ===="
