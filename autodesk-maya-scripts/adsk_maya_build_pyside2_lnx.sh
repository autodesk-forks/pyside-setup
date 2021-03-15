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


$PYTHONEXE -V
if [ $PYTHONMAJORVERSION -eq 3 ]; then
    export PYTHONEXEPATH=$PYTHONEXE_3_DIR
	export PATH=$PYTHONEXEPATH:$PATH
	
	# Ensure that pip and its required modules are installed for Python 3 (release version)
	$PYTHON_EXE -m ensurepip
	$PYTHON_EXE -m pip install pip
	$PYTHON_EXE -m pip install setuptools
	$PYTHON_EXE -m pip install wheel==0.34.1

	# Maya redefines `slots` so it is called `slots_` in the file. Rename it so it can be detected again
	sed -i -e 's/\(PyType_Slot\ \*slots\)_/\1/' $EXTERNAL_DEPENDENCIES_DIR/cpython/3.7.7/RelWithDebInfo/include/python3.7m/object.h
else
	export PYTHONEXEPATH=$PYTHONEXE_2_DIR
	export PATH=$PYTHONEXEPATH:$PATH
fi

# Add CMake (>3.1) to the PATH to ensure it is chosen first instead of default version 2.8.x.x of CentOS 7
export PATH=$CMAKE_DIR:$PATH

# Build PySide2 in release
$PYTHON_EXE setup.py build --qmake=$QTPATH/bin/qmake --ignore-git --parallel=$NUMBER_OF_PROCESSORS
if [ $? -eq 0 ]; then
	echo "==== Success ==== Release Build"
else
    echo "**** Failed to build **** Release Build"
	exit 1
fi


$PYTHONEXE -V
if [ $PYTHONMAJORVERSION -eq 3 ]; then
    export PYTHONEXEPATH=$PYTHONEXE_3_D_DIR
	export PATH=$PYTHONEXEPATH:$OLDPATH

	# Ensure that pip and its required modules are installed for Python 3 (debug version)
	$PYTHON_EXE -m ensurepip
	$PYTHON_EXE -m pip install pip
	$PYTHON_EXE -m pip install setuptools
	$PYTHON_EXE -m pip install wheel==0.34.1
else
	export PYTHONEXEPATH=$PYTHONEXE_2_D_DIR
	export PATH=$PYTHONEXEPATH:$OLDPATH
fi

# Add CMake (>3.1) to the PATH to ensure it is chosen first instead of default version 2.8.x.x of CentOS 7
export PATH=$CMAKE_DIR:$PATH

# Build PySide2 in debug
$PYTHON_EXE setup.py build --qmake=$QTPATH/bin/qmake --ignore-git --parallel=$NUMBER_OF_PROCESSORS --debug
if [ $? -eq 0 ]; then
	echo "==== Success ==== Debug Build"
else
    echo "**** Failed to build **** Debug Build"
	exit 1
fi
