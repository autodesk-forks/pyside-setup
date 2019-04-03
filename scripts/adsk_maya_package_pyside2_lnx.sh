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

if [[ -z "${PYSIDEVERSION}" ]]; then
	echo "PYSIDEVERSION is undefined.  Example: export PYSIDEVERSION=pyside_5.12.2"
	exit 1
else
	echo "PYSIDEVERSION=${PYSIDEVERSION}"
fi

export WORKDIR=$1
export SRCDIR=$WORKDIR/src
export INSTALLDIR=$WORKDIR/install/$PYSIDEVERSION

PKGDIR="$PWD/build/lib.linux-*-2.7"
mkdir -p $INSTALLDIR
cp -R $PKGDIR/PySide2 $INSTALLDIR/PySide2
pushd $PKGDIR >/dev/null
tar zcf $INSTALLDIR/PySide2/pyside2uic.tar.gz pyside2uic
popd >/dev/null
tar zcf $INSTALLDIR/PySide2/pyside2-$QTVERSION-include.tgz pyside2_install/py2.7-qt5.12.0-64bit-release/include/PySide2
tar zcf $INSTALLDIR/PySide2/shiboken2-$QTVERSION-include.tgz pyside2_install/py2.7-qt5.12.0-64bit-release/include/shiboken2
cp pyside2_install/py2.7-qt5.12.0-64bit-release/bin/pyside2-uic $INSTALLDIR/PySide2
echo "==== Success ===="

