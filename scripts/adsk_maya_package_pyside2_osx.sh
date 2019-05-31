if [ $# -eq 0 ]; then
    echo "Need to pass workspace directory to the script"
	exit 1
fi

# TODO Break out the Qt version number from the prefix. We need the version # separate for a directory name (see below)
if [[ -z "${QTVERSION}" ]]; then
	echo "QTVERSION is undefined.  Example: export QTVERSION=5.12.4"
	exit 1
else
	echo "QTVERSION=${QTVERSION}"
fi

if [[ -z "${PYSIDEVERSION}" ]]; then
	echo "PYSIDEVERSION is undefined.  Example: export PYSIDEVERSION=5.12.4"
	exit 1
else
	echo "PYSIDEVERSION=${PYSIDEVERSION}"
fi

export WORKDIR=$1
export SRCDIR=$WORKDIR/src
export INSTALLDIR=$WORKDIR/install/pyside_$PYSIDEVERSION

PKGDIR="$SRCDIR/build/lib.macosx-*-2.7"
mkdir -p $INSTALLDIR
cp -R $PKGDIR/PySide2 $INSTALLDIR/PySide2
pushd $PKGDIR >/dev/null
tar zcf $INSTALLDIR/PySide2/pyside2uic.tar.gz pyside2uic
popd >/dev/null
tar zcf $INSTALLDIR/PySide2/pyside2-qt$QTVERSION-include.tgz pyside2_install/py2.7-qt5.12.4-64bit-release/include/PySide2
tar zcf $INSTALLDIR/PySide2/shiboken2-qt$QTVERSION-include.tgz pyside2_install/py2.7-qt5.12.4-64bit-release/include/shiboken2
cp pyside2_install/py2.7-qt5.12.4-64bit-release/bin/pyside2-uic $INSTALLDIR/PySide2
echo "==== Success ===="


