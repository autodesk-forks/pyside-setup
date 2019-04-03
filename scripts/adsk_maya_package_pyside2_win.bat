if [%1]==[] (
   echo "Need to pass workspace directory to the script"
   exit /b 1
)

if not defined QTVERSION (
	echo QTVERSION is NOT defined.  Example: SET QTVERSION=qt_5.12.2
	exit /b 1
)
else (
	echo QTVERSION=%QTVERSION%
)

if not defined PYSIDEVERSION (
	echo PYSIDEVERSION is NOT defined.  Example: SET PYSIDEVERSION=pyside_5.12.2
	exit /b 1
)
else (
	echo PYSIDEVERSION=%PYSIDEVERSION%
)

set WORKDIR=%1
set SRCDIR=%WORKDIR%\src
set INSTALLDIR=%WORKDIR%\install\%PYSIDEVERSION%

set PKGDIR="%SRCDIR%\build\lib.win-amd64-2.7"
xcopy /e /i %PKGDIR%\pyside2 %INSTALLDIR%\pyside2
pushd %PKGDIR%
7z a -tzip %INSTALLDIR%/PySide2/pyside2uic.zip pyside2uic
popd
7z a -tzip %INSTALLDIR%/PySide2/pyside2-%QTVERSION%-include.zip pyside2_install/py2.7-qt5.12.0-64bit-release/include/PySide2
7z a -tzip %INSTALLDIR%/PySide2/shiboken2-%QTVERSION%-include.zip pyside2_install/py2.7-qt5.12.0-64bit-release/include/shiboken2
cp pyside2_install/py2.7-qt5.12.0-64bit-release/bin/pyside2-uic %INSTALLDIR%/PySide2

echo "==== Success ===="
