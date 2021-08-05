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
    echo "PYTHONMAJORVERSION is undefined. Example: export PYTHONMAJORVERSION=3"
    exit 1
elif [[ ! ("$PYTHONMAJORVERSION" == "2" || "$PYTHONMAJORVERSION" == "3") ]]; then
    echo "PYTHONMAJORVERSION should be '2' or '3'. Example: export PYTHONMAJORVERSION=3"
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

# Location of CMake directory (in external dependencies)
# Latest CMake version in CentOS 7.6 is 2.8.x.x, but PySide2 requires a minimum of CMake 3.1 
export CMAKE_DIR=$EXTERNAL_DEPENDENCIES_DIR/cmake-3.13.3-Linux-x86_64/bin


# By default, the pyside2-uic and pyside2-rcc wrappers are installed in the Python directory during the install step.
# Using the --prefix option, we specify a different location where to output the files, which makes it easier to copy 
# the wrappers in the /bin folder when packaging.
export PREFIX_DIR=$WORKSPACE_DIR/build
export PREFIX_DIR_RELEASE=$PREFIX_DIR/release
export PREFIX_DIR_DEBUG=$PREFIX_DIR/debug

if [ -e "$PREFIX_DIR_RELEASE" ]; then
    rm -rf "$PREFIX_DIR_RELEASE"
fi
if [ -e "$PREFIX_DIR_DEBUG" ]; then
    rm -rf "$PREFIX_DIR_DEBUG"
fi
mkdir "$PREFIX_DIR_RELEASE"
mkdir "$PREFIX_DIR_DEBUG"

# Location where the built wheels will be outputted
# To be able to use pyside2-uic.exe and pyside2-rcc.exe, we need the metadata from the .dist-info folders, 
# which can be obtained by unpacking the wheels.
export DIST_DIR=$WORKSPACE_DIR/dist
export DIST_DIR_RELEASE=$DIST_DIR/release
export DIST_DIR_DEBUG=$DIST_DIR/debug

if [ -e "$DIST_DIR_RELEASE" ]; then
    rm -rf "$DIST_DIR_RELEASE"
fi
if [ -e "$DIST_DIR_DEBUG" ]; then
    rm -rf "$DIST_DIR_DEBUG"
fi
mkdir -p "$DIST_DIR_RELEASE"
mkdir -p "$DIST_DIR_DEBUG"

# Location of Python 2 directory (in external dependencies)
export PYTHONEXE_2_DIR=$EXTERNAL_DEPENDENCIES_DIR/cpython/2.7.11/RelWithDebInfo/bin
export PYTHONEXE_2_D_DIR=$EXTERNAL_DEPENDENCIES_DIR/cpython/2.7.11/Debug/bin

# Location of Python 3 directory (in external dependencies)
export PYTHONEXE_3_DIR=$EXTERNAL_DEPENDENCIES_DIR/cpython/3.7.7/RelWithDebInfo/bin
export PYTHONEXE_3_D_DIR=$EXTERNAL_DEPENDENCIES_DIR/cpython/3.7.7/Debug/bin

# Name of the Python executable
if [ $PYTHONMAJORVERSION -eq 3 ]; then
    export PYTHON_EXE=python3.7
else
    export PYTHON_EXE=python-bin
fi


# Create qt.conf file
touch $EXTERNAL_DEPENDENCIES_DIR/qt_$QTVERSION/bin/qt.conf
echo [Paths] > $EXTERNAL_DEPENDENCIES_DIR/qt_$QTVERSION/bin/qt.conf
echo Prefix=.. >> $EXTERNAL_DEPENDENCIES_DIR/qt_$QTVERSION/bin/qt.conf

# Store current PATH to be able to restore it later
export OLDPATH=$PATH

# Get the number of processors available to build PySide2
export NUMBER_OF_PROCESSORS=`cat /proc/cpuinfo | grep processor | wc -l`



if [ $PYTHONMAJORVERSION -eq 3 ]; then
    export PYTHONEXEPATH=$PYTHONEXE_3_DIR
    export PATH=$PYTHONEXEPATH:$PATH
    
    # Ensure that pip and its required modules are installed for Python 3 (release version)
    $PYTHON_EXE -m ensurepip
    $PYTHON_EXE -m pip install pip
    $PYTHON_EXE -m pip install setuptools

    # Maya redefines `slots` so it is called `slots_` in the file. Rename it so it can be detected again
    sed -i -e 's/\(PyType_Slot\ \*slots\)_/\1/' $EXTERNAL_DEPENDENCIES_DIR/cpython/3.7.7/RelWithDebInfo/include/python3.7m/object.h
else
    export PYTHONEXEPATH=$PYTHONEXE_2_DIR
    export PATH=$PYTHONEXEPATH:$PATH
fi

$PYTHON_EXE -m pip install wheel==0.34.1
$PYTHON_EXE -m pip install packaging

# Add CMake (>3.1) to the PATH to ensure it is chosen first instead of default version 2.8.x.x of CentOS 7
export PATH=$CMAKE_DIR:$PATH

# Build PySide2 in release
$PYTHON_EXE setup.py install --qmake=$QTPATH/bin/qmake --ignore-git --parallel=$NUMBER_OF_PROCESSORS --prefix=$PREFIX_DIR_RELEASE
if [ $? -eq 0 ]; then
    echo "==== Success ==== Release Build"
else
    echo "**** Failed to build **** Release Build"
    exit 1
fi
$PYTHON_EXE setup.py bdist_wheel --qmake=$QTPATH/bin/qmake --ignore-git --parallel=$NUMBER_OF_PROCESSORS --dist-dir=$DIST_DIR_RELEASE
if [ $? -eq 0 ]; then
    echo "==== Success ==== Release Build Wheel"
else
    echo "**** Failed to build **** Release Build Wheel"
    exit 1
fi


# Unpack the wheels
if [ $PYTHONMAJORVERSION -eq 3 ]; then
    export WHEEL_SUFFIX_R=${QTVERSION}-${PYSIDEVERSION}-cp${PYTHONMAJORVERSION}7-cp${PYTHONMAJORVERSION}7m-linux_x86_64
else
    export WHEEL_SUFFIX_R=${QTVERSION}-${PYSIDEVERSION}-cp${PYTHONMAJORVERSION}7-cp${PYTHONMAJORVERSION}7mu-manylinux1_x86_64
fi

export PYSIDE2_WHEEL=PySide2-${WHEEL_SUFFIX_R}.whl
export SHIBOKEN2_WHEEL=shiboken2-${WHEEL_SUFFIX_R}.whl
export SHIBOKEN2_GEN_WHEEL=shiboken2_generator-${WHEEL_SUFFIX_R}.whl

$PYTHON_EXE -m wheel unpack $DIST_DIR_RELEASE/$PYSIDE2_WHEEL --dest=$DIST_DIR_RELEASE
$PYTHON_EXE -m wheel unpack $DIST_DIR_RELEASE/$SHIBOKEN2_WHEEL --dest=$DIST_DIR_RELEASE
$PYTHON_EXE -m wheel unpack $DIST_DIR_RELEASE/$SHIBOKEN2_GEN_WHEEL --dest=$DIST_DIR_RELEASE



if [ $PYTHONMAJORVERSION -eq 3 ]; then
    export PYTHONEXEPATH=$PYTHONEXE_3_D_DIR
    export PATH=$PYTHONEXEPATH:$OLDPATH

    # Ensure that pip and its required modules are installed for Python 3 (debug version)
    $PYTHON_EXE -m ensurepip
    $PYTHON_EXE -m pip install pip
    $PYTHON_EXE -m pip install setuptools
else
    export PYTHONEXEPATH=$PYTHONEXE_2_D_DIR
    export PATH=$PYTHONEXEPATH:$OLDPATH
fi

$PYTHON_EXE -m pip install wheel==0.34.1
$PYTHON_EXE -m pip install packaging

# Add CMake (>3.1) to the PATH to ensure it is chosen first instead of default version 2.8.x.x of CentOS 7
export PATH=$CMAKE_DIR:$PATH

# Build PySide2 in debug
$PYTHON_EXE setup.py install --qmake=$QTPATH/bin/qmake --ignore-git --parallel=$NUMBER_OF_PROCESSORS --debug --prefix=$PREFIX_DIR_DEBUG
if [ $? -eq 0 ]; then
    echo "==== Success ==== Debug Build"
else
    echo "**** Failed to build **** Debug Build"
    exit 1
fi
$PYTHON_EXE setup.py bdist_wheel --qmake=$QTPATH/bin/qmake --ignore-git --parallel=$NUMBER_OF_PROCESSORS --debug --dist-dir=$DIST_DIR_DEBUG
if [ $? -eq 0 ]; then
    echo "==== Success ==== Debug Build Wheel"
else
    echo "**** Failed to build **** Debug Build Wheel"
    exit 1
fi


# Unpack the wheels
if [ $PYTHONMAJORVERSION -eq 3 ]; then
    export WHEEL_SUFFIX_D=${QTVERSION}-${PYSIDEVERSION}-cp${PYTHONMAJORVERSION}7-cp${PYTHONMAJORVERSION}7dm-linux_x86_64
else
    export WHEEL_SUFFIX_D=${QTVERSION}-${PYSIDEVERSION}-cp${PYTHONMAJORVERSION}7-cp${PYTHONMAJORVERSION}7mu-manylinux1_x86_64
fi

export PYSIDE2_WHEEL=PySide2-${WHEEL_SUFFIX_D}.whl
export SHIBOKEN2_WHEEL=shiboken2-${WHEEL_SUFFIX_D}.whl
export SHIBOKEN2_GEN_WHEEL=shiboken2_generator-${WHEEL_SUFFIX_D}.whl

$PYTHON_EXE -m wheel unpack $DIST_DIR_DEBUG/$PYSIDE2_WHEEL --dest=$DIST_DIR_DEBUG
$PYTHON_EXE -m wheel unpack $DIST_DIR_DEBUG/$SHIBOKEN2_WHEEL --dest=$DIST_DIR_DEBUG
$PYTHON_EXE -m wheel unpack $DIST_DIR_DEBUG/$SHIBOKEN2_GEN_WHEEL --dest=$DIST_DIR_DEBUG