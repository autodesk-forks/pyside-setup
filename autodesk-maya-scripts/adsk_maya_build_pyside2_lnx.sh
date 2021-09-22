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

# Environment Variable - PYTHONVERSION - Version of Python for which PySide2 is built
if [[ -z "$PYTHONVERSION" ]]; then
    echo "PYTHONVERSION is undefined. Example: export PYTHONVERSION=3.7.7"
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

# Location of external dependencies directory
export EXTERNAL_DEPENDENCIES_DIR=$WORKSPACE_DIR/external_dependencies

# Location of Qt build directory (in external dependencies)
export QTPATH=$EXTERNAL_DEPENDENCIES_DIR/qt_$QTVERSION

# Location of liblang directory (in external dependencies)
export CLANG_INSTALL_DIR=$EXTERNAL_DEPENDENCIES_DIR/libclang

# Location of CMake directory (in external dependencies)
# Latest CMake version in CentOS 7.6 is 2.8.x.x, but PySide2 requires a minimum of CMake 3.1 
export CMAKE_DIR=$EXTERNAL_DEPENDENCIES_DIR/cmake-3.13.3-Linux-x86_64/bin

# Location of Python directory (in external dependencies)
export PYTHONEXE_DIR=$EXTERNAL_DEPENDENCIES_DIR/cpython/${PYTHONVERSION}/RelWithDebInfo/bin
export PYTHONEXE_D_DIR=$EXTERNAL_DEPENDENCIES_DIR/cpython/${PYTHONVERSION}/Debug/bin

# Name of the Python executable
if [ $PYTHONVERSION_A -eq 3 ]; then
    export PYTHON_EXE=python${PYTHONVERSION_AdotB}
else
    export PYTHON_EXE=python-bin
fi

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


# Create qt.conf file
touch $EXTERNAL_DEPENDENCIES_DIR/qt_$QTVERSION/bin/qt.conf
echo [Paths] > $EXTERNAL_DEPENDENCIES_DIR/qt_$QTVERSION/bin/qt.conf
echo Prefix=.. >> $EXTERNAL_DEPENDENCIES_DIR/qt_$QTVERSION/bin/qt.conf

# Store current PATH to be able to restore it later
export OLDPATH=$PATH

# Get the number of processors available to build PySide2
export NUMBER_OF_PROCESSORS=`cat /proc/cpuinfo | grep processor | wc -l`


for BUILDTYPE in release debug;
do
    export BUILDTYPE_STR="Release"
    export PYTHONEXEPATH=$PYTHONEXE_DIR
    export EXTRA_SETUP_PY_OPTS=""
    export DEBUG_SUFFIX=

	if [ "$BUILDTYPE" == "debug" ]; then
	    export BUILDTYPE_STR="Debug"
        export PYTHONEXEPATH=$PYTHONEXE_D_DIR
		export EXTRA_SETUP_PY_OPTS="--debug"
        export DEBUG_SUFFIX=d
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

    # Add Python executable to the PATH
    export PATH=$PYTHONEXEPATH:$OLDPATH

    if [ $PYTHONVERSION_A -eq 3 ]; then    
        # Ensure that pip and its required modules are installed for Python 3 (release version)
        $PYTHON_EXE -m ensurepip
        $PYTHON_EXE -m pip install pip
        $PYTHON_EXE -m pip install setuptools

        if [ "$BUILDTYPE" == "release" ]; then
            # Maya redefines `slots` so it is called `slots_` in the file. Rename it so it can be detected again
            sed -i -e 's/\(PyType_Slot\ \*slots\)_/\1/' $EXTERNAL_DEPENDENCIES_DIR/cpython/${PYTHONVERSION}/RelWithDebInfo/include/python${PYTHONVERSION_AdotB}${PYMALLOC_SUFFIX}/object.h
        fi
    fi

    $PYTHON_EXE -m pip install wheel==0.34.1
    $PYTHON_EXE -m pip install packaging

    # Add CMake (>3.1) to the PATH to ensure it is chosen first instead of default version 2.8.x.x of CentOS 7
    export PATH=$CMAKE_DIR:$PATH

    # Build PySide2
    $PYTHON_EXE setup.py install --qmake=$QTPATH/bin/qmake --ignore-git --parallel=$NUMBER_OF_PROCESSORS --prefix=$PREFIX_DIR_BUILDTYPE $EXTRA_SETUP_PY_OPTS
    if [ $? -eq 0 ]; then
        echo "==== Success ==== $BUILDTYPE_STR Build"
    else
        echo "**** Failed to build **** $BUILDTYPE_STR Build"
        exit 1
    fi
    $PYTHON_EXE setup.py bdist_wheel --qmake=$QTPATH/bin/qmake --ignore-git --parallel=$NUMBER_OF_PROCESSORS --dist-dir=$DIST_DIR_BUILDTYPE $EXTRA_SETUP_PY_OPTS
    if [ $? -eq 0 ]; then
        echo "==== Success ==== $BUILDTYPE_STR Build Wheel"
    else
        echo "**** Failed to build **** $BUILDTYPE_STR Build Wheel"
        exit 1
    fi

    # Unpack the wheels
    export WHEEL_SUFFIX=${QTVERSION}-${PYSIDEVERSION}-cp${PYTHONVERSION_AB}-cp${PYTHONVERSION_AB}

    if [ $PYTHONVERSION_A -eq 3 ]; then
        export WHEEL_SUFFIX=${WHEEL_SUFFIX}${DEBUG_SUFFIX}${PYMALLOC_SUFFIX}-linux_x86_64
    else
        export WHEEL_SUFFIX=${WHEEL_SUFFIX}${PYMALLOC_SUFFIX}u-manylinux1_x86_64
    fi

    export PYSIDE2_WHEEL=PySide2-${WHEEL_SUFFIX}.whl
    export SHIBOKEN2_WHEEL=shiboken2-${WHEEL_SUFFIX}.whl
    export SHIBOKEN2_GEN_WHEEL=shiboken2_generator-${WHEEL_SUFFIX}.whl

    $PYTHON_EXE -m wheel unpack $DIST_DIR_BUILDTYPE/$PYSIDE2_WHEEL --dest=$DIST_DIR_BUILDTYPE
    $PYTHON_EXE -m wheel unpack $DIST_DIR_BUILDTYPE/$SHIBOKEN2_WHEEL --dest=$DIST_DIR_BUILDTYPE
    $PYTHON_EXE -m wheel unpack $DIST_DIR_BUILDTYPE/$SHIBOKEN2_GEN_WHEEL --dest=$DIST_DIR_BUILDTYPE
done