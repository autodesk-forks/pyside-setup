# Current Directory is assumed to be the base of the pyside-setup repository.

if [ ! -e README.pyside2.md ]
    echo "Pyside2 packaging script not in correct current directory"
    echo "ABORTING: Current directory incorrect."
    exit 1
fi

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
export INSTALLDIR=$WORKDIR/install

mkdir -p $INSTALLDIR

# Instead of encoding the pyside version number in a directory name
# instead put it in a "pyside2_version" file.
cat <<EOF >${INSTALLDIR}/pyside2_version
pyside2 $PYSIDEVERSION
qt $QTVERSION
EOF

if [ -e "pyside2_install" ]; then
    cp -R "pyside2_install" $INSTALLDIR/
fi
if [ -e "pyside2d_install" ]; then
    cp -R "pyside2d_install" $INSTALLDIR/
fi
echo "==== Success ===="

