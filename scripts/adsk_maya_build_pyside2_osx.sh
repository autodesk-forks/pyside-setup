if [ $# -eq 0 ]; then
    echo "Need to pass workspace directory to the script"
	exit 1
fi

if [[ -z "${QTVERSION}" ]]; then
	echo "QTVERSION is undefined.  Example: export QTVERSION=qt_5.12.2"
	exit 1
else
	echo "QTVERSION=${QTVERSION}"
fi

export WORKDIR=$1
export ARTIFACTORYDIR=$WORKDIR/artifactory

export CLANG_INSTALL_DIR=$ARTIFACTORYDIR/libclang

#Create qt.conf file
touch $ARTIFACTORYDIR/$QTVERSION/bin/qt.conf
echo [Paths] > $ARTIFACTORYDIR/$QTVERSION/bin/qt.conf
echo Prefix=.. >> $ARTIFACTORYDIR/$QTVERSION/bin/qt.conf

export NUMBER_OF_PROCESSORS=`sysctl -n hw.ncpu`
python setup.py build --qmake=$ARTIFACTORYDIR/$QTVERSION/bin/qmake --build-tests --ignore-git --parallel=$NUMBER_OF_PROCESSORS

if [ $? -eq 0 ]; then
	echo "==== Success ===="
else
    echo "**** Failed to build ****"
	exit 1
fi


