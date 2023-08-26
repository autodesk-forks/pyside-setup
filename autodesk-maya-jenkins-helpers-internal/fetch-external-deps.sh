#!/usr/bin/env bash

# Fetch external dependencies needed by PySide6 build (Fetched from artifactory)

set -e
set -u

startingPwd=$PWD

SKIP_QT=0
kept_args=()
for arg in "$@"; do
  case $arg in
    --skip-qt)
        if [[ $SKIP_QT -eq 0 ]]; then
            echo >&2 "Skipping Qt artifact."
            SKIP_QT=1
        fi
        shift
        ;;
    -*|--*)
        echo >&2 "Unknown option $arg"
        exit 1
        ;;
    *)
        kept_args+=($arg)
        ;;
  esac
done
set -- "${kept_args[@]}"

# Parameter 1 - Absolute path to workspace directory
if [ $# -eq 0 ]; then
    echo >&2 "Need to pass workspace directory to the script"
    exit 1
fi

if [[ $SKIP_QT -eq 0 ]]; then
set +u
# Environment Variable - QTVERSION - Version of Qt used to build PySide6
if [[ -z "${QTVERSION}" ]]; then
    echo >&2 "QTVERSION is undefined. Example: export QTVERSION=6.2.3"
    exit 1
else
    echo "QTVERSION=${QTVERSION}"
fi
set -u
fi # [[ $SKIP_QT -eq 0 ]]

# Location of the workspace directory (root)
export WORKSPACE_DIR=$1

DISTRO=""
OS=
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
    DISTRO=$(hostnamectl | awk '/Operating System/ { print $3 }')
    if [[ "$DISTRO" =~ "CentOS" ]]; then
        ARTIFACT_SUFFIX="Maya-Qt-Linux.tar.gz"
    else
        echo -n "RHEL "
        ARTIFACT_SUFFIX="Maya-Qt-Rhel8.tar.gz"
    fi
    PYTHON=python3
    echo "Linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
    ARTIFACT_SUFFIX="Maya-Qt-Mac.tar.gz"
    PYTHON=python3
    echo "macOS"
else
    OS="windows"
    ARTIFACT_SUFFIX="Maya-Qt-Windows.zip"
    PYTHON=python
    echo "Empty OSTYPE, assuming Windows."
fi

# Location of external dependencies directory
export EXTERNAL_DEPENDENCIES_DIR=$WORKSPACE_DIR/external_dependencies
if [[ ! -e $EXTERNAL_DEPENDENCIES_DIR ]]; then
    mkdir $EXTERNAL_DEPENDENCIES_DIR
fi


# First fetch the name of the artifacts we are going to use.
# Qt is the most complex, as it searches for the latest available Qt build for the version specified.
curlCmdSilent="curl -s -S"
artifactoryRoot="https://art-bobcat.autodesk.com/artifactory/"

# Test connection to artifactory
set +e
testOut=$($curlCmdSilent $artifactoryRoot 2>&1)
set -e
if [[ "$testOut" =~ "Could not resolve host" ]]; then
    echo >&2 "Couldn't connect to $artifactoryRoot, verify connection to ADSK VPN. Aborting."
    exit 1
fi

if [[ $SKIP_QT -eq 0 ]]; then
# Check both Jenkins builds and manual and persisted builds in maya area. first ones found win.
echo -n "Determining which Qt artifact to download."
artifactoryQtPath=
for artifactoryArea in "oss-stg-generic" "team-maya-generic"; do
    echo -n "."
    artifactoryQtPath="${artifactoryRoot}api/storage/${artifactoryArea}/Qt/${QTVERSION}/Maya"
    artifactoryQtBuildFolders=$($curlCmdSilent $artifactoryQtPath | $PYTHON -c "import sys, json; print(' '.join(sorted([x['uri'] for x in json.load(sys.stdin)['children'] if x['folder'] == True ], reverse=True)))")
    if [ $? -gt 0 ]; then
        echo >&2 "Fetching Qt Build folders from Artifactory url $artifactoryQtPath failed. Aborting."
        exit 1
    fi
    if [[ -n "${artifactoryQtBuildFolders}" ]]; then
        # don't bother checking other area if we already found builds.
        break
    fi
done

if [[ -z "${artifactoryQtBuildFolders}" ]]; then
    echo >&2 "No Qt artifacts for $QTVERSION found. Aborting."
    exit 1
fi

qtArtifactDownloadUri=
for folder in ${artifactoryQtBuildFolders[@]}; do

    echo -n "."
    folderls=$($curlCmdSilent ${artifactoryQtPath}${folder})
    if [ $? -gt 0 ]; then
        echo >&2 "Fetching Qt Build folder $folder from Artifactory failed. Aborting."
        exit 1
    fi
    folderls=$(echo $folderls) # remove \n that breaks python
    children=$($PYTHON -c "import sys, json; print(' '.join([x['uri'] for x in json.loads('$folderls')['children'] if x['folder'] == False ]))")
    for child in ${children[@]}; do
        if [[ -z "$qtArtifactDownloadUri" && $child == *"${ARTIFACT_SUFFIX}" || ($OS == "macos" && $child == *"-macos-ub2.tar.gz") ]]; then
            childls=$($curlCmdSilent ${artifactoryQtPath}${folder}${child})
            if [ $? -gt 0 ]; then
                echo >&2 "Fetching Qt Build metadata for ${artifactoryQtPath}${folder}${child} from Artifactory failed. Aborting."
                exit 1
            fi
            childls=$(echo $childls)
            qtArtifactDownloadUri=$($PYTHON -c "import json; print(json.loads('$childls')['downloadUri'])")
            qtArtifactDownloadMd5=$($PYTHON -c "import json; print(json.loads('$childls')['checksums']['md5'])")
        fi
    done
done

echo
if [[ -n "$qtArtifactDownloadUri" ]]; then
    echo "Using Qt artifact:"
    echo "    $qtArtifactDownloadUri"
else
    echo "No Qt $QTVERSION artifact found for ${DISTRO} ${OS}. Aborting."
    exit 1
fi
fi # [[ $SKIP_QT -eq 0 ]]


# Which Python artifact to use - not used on all platforms
declare -A pythonArtifactDownloadUris
pythonArtifactDownloadUris["windows"]="team-maya-generic/python/3.11.4/cpython-3.11.4-win.zip"
pythonArtifactDownloadUris["linux"]="team-maya-generic/python/3.11.4/cpython-3.11.4-lin-rocky8-gcc12-2023_08_22_1645.zip"
pythonArtifactDownloadUris["macos"]="team-maya-generic/python/3.11.4/cpython-3.11.4-mac-universal2.zip"
pythonArtifactDownloadUri=${pythonArtifactDownloadUris[${OS}]}

# Which OpenSSL artifact to use - not used on all platforms
declare -A opensslArtifactDownloadUris
opensslArtifactDownloadUris["windows"]="team-maya-generic/openssl/1.1.1g/openssl-1.1.1g-win-vc140.zip"
opensslArtifactDownloadUris["linux"]=""
opensslArtifactDownloadUris["macos"]=""
opensslArtifactDownloadUri=${opensslArtifactDownloadUris[${OS}]}

# Which libclang artifact to use - not used on all platforms
declare -A libclangArtifactDownloadUris
libclangArtifactDownloadUris["windows"]="team-maya-generic/libclang/release_140-based/libclang-release_140-based-windows-vs2019_64.zip"
libclangArtifactDownloadUris["linux"]="team-maya-generic/libclang/release_140-based/libclang-release_140-based-linux-Rhel8.2-gcc9.2-x86_64.tar.gz"
libclangArtifactDownloadUris["macos"]="team-maya-generic/libclang/release_140-based/libclang-release_140-based-macos-universal.tar.gz"
libclangArtifactDownloadUri=${libclangArtifactDownloadUris[${OS}]}

# Which cmake artifact to use - not used on all platforms
declare -A cmakeArtifactDownloadUris
cmakeArtifactDownloadUris["windows"]=""
cmakeArtifactDownloadUris["linux"]="team-maya-generic/Cmake/cmake-3.22.1-linux-x86_64.tar.gz"
cmakeArtifactDownloadUris["macos"]="team-maya-generic/Cmake/cmake-3.22.1-windows-x86_64.zip"
cmakeArtifactDownloadUri=${cmakeArtifactDownloadUris[${OS}]}
artifactDownloadUris=($pythonArtifactDownloadUri $opensslArtifactDownloadUri $libclangArtifactDownloadUri $cmakeArtifactDownloadUri)



# Download artifacts from artifactory
cd $EXTERNAL_DEPENDENCIES_DIR

if [[ $SKIP_QT -eq 0 ]]; then
qtArtifactBasename=$(basename $qtArtifactDownloadUri)
usingExistingQt=0
if [[ -e "$qtArtifactBasename" ]]; then
    echo >&2 "$qtArtifactBasename exists."
    localMd5=$(md5sum $qtArtifactBasename | awk '{print $1}')
    if [[ $localMd5 == $qtArtifactDownloadMd5 ]]; then
        echo "md5sums match, using cached artifact package."
        usingExistingQt=1
    else
        mv -f "$qtArtifactBasename" "$qtArtifactBasename.bak"
    fi
fi

if [[ ! -e "$qtArtifactBasename" ]]; then
    echo "Downloading Qt artifact $qtArtifactDownloadUri"
    curl -O $qtArtifactDownloadUri
    if [ $? -gt 0 ]; then
        echo >&2 "Failed to download Qt artifact $qtArtifactDownloadUri. Aborting."
        exit 1
    fi
fi
fi # [[ $SKIP_QT -eq 0 ]]

for artifactDownloadUri in ${artifactDownloadUris[@]}; do
    artifactBasename=$(basename $artifactDownloadUri)
    if [ -n "$artifactDownloadUri" ]; then
        # Fetch the md5sum of the artifact from Artifactory
        artifactls=$($curlCmdSilent ${artifactoryRoot}api/storage/${artifactDownloadUri})
        artifactls=$(echo $artifactls)
        artifactDownloadMd5=$($PYTHON -c "import json; print(json.loads('$artifactls')['checksums']['md5'])")

        if [[ -e "$artifactBasename" ]]; then
            echo >&2 "$artifactBasename exists."
            localMd5=$(md5sum $artifactBasename | awk '{print $1}')
            if [[ $localMd5 == $artifactDownloadMd5 ]]; then
                echo "md5sums match, using cached artifact package."
            else
                mv -f "$artifactBasename" "$artifactBasename.bak"
            fi
        fi

        if [[ ! -e "$artifactBasename" ]]; then
            artifactDownloadUri="${artifactoryRoot}${artifactDownloadUri}"
            echo "Downloading artifact $artifactDownloadUri"
            curl -O $artifactDownloadUri
            if [ $? -gt 0 ]; then
                echo >&2 "Failed to download artifact $artifactDownloadUri. Aborting."
                exit 1
            fi
        fi
    fi
done

if [[ $SKIP_QT -eq 0 ]]; then
# Expand artifacts to the external_dependencies directory
# expand Qt artifact
if [[ -d qt_$QTVERSION && ! $usingExistingQt -eq 1 ]]; then
    echo "Found existing unpacked Qt artifact qt_$QTVERSION. Removing it."
    rm -Rf qt_$QTVERSION
fi

if [[ ! -d qt_$QTVERSION ]]; then
    echo "Expanding Qt artifact"
    if [ $OS == "windows" ]; then
        7z x "$qtArtifactBasename"
        if [ $? -gt 0 ]; then
            echo >&2 "Failed to unpack Qt artifact $qtArtifactBasename with 7zip. Aborting."
            exit 1
        fi
    else
        tar zxvf "$qtArtifactBasename" | python -c "
import sys
for line in sys.stdin:
    sys.stdout.write('.')
    sys.stdout.flush()
print()"
        if [ $? -gt 0 ]; then
            echo >&2 "Failed to unpack Qt artifact $qtArtifactBasename. Aborting."
            exit 1
        fi
    fi
fi
fi # [[ $SKIP_QT -eq 0 ]]

# Remove artifact dirs if they exist (these ones we remove because there may be contamination in the
# expanded python dir. Others that are part of this could be done more like the Qt one above - where
# md5sums are checked and tar not unpacked if matching selected one on server.
# For now, we just always remove and expand fresh.
artifactDirNames=("cpython" "openssl" "libclang")
for i in $(seq 0 $((${#artifactDownloadUris[@]}-1)) ); do
    echo "artifactDownloadUris[$i]: ${artifactDownloadUris[$i]}"
    echo "artifactDirNames[$i]: ${artifactDirNames[$i]}"
    if [ -n "${artifactDownloadUris[$i]}" ]; then
        if [[ -d ${artifactDirNames[$i]} ]]; then
            echo "Found existing unpacked artifact ${artifactDirNames[$i]}. Removing it."
            rm -Rf ${artifactDirNames[$i]}
        fi
    fi
done

# Expand artifacts (that aren't Qt which is special cased)
for artifactDownloadUri in ${artifactDownloadUris[@]}; do
    artifactBasename=$(basename $artifactDownloadUri)
    if [ -n "$artifactDownloadUri" ]; then
        echo -n "Expanding artifact $artifactBasename"
        if [ $OS == "windows" ]; then
            7z x "$artifactBasename"
            if [ $? -gt 0 ]; then
                echo >&2 "Failed to unpack artifact $artifactBasename with 7zip. Aborting."
                exit 1
            fi
        else
            if [[ "$artifactBasename" =~ .*\.zip ]]; then
                cmd="unzip"
            elif [[ "$artifactBasename" =~ .*\.tar.xz ]]; then
                cmd="tar Jxvf"
            else
                cmd="tar zxvf"
            fi
            $cmd "$artifactBasename" | python -c "
import sys
for line in sys.stdin:
    sys.stdout.write('.')
    sys.stdout.flush()
print()"
            if [ $? -gt 0 ]; then
                echo >&2 "Failed to unpack artifact $artifactBasename. Aborting."
                exit 1
            fi
        fi
    fi
done

echo "---- Success Finished ----"
