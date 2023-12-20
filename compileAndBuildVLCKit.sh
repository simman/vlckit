#!/bin/sh
# Copyright (C) Pierre d'Herbemont, 2010
# Copyright (C) Felix Paul Kühne, 2012-2023

set -e

BUILD_DEVICE=yes
BUILD_SIMULATOR=no
BUILD_FRAMEWORK=no
SDK_VERSION=`xcrun --sdk iphoneos --show-sdk-version`
SDK_MIN=9.0
VERBOSE=yes
DISABLEDEBUG=yes
CONFIGURATION="Debug"
NONETWORK=no
SKIPLIBVLCCOMPILATION=no
TVOS=no
MACOS=no
IOS=yes
BITCODE=no
INCLUDE_ARMV7=no
OSVERSIONMINCFLAG=iphoneos
OSVERSIONMINLDFLAG=ios
ROOT_DIR=empty
FARCH="all"

if [ -z "$MAKEFLAGS" ]; then
    MAKEFLAGS="-j$(sysctl -n machdep.cpu.core_count || nproc)";
fi

TESTEDHASH="e6b30a03" # libvlc hash that this version of VLCKit is build on

usage()
{
cat << EOF
usage: $0 [-s] [-v] [-k sdk]

OPTIONS
   -k       Specify which sdk to use (see 'xcodebuild -showsdks', current: ${SDK})
   -v       Be more verbose
   -s       Build for simulator
   -f       Build framework for device and simulator
   -r       Disable Debug for Release
   -n       Skip script steps requiring network interaction
   -l       Skip libvlc compilation
   -t       Build for tvOS
   -x       Build for macOS / Mac OS X
   -b       Enable bitcode
   -a       Build framework for specific arch (all|x86_64|armv7|aarch64)
   -e       External VLC source path
   -7       Include optional ARMv7 slice (iOS only)
EOF
}

get_actual_arch() {
    if [ "$1" = "aarch64" ]; then
        echo "arm64"
    else
        echo "$1"
    fi
}

get_arch() {
    if [ "$1" = "arm64" ]; then
        echo "aarch64"
    else
        echo "$1"
    fi
}

is_simulator_arch() {
    if [ "$1" = "x86_64" ];then
        return 0
    else
        return 1
    fi
}

spushd()
{
     pushd "$1" 2>&1> /dev/null
}

spopd()
{
     popd 2>&1> /dev/null
}

info()
{
     local green="\033[1;32m"
     local normal="\033[0m"
     echo "[${green}info${normal}] $1"
}

buildxcodeproj()
{
    local target="$2"
    local PLATFORM="$3"

    info "Building $1 ($target, ${CONFIGURATION}, $PLATFORM)"

    local architectures=""
    if [ "$FARCH" = "all" ];then
        if [ "$TVOS" = "yes" ]; then
            if [ "$PLATFORM" = "appletvsimulator" ]; then
                architectures="x86_64 arm64"
            else
                architectures="arm64"
            fi
        fi
        if [ "$IOS" = "yes" ]; then
            if [ "$PLATFORM" = "iphonesimulator" ]; then
                architectures="x86_64 arm64"
            else
                if [ "$INCLUDE_ARMV7" = "yes" ]; then
                    architectures="armv7 arm64"
                else
                    architectures="arm64"
                fi
            fi
        fi
        if [ "$MACOS" = "yes" ]; then
            architectures="arm64 x86_64"
        fi
    else
        architectures=`get_actual_arch $FARCH`
    fi

    local bitcodeflag=""
    if [ "$IOS" = "yes" ]; then
    if [ "$BITCODE" = "yes" ]; then
        info "Bitcode enabled"
        bitcodeflag="BITCODE_GENERATION_MODE=bitcode"
    else
        info "Bitcode disabled"
        bitcodeflag="BITCODE_GENERATION_MODE=none ENABLE_BITCODE=no"
    fi
    fi
    if [ "$TVOS" = "yes" ]; then
    if [ "$BITCODE" = "yes" ]; then
        bitcodeflag="BITCODE_GENERATION_MODE=bitcode"
    fi
    fi

    local verboseflag=""
    if [ "$VERBOSE" = "yes" ]; then
        verboseflag="-verbose"
    fi

    local defs="$GCC_PREPROCESSOR_DEFINITIONS"

    xcodebuild archive \
               -project "$1.xcodeproj" \
               -sdk $PLATFORM$SDK \
               -configuration ${CONFIGURATION} \
               -scheme "$target" \
               -archivePath build/"$target"-$PLATFORM$SDK.xcarchive \
               ARCHS="${architectures}" \
               IPHONEOS_DEPLOYMENT_TARGET=${SDK_MIN} \
               ${bitcodeflag} \
               ${verboseflag} \
               SKIP_INSTALL=no \
               ONLY_ACTIVE_ARCH=NO \
               > ${out}
}

buildLibVLC() {
    ARCH="$1"
    PLATFORM="$2"

    if [ "$DISABLEDEBUG" = "yes" ]; then
        DEBUGFLAG="--disable-debug"
    else
        DEBUGFLAG=""
    fi
    if [ "$VERBOSE" = "yes" ]; then
        VERBOSEFLAG="--verbose"
    else
        VERBOSEFLAG=""
    fi
    if [ "$BITCODE" = "yes" ]; then
        if [[ "$PLATFORM" == *"os"* ]]; then
            BITCODEFLAG="--enable-bitcode"
        else
            BITCODEFLAG=""
        fi
    else
        BITCODEFLAG=""
    fi
    info "Compiling ${ARCH} with SDK version ${SDK_VERSION}, platform ${PLATFORM}"

    ACTUAL_ARCH=`get_actual_arch $ARCH`
    BUILDDIR="${VLCROOT}/build-${PLATFORM}-${ACTUAL_ARCH}"

    mkdir -p ${BUILDDIR}
    spushd ${BUILDDIR}

    ../extras/package/apple/build.sh --arch=$ARCH --sdk=${PLATFORM}${SDK_VERSION} ${DEBUGFLAG} ${VERBOSEFLAG} ${BITCODEFLAG} ${MAKEFLAGS}

    spopd # builddir

    info "Finished compiling libvlc for ${ARCH} with SDK version ${SDK_VERSION}, platform ${PLATFORM}"
}

buildMobileKit() {
    PLATFORM="$1"

    if [ "$SKIPLIBVLCCOMPILATION" != "yes" ]; then
        if [ "$FARCH" = "all" ];then
            if [ "$TVOS" = "yes" ]; then
                if [ "$PLATFORM" = "iphonesimulator" ]; then
                    buildLibVLC "x86_64" "appletvsimulator"
                    buildLibVLC "aarch64" "appletvsimulator"
                else
                    buildLibVLC "aarch64" "appletvos"
                fi
            fi
            if [ "$MACOS" = "yes" ]; then
                buildLibVLC "aarch64" "macosx"
                buildLibVLC "x86_64" "macosx"
            fi
            if [ "$IOS" = "yes" ]; then
                if [ "$PLATFORM" = "iphonesimulator" ]; then
                    buildLibVLC "x86_64" $PLATFORM
                    buildLibVLC "aarch64" $PLATFORM
                else
                    if [ "$INCLUDE_ARMV7" = "yes" ]; then
                        buildLibVLC "armv7" $PLATFORM
                    fi
                    buildLibVLC "aarch64" $PLATFORM
                fi
            fi
        else
            if [ "$FARCH" != "x86_64" -a "$FARCH" != "aarch64" -a "$FARCH" != "armv7" ];then
                echo "*** Framework ARCH: ${FARCH} is invalid ***"
                exit 1
            fi
            if (is_simulator_arch $FARCH);then
                if [ "$TVOS" = "yes" ]; then
                    PLATFORM="appletvsimulator"
                fi
                if [ "$IOS" = "yes" ]; then
                    PLATFORM="iphonesimulator"
                fi
                if [ "$MACOS" = "yes" ]; then
                    PLATFORM="macosx"
                fi
            else
                if [ "$TVOS" = "yes" ]; then
                    PLATFORM="appletvos"
                fi
                if [ "$IOS" = "yes" ]; then
                    PLATFORM="iphoneos"
                fi
                if [ "$MACOS" = "yes" ]; then
                    PLATFORM="macosx"
                fi
            fi

            buildLibVLC $FARCH "$PLATFORM"
        fi
    fi
}

get_symbol()
{
    echo "$1" | grep vlc_entry_$2|cut -d" " -f 3|sed 's/_vlc/vlc/'
}

function check_lipo {
    os_style="$1"
    os_arch="$2"
    header=""
    if [ -z "${os_style%%*simulator}" ]; then
        header=vlc-plugins-${os_style%simulator}-simulator-${os_arch}.h
    else
        header=vlc-plugins-${os_style%os}-device-${os_arch}.h
    fi

    build_dir="${VLCROOT}/build-${os_style}-${os_arch}"
    if [ -d "${build_dir}" ]; then
        VLCSTATICLIBS+=" ${build_dir}/${VLCSTATICLIBRARYNAME}"
        VLCSTATICMODULELIST="${build_dir}/static-lib/static-module-list.c"
        cp $VLCSTATICMODULELIST $PROJECT_DIR/Headers/Internal/${header}
    else
        echo "Directory ${build_dir} doesn't exist"
    fi
}

build_simulator_static_lib() {
    PROJECT_DIR=`pwd`
    OSSTYLE="$1"
    info "building simulator static lib for $OSSTYLE"

    # remove old module list
    rm -f $PROJECT_DIR/Headers/Internal/vlc-plugins-$OSSTYLE-simulator.h
    touch $PROJECT_DIR/Headers/Internal/vlc-plugins-$OSSTYLE-simulator.h

    spushd ${VLCROOT}
    rm -rf install-$OSSTYLE-simulator
    mkdir install-$OSSTYLE-simulator
    spopd # vlc

    VLCSTATICLIBS=""
    VLCSTATICLIBRARYNAME="static-lib/libvlc-full-static.a"
    VLCSTATICMODULELIST=""

    # brute-force test the available architectures we could lipo
    check_lipo "${OSSTYLE}simulator" x86_64
    check_lipo "${OSSTYLE}simulator" arm64

    if [ ! -z "${VLCSTATICLIBS}" ]; then
        spushd ${VLCROOT}
        lipo $VLCSTATICLIBS -create -output install-$OSSTYLE-simulator/libvlc-simulator-static.a
        spopd # VLCROOT
    fi
}

build_device_static_lib() {
    PROJECT_DIR=`pwd`
    OSSTYLE="$1"
    info "building device static lib for $OSSTYLE"

    # remove old module list
    rm -f $PROJECT_DIR/Headers/Internal/vlc-plugins-$OSSTYLE-device*

    spushd ${VLCROOT}
    rm -rf install-$OSSTYLE-device
    mkdir install-$OSSTYLE-device
    spopd # vlc

    VLCSTATICLIBS=""
    VLCSTATICLIBRARYNAME="static-lib/libvlc-full-static.a"
    VLCSTATICMODULELIST=""

    # brute-force test the available architectures we could lipo
    check_lipo "${OSSTYLE}os" arm64
    check_lipo "${OSSTYLE}os" armv7
    # macosx is not -os or -simulator suffixed in the script unfortunately.
    check_lipo "${OSSTYLE}" x86_64
    check_lipo "${OSSTYLE}" arm64

    if [ ! -z "${VLCSTATICLIBS}" ]; then
        spushd ${VLCROOT}
        lipo $VLCSTATICLIBS -create -output install-$OSSTYLE-device/libvlc-device-static.a
        spopd # VLCROOT
    fi
}

while getopts "hvsfbrxntl7k:a:e:" OPTION
do
     case $OPTION in
         h)
             usage
             exit 1
             ;;
         v)
             VERBOSE=yes
             ;;
         s)
             BUILD_DEVICE=no
             BUILD_SIMULATOR=yes
             BUILD_FRAMEWORK=no
             ;;
         f)
             BUILD_DEVICE=yes
             BUILD_SIMULATOR=yes
             BUILD_FRAMEWORK=yes
             ;;
         r)  CONFIGURATION="Release"
             DISABLEDEBUG=yes
             ;;
         n)
             NONETWORK=yes
             ;;
         l)
             SKIPLIBVLCCOMPILATION=yes
             ;;
         k)
             SDK=$OPTARG
             ;;
         a)
             BUILD_DEVICE=yes
             BUILD_SIMULATOR=yes
             BUILD_FRAMEWORK=yes
             FARCH=$OPTARG
             ;;
         b)
             BITCODE=yes
             ;;
         t)
             TVOS=yes
             IOS=no
             SDK_VERSION=`xcrun --sdk appletvos --show-sdk-version`
             SDK_MIN=10.2
             OSVERSIONMINCFLAG=tvos
             OSVERSIONMINLDFLAG=tvos
             ;;
         x)
             MACOS=yes
             IOS=no
             BITCODE=no
             SDK_VERSION=`xcrun --sdk macosx --show-sdk-version`
             SDK_MIN=10.11
             OSVERSIONMINCFLAG=macosx
             OSVERSIONMINLDFLAG=macosx
             BUILD_DEVICE=yes
             BUILD_FRAMEWORK=yes
             ;;
         e)
             VLCROOT=$OPTARG
             ;;
         7)
             INCLUDE_ARMV7=yes
             ;;
         ?)
             usage
             exit 1
             ;;
     esac
done
shift $(($OPTIND - 1))

out="/dev/null"
if [ "$VERBOSE" = "yes" ]; then
   out="/dev/stdout"
fi

if [ "$1" != "" ]; then
    usage
    exit 1
fi

# Get root dir
spushd .
ROOT_DIR=`pwd`
spopd

if [ "$VLCROOT" = "" ]; then
    VLCROOT=${ROOT_DIR}/libvlc/vlc
    info "Preparing build dirs"

    mkdir -p libvlc
    spushd libvlc

    if [ "$NONETWORK" != "yes" ]; then
        if ! [ -e vlc ]; then
            git clone https://code.videolan.org/videolan/vlc.git --branch master --single-branch vlc
            info "Applying patches to vlc.git"
            cd vlc
            git checkout -B localBranch ${TESTEDHASH}
            git branch --set-upstream-to=origin/master localBranch
            git am ${ROOT_DIR}/libvlc/patches/*.patch
            if [ $? -ne 0 ]; then
                git am --abort
                info "Applying the patches failed, aborting git-am"
                exit 1
            fi
            cd ..
        else
            cd vlc
            git fetch --all
            git reset --hard ${TESTEDHASH}
            git am ${ROOT_DIR}/libvlc/patches/*.patch
            cd ..
        fi
    fi

    spopd
fi

fetch_python3_path() {
    # PYTHON3_PATH=$(echo /Library/Frameworks/Python.framework/Versions/3.*/bin | awk '{print $1;}')
    PYTHON3_PATH="/Users/runner/hostedtoolcache/Python/3.7.17/x64/bin"
    if [ ! -d "${PYTHON3_PATH}" ]; then
        PYTHON3_PATH=""
    fi
}

#
# Build time
#

out="/dev/null"
if [ "$VERBOSE" = "yes" ]; then
   out="/dev/stdout"
fi

if [ "$SKIPLIBVLCCOMPILATION" != "yes" ]; then
    info "Building tools"

    fetch_python3_path
    export PATH="${PYTHON3_PATH}:${VLCROOT}/extras/tools/build/bin:${VLCROOT}/contrib/${TARGET}/bin:$VLC_PATH:/usr/bin:/bin:/usr/sbin:/sbin"

    spushd ${VLCROOT}/extras/tools
    ./bootstrap
    make
    spopd #${VLCROOT}/extras/tools
fi

if [ "$BUILD_DEVICE" != "no" ]; then
    buildMobileKit iphoneos
fi
if [ "$BUILD_SIMULATOR" != "no" ]; then
    buildMobileKit iphonesimulator
fi

DEVICEARCHS=""
SIMULATORARCHS=""

if [ "$TVOS" = "yes" ]; then
    build_simulator_static_lib "appletv"
    build_device_static_lib "appletv"
fi
if [ "$MACOS" = "yes" ]; then
    build_device_static_lib "macosx"
fi
if [ "$IOS" = "yes" ]; then
    build_simulator_static_lib "iphone"
    build_device_static_lib "iphone"
fi

info "all done"

if [ "$BUILD_FRAMEWORK" != "no" ]; then
if [ "$TVOS" = "yes" ]; then
    info "Building TVVLCKit.xcframework"

    frameworks=""
    platform=""
    if [ "$FARCH" = "all" ] || (! is_simulator_arch $FARCH);then
        platform="appletvos"
        buildxcodeproj VLCKit "TVVLCKit" ${platform}
        dsymfolder=$PROJECT_DIR/build/TVVLCKit-${platform}.xcarchive/dSYMs/TVVLCKit.framework.dSYM
        bcsymbolmapfolder=$PROJECT_DIR/build/TVVLCKit-${platform}.xcarchive/BCSymbolMaps
        frameworks="$frameworks -framework TVVLCKit-${platform}.xcarchive/Products/Library/Frameworks/TVVLCKit.framework -debug-symbols $dsymfolder"
        if [ -d ${bcsymbolmapfolder} ];then
            info "Bitcode support found"
            spushd $bcsymbolmapfolder
            for i in `ls *.bcsymbolmap`
            do
                frameworks+=" -debug-symbols $bcsymbolmapfolder/$i"
            done
            spopd
        fi
    fi
    if [ "$FARCH" = "all" ] || (is_simulator_arch $arch);then
        platform="appletvsimulator"
        buildxcodeproj VLCKit "TVVLCKit" ${platform}
        dsymfolder=$PROJECT_DIR/build/TVVLCKit-${platform}.xcarchive/dSYMs/TVVLCKit.framework.dSYM
        frameworks="$frameworks -framework TVVLCKit-${platform}.xcarchive/Products/Library/Frameworks/TVVLCKit.framework -debug-symbols $dsymfolder"
    fi

    # Assumes both platforms were built currently
    spushd build
    rm -rf TVVLCKit.xcframework
    xcodebuild -create-xcframework $frameworks -output TVVLCKit.xcframework
    spopd # build

    info "Build of TVVLCKit.xcframework completed"
fi
if [ "$IOS" = "yes" ]; then
    info "Building MobileVLCKit.xcframework"

    frameworks=""
    platform=""
    if [ "$FARCH" = "all" ] || (! is_simulator_arch $FARCH);then
        platform="iphoneos"
        buildxcodeproj VLCKit "MobileVLCKit" ${platform}
        dsymfolder=$PROJECT_DIR/build/MobileVLCKit-${platform}.xcarchive/dSYMs/MobileVLCKit.framework.dSYM
        bcsymbolmapfolder=$PROJECT_DIR/build/MobileVLCKit-${platform}.xcarchive/BCSymbolMaps
        frameworks="$frameworks -framework MobileVLCKit-${platform}.xcarchive/Products/Library/Frameworks/MobileVLCKit.framework -debug-symbols $dsymfolder"
        if [ -d ${bcsymbolmapfolder} ];then
            info "Bitcode support found"
            spushd $bcsymbolmapfolder
            for i in `ls *.bcsymbolmap`
            do
                frameworks+=" -debug-symbols $bcsymbolmapfolder/$i"
            done
            spopd
        fi
    fi
    if [ "$FARCH" = "all" ] || (is_simulator_arch $arch);then
        platform="iphonesimulator"
        buildxcodeproj VLCKit "MobileVLCKit" ${platform}
        dsymfolder=$PROJECT_DIR/build/MobileVLCKit-${platform}.xcarchive/dSYMs/MobileVLCKit.framework.dSYM
        frameworks="$frameworks -framework MobileVLCKit-${platform}.xcarchive/Products/Library/Frameworks/MobileVLCKit.framework -debug-symbols $dsymfolder"
    fi

    # Assumes both platforms were built currently
    spushd build
    rm -rf MobileVLCKit.xcframework
    xcodebuild -create-xcframework $frameworks -output MobileVLCKit.xcframework
    spopd # build

    info "Build of MobileVLCKit.xcframework completed"
fi
fi
if [ "$BUILD_FRAMEWORK" != "no" ]; then
if [ "$MACOS" = "yes" ]; then
    CURRENT_DIR=`pwd`
    info "Building VLCKit.xcframework in ${CURRENT_DIR}"

    buildxcodeproj VLCKit "VLCKit" "macosx"

    spushd build
    rm -rf VLCKit.xcframework
    xcodebuild -create-xcframework -framework VLCKit-macosx.xcarchive/Products/Library/Frameworks/VLCKit.framework -debug-symbols $PROJECT_DIR/build/VLCKit-macosx.xcarchive/dSYMs/VLCKit.framework.dSYM -output VLCKit.xcframework
    spopd # build

    info "Build of VLCKit.xcframework completed"
fi
fi
