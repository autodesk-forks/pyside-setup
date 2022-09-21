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

# Make sure the user has passed in a python executable to use
if [[ -z "$PYTHONEXE" || ! -e "$PYTHONEXE" ]]; then
    if [[ -z "$PYTHONEXE" ]]; then echo -n "PYTHONEXE is undefined. "; fi
    if [[ ! -e "$PYTHONEXE" ]]; then echo -n "${PYTHONEXE} doesn't exist. "; fi
    if [[ ! -x "$PYTHONEXE" ]]; then echo -n "${PYTHONEXE} isn't executable. "; fi
	echo "Example: export PYTHONEXE=/external_dependencies/cpython/3.9.5/RelWithdebInfo/bin/python"
	exit 1
else
	echo "PYTHONEXE=${PYTHONEXE}"
fi

# Environment Variable - PYTHONVERSION - Version of Python for which PySide2 is built
# Determine the python version from python itself.
PYTHON_EXE_VERSION=$($PYTHONEXE -c "import sys; v=sys.version_info; print('{}.{}.{}'.format(v.major, v.minor, v.micro))")
if [[ ! "$PYTHON_EXE_VERSION" == "$PYTHONVERSION" ]]; then
    echo >&2 "Expecting Python ${PYTHONVERSION}, but the python executable ${PYTHONEXE} is ${PYTHON_EXE_VERSION}. aborting."
    exit 1
fi
echo "PYTHONVERSION=${PYTHONVERSION}"

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
	echo "Python major version should be '2' or '3'. Example: export PYTHONVERSION=3.7.7"
	exit 1
fi

# Python 2.7.X and 3.7.X artifacts have files with the pymalloc suffix
export PYMALLOC_SUFFIX=
if [ $PYTHONVERSION_B -eq 7 ]; then
	export PYMALLOC_SUFFIX=m
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


# Create qt.conf file
touch $EXTERNAL_DEPENDENCIES_DIR/qt_$QTVERSION/bin/qt.conf
echo [Paths] > $EXTERNAL_DEPENDENCIES_DIR/qt_$QTVERSION/bin/qt.conf
echo Prefix=.. >> $EXTERNAL_DEPENDENCIES_DIR/qt_$QTVERSION/bin/qt.conf

# Get the number of processors available to build PySide2
export NUMBER_OF_PROCESSORS=`sysctl -n hw.ncpu`

# Ensure that pip and its required modules are installed
$PYTHONEXE -m ensurepip
$PYTHONEXE -m pip install pip
$PYTHONEXE -m pip install setuptools
$PYTHONEXE -m pip install wheel==0.34.1
$PYTHONEXE -m pip install packaging

# Note: Mac uses the python.org distribution of Python 3, so there is no need to modify `slots`.

# Cleanup PREFIX and DIST dirs. See below for their definition.
export PREFIX_DIR=$WORKSPACE_DIR/build
export DIST_DIR=$WORKSPACE_DIR/dist
for BUILDTYPE in release debug;
do
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

	$PYTHONEXE setup.py install --qmake=$QTPATH/bin/qmake --ignore-git --parallel=$NUMBER_OF_PROCESSORS --prefix=$PREFIX_DIR_BUILDTYPE $EXTRA_SETUP_PY_OPTS --macos-deployment-target=11.0 --macos-arch="x86_64;arm64"  --skip-modules=Help
	if [ $? -eq 0 ]; then
		echo "==== Success ==== $BUILDTYPE_STR Build"
	else
		echo "**** Failed to build **** $BUILDTYPE_STR Build"
		exit 1
	fi

	$PYTHONEXE setup.py bdist_wheel --qmake=$QTPATH/bin/qmake --ignore-git --parallel=$NUMBER_OF_PROCESSORS --dist-dir=$DIST_DIR_BUILDTYPE $EXTRA_SETUP_PY_OPTS --skip-modules=Help --macos-deployment-target=11.0 --macos-arch="x86_64;arm64"

	if [ $? -eq 0 ]; then
		echo "==== Success ==== $BUILDTYPE_STR Build Wheel"
	else
		echo "**** Failed to build **** $BUILDTYPE_STR Build Wheel"
		exit 1
	fi

	# Unpack the wheels
	export WHEEL_SUFFIX=${PYSIDEVERSION}-${QTVERSION}-cp${PYTHONVERSION_AB}-cp${PYTHONVERSION_AB}${PYMALLOC_SUFFIX}

	export WHEEL_SUFFIX=${WHEEL_SUFFIX}-macosx_11_0_universal2

	export PYSIDE2_WHEEL=PySide2-${WHEEL_SUFFIX}.whl
	export SHIBOKEN2_WHEEL=shiboken2-${WHEEL_SUFFIX}.whl
	export SHIBOKEN2_GEN_WHEEL=shiboken2_generator-${WHEEL_SUFFIX}.whl

	$PYTHONEXE -m wheel unpack "${DIST_DIR_BUILDTYPE}/${PYSIDE2_WHEEL}" --dest="${DIST_DIR_BUILDTYPE}"
	$PYTHONEXE -m wheel unpack "${DIST_DIR_BUILDTYPE}/${SHIBOKEN2_WHEEL}" --dest="${DIST_DIR_BUILDTYPE}"
	$PYTHONEXE -m wheel unpack "${DIST_DIR_BUILDTYPE}/${SHIBOKEN2_GEN_WHEEL}" --dest="${DIST_DIR_BUILDTYPE}"
done
echo "==== Finished ===="
