# PySide2 Build instructions

This document provides instructions for building PySide2 (5.12.2) which include setting up build machines, building PySide2 via Jenkins and localtion of build artifacts.

## Links

[Building PySide2 from scratch](https://wiki.qt.io/Qt_for_Python/GettingStarted#Building_PySide2_from_scratch)


## Machine Setup

PySide2 is using the same QT5 build machines but required few additional packages installed on specific OS as listed below.  Please refer to [QT5 Build Machines Setup](https://git.autodesk.com/autodesk-forks/qt5/blob/adsk-contrib-maya-v5.12.2/QTBuildSetup.md) for more info.

### Windows 10

#### Install Python 2.7.15

- Download and install [Python 2.7.15](https://www.python.org/downloads/windows/)

#### Install Jom

- Download and install [Jom](http://download.qt.io/official_releases/jom/jom.zip)

Note that `Debug` build is not working yet.  Devs are still checking but likely we'll need to copy Python Debug libraries to machine.

### Linux - CentOS 7.3

#### Install python-setuptools

- sudo yum install python-setuptools

#### Install python

- sudo yum install python27

### Mac - OSX 10.14.

#### Install Python 2.7.15

- Download and install [Python 2.7.15](https://www.python.org/downloads/mac-osx/)

## Build

### Jenkins

- Login this [PySide2 5.12.2 build](https://master-11.jenkins.autodesk.com/job/Maya-pyside/job/pyside-setup/job/adsk-maya-qt-5.12.2/)
- Select 'Build with Parameters' where you can specify the commit hash you want build or leave it blank which will build from the HEAD commit.  You'll also need to specify QT branch and build to be used for this PySide2 build.

## Build artifacts 

PySide2 build artifacts will be uploaded [here](
https://art-bobcat.autodesk.com:443/artifactory/oss-stg-generic/pyside2/5.12.2/Maya)