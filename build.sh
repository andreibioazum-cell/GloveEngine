#!/bin/bash
set -e

# Host tools required by the Android build (compiled on the desktop host)
MOBILE_HOST_TOOLS="matc resgen cmgen filamesh uberz"

function print_help {
    local self_name=$(basename "$0")
    echo "Usage:"
    echo "    $self_name [options] <build_type1> [<build_type2> ...] [targets]"
    echo ""
    echo "GloveEngine builds for Android only (API level 29 / Android 10 and up), for the"
    echo "32-bit (armeabi-v7a, x86) and 64-bit (arm64-v8a, x86_64) ABIs."
    echo ""
    echo "Options:"
    echo "    -h"
    echo "        Print this help message."
    echo "    -a"
    echo "        Generate .tgz build archives, implies -i."
    echo "    -c"
    echo "        Clean build directories."
    echo "    -C"
    echo "        Clean build directories and revert android/ to a freshly sync'ed state."
    echo "        All (and only) git-ignored files under android/ are deleted."
    echo "        This is sometimes needed instead of -c (which still misses some clean steps)."
    echo "    -d"
    echo "        Enable matdbg."
    echo "    -t"
    echo "        Enable fgviewer."
    echo "    -u"
    echo "        Enable utils::Mutex debugging (lock-order inversion and self-deadlock detection)."
    echo "    -f"
    echo "        Always invoke CMake before incremental builds."
    echo "    -g"
    echo "        Disable material optimization."
    echo "    -i"
    echo "        Install build output"
    echo "    -m"
    echo "        Compile with make instead of ninja."
    echo "    -q abi1,abi2,..."
    echo "        Where abiN is [armeabi-v7a|arm64-v8a|x86|x86_64|all]."
    echo "        ABIs to build. Defaults to all (32-bit and 64-bit)."
    echo "    -v"
    echo "        Exclude Vulkan support from the Android build."
    echo "    -E"
    echo "        Disable C++ exceptions."
    echo "    -W"
    echo "        Include WebGPU support in the core Filament library. (NOT functional atm)."
    echo "    -k sample1,sample2,..."
    echo "        Also build select sample APKs."
    echo "        sampleN is an Android sample, e.g., sample-gltf-viewer."
    echo "        This automatically performs a partial host build and install."
    echo "    -x value"
    echo "        Define a preprocessor flag FILAMENT_BACKEND_DEBUG_FLAG with [value]. This is useful for"
    echo "        enabling debug paths in the backend from the build script. For example, make a"
    echo "        systrace-enabled build without directly changing #defines. Remember to add -f when"
    echo "        changing this option."
    echo "    -P"
    echo "        Enable perfetto traces on Android. Disabled by default on the Release build, enabled otherwise."
    echo "    -y build_type"
    echo "        Build the filament dependent tools (matc, resgen) separately from the project. This will set"
    echo "        the tools as prebuilts that filament target will then use to build. The build_type option"
    echo "        (debug|release|none) is meant to indicate the type of build of the resulting prebuilts,"
    echo "        or 'none' to disable the split build."
    echo "        Defaults to 'release' (tools are always prebuilt as release unless overridden)."
    echo "    -D"
    echo "        Build Android Markdown documentation using Dokka."
    echo ""
    echo "Build types:"
    echo "    release"
    echo "        Release build only"
    echo "    debug"
    echo "        Debug build only"
    echo ""
    echo "Targets:"
    echo "    Any target supported by the underlying build system"
    echo ""
    echo "Examples:"
    echo "    Android release build:"
    echo "        \$ ./$self_name release"
    echo ""
    echo "    Android debug and release builds:"
    echo "        \$ ./$self_name debug release"
    echo ""
    echo "    Clean, Android debug build and create archive of build artifacts:"
    echo "        \$ ./$self_name -c -a debug"
    echo ""
    echo "    Android release build, arm64-v8a only:"
    echo "        \$ ./$self_name -q arm64-v8a release"
    echo ""
    echo "    Build gltf_viewer sample APK:"
    echo "        \$ ./$self_name -k sample-gltf-viewer release"
    echo ""
}

function print_matdbg_help {
    echo "matdbg is enabled in the build, but some extra steps are needed."
    echo ""
    echo "1) For Android Studio builds, make sure to set:"
    echo "       -Pcom.google.android.filament.matdbg"
    echo "   option in Preferences > Build > Compiler > Command line options."
    echo ""
    echo "2) The port number is hardcoded to 8081 so you will need to do:"
    echo "       adb forward tcp:8081 tcp:8081"
    echo ""
    echo "3) Be sure to enable INTERNET permission in your app's manifest file."
    echo ""
}

function print_fgviewer_help {
    echo "fgviewer is enabled in the build, but some extra steps are needed."
    echo ""
    echo "1) For Android Studio builds, make sure to set:"
    echo "       -Pcom.google.android.filament.fgviewer"
    echo "   option in Preferences > Build > Compiler > Command line options."
    echo ""
    echo "2) The port number is hardcoded to 8085 so you will need to do:"
    echo "       adb forward tcp:8085 tcp:8085"
    echo ""
    echo "3) Be sure to enable INTERNET permission in your app's manifest file."
    echo ""
}

# Unless explicitly specified, NDK version will be selected as highest available version within same major release chain
FILAMENT_NDK_VERSION=$(cat `dirname $0`/build/common/versions | grep GITHUB_NDK_VERSION | sed s/GITHUB_NDK_VERSION=//g | cut -f 1 -d ".")

# Internal variables
ISSUE_CLEAN=false
ISSUE_CLEAN_AGGRESSIVE=false

ISSUE_DEBUG_BUILD=false
ISSUE_RELEASE_BUILD=false

# Default: all 32-bit and 64-bit ABIs
ABI_ARMEABI_V7A=true
ABI_ARM64_V8A=true
ABI_X86=true
ABI_X86_64=true
ABI_GRADLE_OPTION="all"

ISSUE_ARCHIVES=false
BUILD_DOKKA_DOCS=false

ISSUE_CMAKE_ALWAYS=false

ANDROID_SAMPLES=()
BUILD_ANDROID_SAMPLES=false

INSTALL_COMMAND=

VULKAN_ANDROID_OPTION="-DFILAMENT_SUPPORTS_VULKAN=ON"
VULKAN_ANDROID_GRADLE_OPTION=""

WEBGPU_OPTION="-DFILAMENT_SUPPORTS_WEBGPU=OFF"
WEBGPU_ANDROID_GRADLE_OPTION=""

MATDBG_OPTION="-DFILAMENT_ENABLE_MATDBG=OFF"
MATDBG_GRADLE_OPTION=""
FGVIEWER_OPTION="-DFILAMENT_ENABLE_FGVIEWER=OFF"
FGVIEWER_GRADLE_OPTION=""
MUTEX_DEBUG_OPTION="-DFILAMENT_DEBUG_MUTEX=OFF"
MUTEX_DEBUG_GRADLE_OPTION=""

MATOPT_OPTION=""
MATOPT_GRADLE_OPTION=""

ENABLE_PERFETTO=""

BACKEND_DEBUG_FLAG_OPTION=""

ISSUE_SPLIT_BUILD=true
SPLIT_BUILD_TYPE="release"
PREBUILT_TOOLS_DIR=""
IMPORT_EXECUTABLES_DIR_OPTION="-DIMPORT_EXECUTABLES_DIR=out"

BUILD_GENERATOR=Ninja
BUILD_COMMAND=ninja
BUILD_CUSTOM_TARGETS=

UNAME=$(uname)
LC_UNAME=$(echo "${UNAME}" | tr '[:upper:]' '[:lower:]')

# Functions

function build_clean {
    echo "Cleaning build directories..."
    rm -Rf out
    rm -Rf android/filament-android/build android/filament-android/.externalNativeBuild android/filament-android/.cxx
    rm -Rf android/filamat-android/build android/filamat-android/.externalNativeBuild android/filamat-android/.cxx
    rm -Rf android/gltfio-android/build android/gltfio-android/.externalNativeBuild android/gltfio-android/.cxx
    rm -Rf android/filament-utils-android/build android/filament-utils-android/.externalNativeBuild android/filament-utils-android/.cxx
    rm -f compile_commands.json
}

function build_clean_aggressive {
    echo "Cleaning build directories..."
    rm -Rf out
    git clean -qfX android
}

function build_tools_for_split_build {
    local build_type_arg=$1
    local lc_build_type=$(echo "${build_type_arg}" | tr '[:upper:]' '[:lower:]')
    PREBUILT_TOOLS_DIR="out/prebuilt-tools-${lc_build_type}"

    echo "Building tools for split build (${lc_build_type}) in ${PREBUILT_TOOLS_DIR}..."
    mkdir -p "${PREBUILT_TOOLS_DIR}"

    pushd "${PREBUILT_TOOLS_DIR}" > /dev/null

    cmake \
        -G "${BUILD_GENERATOR}" \
        -DFILAMENT_EXPORT_PREBUILT_EXECUTABLES_DIR=${PREBUILT_TOOLS_DIR} \
        -DCMAKE_BUILD_TYPE="${build_type_arg}" \
        ${WEBGPU_OPTION} \
        ${EXCEPTIONS_OPTION} \
        ${MUTEX_DEBUG_OPTION} \
        ../../

    ${BUILD_COMMAND} ${MOBILE_HOST_TOOLS}

    popd > /dev/null
}

function build_desktop_target {
    local lc_target=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    local build_targets=$2

    if [[ ! "${build_targets}" ]]; then
        build_targets=${BUILD_CUSTOM_TARGETS}
    fi

    echo "Building host ${lc_target} in out/cmake-${lc_target}..."
    mkdir -p "out/cmake-${lc_target}"

    pushd "out/cmake-${lc_target}" > /dev/null

    if [[ ! -d "CMakeFiles" ]] || [[ "${ISSUE_CMAKE_ALWAYS}" == "true" ]]; then
        cmake \
            -G "${BUILD_GENERATOR}" \
            ${IMPORT_EXECUTABLES_DIR_OPTION} \
            -DCMAKE_BUILD_TYPE="$1" \
            -DCMAKE_INSTALL_PREFIX="../${lc_target}/filament" \
            ${FGVIEWER_OPTION} \
            ${WEBGPU_OPTION} \
            ${MATDBG_OPTION} \
            ${MATOPT_OPTION} \
            ${BACKEND_DEBUG_FLAG_OPTION} \
            ${EXCEPTIONS_OPTION} \
            ${MUTEX_DEBUG_OPTION} \
            ../../
        ln -sf "out/cmake-${lc_target}/compile_commands.json" \
           ../../compile_commands.json
    fi
    ${BUILD_COMMAND} ${build_targets}

    if [[ "${INSTALL_COMMAND}" ]]; then
        echo "Installing ${lc_target} in out/${lc_target}/filament..."
        ${BUILD_COMMAND} ${INSTALL_COMMAND}
    fi

    popd > /dev/null
}

function build_desktop {
    # The Android build requires host-side tools (matc, resgen, ...), which are
    # built for the desktop as part of this flow.
    if [[ "${ISSUE_DEBUG_BUILD}" == "true" ]]; then
        build_desktop_target "Debug" "$1"
    fi

    if [[ "${ISSUE_RELEASE_BUILD}" == "true" ]]; then
        build_desktop_target "Release" "$1"
    fi
}

function build_android_target {
    local lc_target=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    local arch=$2

    echo "Building Android ${lc_target} (${arch})..."
    mkdir -p "out/cmake-android-${lc_target}-${arch}"

    pushd "out/cmake-android-${lc_target}-${arch}" > /dev/null

    if [[ ! -d "CMakeFiles" ]] || [[ "${ISSUE_CMAKE_ALWAYS}" == "true" ]]; then
        cmake \
            -G "${BUILD_GENERATOR}" \
            ${IMPORT_EXECUTABLES_DIR_OPTION} \
            -DCMAKE_BUILD_TYPE="$1" \
            -DFILAMENT_NDK_VERSION="${FILAMENT_NDK_VERSION}" \
            -DCMAKE_INSTALL_PREFIX="../android-${lc_target}/filament" \
            -DCMAKE_TOOLCHAIN_FILE="../../build/toolchain-${arch}-linux-android.cmake" \
            ${FGVIEWER_OPTION} \
            ${MATDBG_OPTION} \
            ${MATOPT_OPTION} \
            ${VULKAN_ANDROID_OPTION} \
            ${WEBGPU_OPTION} \
            ${BACKEND_DEBUG_FLAG_OPTION} \
            ${ENABLE_PERFETTO} \
            ${EXCEPTIONS_OPTION} \
            ${MUTEX_DEBUG_OPTION} \
            ../../
        ln -sf "out/cmake-android-${lc_target}-${arch}/compile_commands.json" \
           ../../compile_commands.json
    fi

    # We must always install Android libraries to build the AAR
    ${BUILD_COMMAND} install

    popd > /dev/null
}

function build_android_arch {
    local arch=$1

    if [[ "${ISSUE_DEBUG_BUILD}" == "true" ]]; then
        build_android_target "Debug" "${arch}"
    fi

    if [[ "${ISSUE_RELEASE_BUILD}" == "true" ]]; then
        build_android_target "Release" "${arch}"
    fi
}

function archive_android {
    local lc_target=$(echo "$1" | tr '[:upper:]' '[:lower:]')

    if [[ -d "out/android-${lc_target}/filament" ]]; then
        if [[ "${ISSUE_ARCHIVES}" == "true" ]]; then
            echo "Generating out/filament-android-${lc_target}-${LC_UNAME}.tgz..."
            pushd "out/android-${lc_target}" > /dev/null
            tar -czvf "../filament-android-${lc_target}-${LC_UNAME}.tgz" filament
            popd > /dev/null
        fi
    fi
}

function ensure_android_build {
    if [[ "${ANDROID_HOME}" == "" ]]; then
        echo "Error: ANDROID_HOME is not set, exiting"
        exit 1
    fi

    # shellcheck disable=SC2012
    if [[ -z $(ls "${ANDROID_HOME}/ndk/" | sort -V | grep "^${FILAMENT_NDK_VERSION}") ]]; then
        echo "Error: Android NDK side-by-side version ${FILAMENT_NDK_VERSION} or compatible must be installed, exiting"
        exit 1
    fi
}

function build_android {
    ensure_android_build

    # Suppress intermediate desktop tools install
    local old_install_command=${INSTALL_COMMAND}
    INSTALL_COMMAND=

    build_desktop "${MOBILE_HOST_TOOLS}"

    # When building the samples, we need to partially "install" the host tools so Gradle can see
    # them.
    if [[ "${BUILD_ANDROID_SAMPLES}" == "true" ]]; then
        if [[ "${ISSUE_DEBUG_BUILD}" == "true" ]]; then
            mkdir -p out/debug/filament/bin
            for tool in ${MOBILE_HOST_TOOLS}; do
                cp out/cmake-debug/tools/${tool}/${tool} out/debug/filament/bin/
            done
        fi

        if [[ "${ISSUE_RELEASE_BUILD}" == "true" ]]; then
            mkdir -p out/release/filament/bin
            for tool in ${MOBILE_HOST_TOOLS}; do
                cp out/cmake-release/tools/${tool}/${tool} out/release/filament/bin/
            done
        fi
    fi

    INSTALL_COMMAND=${old_install_command}

    if [[ "${ABI_ARM64_V8A}" == "true" ]]; then
        build_android_arch "aarch64" "aarch64-linux-android"
    fi
    if [[ "${ABI_ARMEABI_V7A}" == "true" ]]; then
        build_android_arch "arm7" "arm-linux-androideabi"
    fi
    if [[ "${ABI_X86_64}" == "true" ]]; then
        build_android_arch "x86_64" "x86_64-linux-android"
    fi
    if [[ "${ABI_X86}" == "true" ]]; then
        build_android_arch "x86" "i686-linux-android"
    fi

    if [[ "${ISSUE_DEBUG_BUILD}" == "true" ]]; then
        archive_android "Debug"
    fi

    if [[ "${ISSUE_RELEASE_BUILD}" == "true" ]]; then
        archive_android "Release"
    fi

    local root_dir=$(pwd)

    pushd android > /dev/null

    if [[ "${ISSUE_DEBUG_BUILD}" == "true" ]]; then
        ./gradlew \
            -Pcom.google.android.filament.dist-dir=../out/android-debug/filament \
            -Pcom.google.android.filament.tools-dir=${root_dir}/out/debug/filament \
            -Pcom.google.android.filament.abis=${ABI_GRADLE_OPTION} \
            ${VULKAN_ANDROID_GRADLE_OPTION} \
            ${WEBGPU_ANDROID_GRADLE_OPTION} \
            ${MATDBG_GRADLE_OPTION} \
            ${FGVIEWER_GRADLE_OPTION} \
            ${MATOPT_GRADLE_OPTION} \
            ${MUTEX_DEBUG_GRADLE_OPTION} \
            :filament-android:assembleDebug \
            :gltfio-android:assembleDebug \
            :filament-utils-android:assembleDebug

        ./gradlew \
            -Pcom.google.android.filament.dist-dir=../out/android-debug/filament \
            -Pcom.google.android.filament.tools-dir=${root_dir}/out/debug/filament \
            -Pcom.google.android.filament.abis=${ABI_GRADLE_OPTION} \
            ${WEBGPU_ANDROID_GRADLE_OPTION} \
            :filamat-android:assembleDebug

        if [[ "${BUILD_ANDROID_SAMPLES}" == "true" ]]; then
            for sample in ${ANDROID_SAMPLES}; do
                ./gradlew \
                    -Pcom.google.android.filament.dist-dir=../out/android-debug/filament \
                   -Pcom.google.android.filament.tools-dir=${root_dir}/out/debug/filament \
                    -Pcom.google.android.filament.abis=${ABI_GRADLE_OPTION} \
                    ${MATOPT_GRADLE_OPTION} \
                    :samples:${sample}:assembleDebug
            done
        fi

        if [[ "${INSTALL_COMMAND}" ]]; then
            echo "Installing out/filamat-android-debug.aar..."
            cp filamat-android/build/outputs/aar/filamat-android-debug.aar ../out/filamat-android-debug.aar

            echo "Installing out/filament-android-debug.aar..."
            cp filament-android/build/outputs/aar/filament-android-debug.aar ../out/

            echo "Installing out/gltfio-android-debug.aar..."
            cp gltfio-android/build/outputs/aar/gltfio-android-debug.aar ../out/gltfio-android-debug.aar

            echo "Installing out/filament-utils-android-debug.aar..."
            cp filament-utils-android/build/outputs/aar/filament-utils-android-debug.aar ../out/filament-utils-android-debug.aar

            if [[ "${BUILD_ANDROID_SAMPLES}" == "true" ]]; then
                for sample in ${ANDROID_SAMPLES}; do
                    echo "Installing out/${sample}-debug.apk"
                    cp samples/${sample}/build/outputs/apk/debug/${sample}-debug.apk \
                        ../out/${sample}-debug.apk
                done
            fi
        fi
    fi

    if [[ "${ISSUE_RELEASE_BUILD}" == "true" ]]; then
        ./gradlew \
            -Pcom.google.android.filament.dist-dir=../out/android-release/filament \
            -Pcom.google.android.filament.tools-dir=${root_dir}/out/release/filament \
            -Pcom.google.android.filament.abis=${ABI_GRADLE_OPTION} \
            ${VULKAN_ANDROID_GRADLE_OPTION} \
            ${WEBGPU_ANDROID_GRADLE_OPTION} \
            ${MATDBG_GRADLE_OPTION} \
            ${FGVIEWER_GRADLE_OPTION} \
            ${MATOPT_GRADLE_OPTION} \
            ${MUTEX_DEBUG_GRADLE_OPTION} \
            :filament-android:assembleRelease \
            :gltfio-android:assembleRelease \
            :filament-utils-android:assembleRelease

        ./gradlew \
            -Pcom.google.android.filament.dist-dir=../out/android-release/filament \
            -Pcom.google.android.filament.tools-dir=${root_dir}/out/release/filament \
            -Pcom.google.android.filament.abis=${ABI_GRADLE_OPTION} \
            ${WEBGPU_ANDROID_GRADLE_OPTION} \
            :filamat-android:assembleRelease

        if [[ "${BUILD_ANDROID_SAMPLES}" == "true" ]]; then
            for sample in ${ANDROID_SAMPLES}; do
                ./gradlew \
                    -Pcom.google.android.filament.dist-dir=../out/android-release/filament \
                    -Pcom.google.android.filament.tools-dir=${root_dir}/out/release/filament \
                    -Pcom.google.android.filament.abis=${ABI_GRADLE_OPTION} \
                    ${MATOPT_GRADLE_OPTION} \
                    :samples:${sample}:assembleRelease
            done
        fi

        if [[ "${INSTALL_COMMAND}" ]]; then
            echo "Installing out/filamat-android-release.aar..."
            cp filamat-android/build/outputs/aar/filamat-android-release.aar ../out/filamat-android-release.aar

            echo "Installing out/filament-android-release.aar..."
            cp filament-android/build/outputs/aar/filament-android-release.aar ../out/

            echo "Installing out/gltfio-android-release.aar..."
            cp gltfio-android/build/outputs/aar/gltfio-android-release.aar ../out/gltfio-android-release.aar

            echo "Installing out/filament-utils-android-release.aar..."
            cp filament-utils-android/build/outputs/aar/filament-utils-android-release.aar ../out/filament-utils-android-release.aar

            if [[ "${BUILD_ANDROID_SAMPLES}" == "true" ]]; then
                for sample in ${ANDROID_SAMPLES}; do
                    echo "Installing out/${sample}-release.apk"
                    cp samples/${sample}/build/outputs/apk/release/${sample}-release-unsigned.apk \
                        ../out/${sample}-release.apk
                done
            fi
        fi
    fi

    popd > /dev/null
}

function validate_build_command {
    set +e
    # Make sure CMake is installed
    local cmake_binary=$(command -v cmake)
    if [[ ! "${cmake_binary}" ]]; then
        echo "Error: could not find cmake, exiting"
        exit 1
    fi

    # Make sure Ninja is installed
    if [[ "${BUILD_COMMAND}" == "ninja" ]]; then
        local ninja_binary=$(command -v ninja)
        if [[ ! "${ninja_binary}" ]]; then
            echo "Warning: could not find ninja, using make instead"
            BUILD_GENERATOR="Unix Makefiles"
            BUILD_COMMAND="make"
        fi
    fi
    # Make sure Make is installed
    if [[ "${BUILD_COMMAND}" == "make" ]]; then
        local make_binary=$(command -v make)
        if [[ ! "${make_binary}" ]]; then
            echo "Error: could not find make, exiting"
            exit 1
        fi
    fi

    # Make sure ANDROID_HOME is available
    if [[ "${ANDROID_HOME}" == "" ]]; then
        echo "Error: ANDROID_HOME is not set, exiting"
        exit 1
    fi

    # Make sure FILAMENT_BACKEND_DEBUG_FLAG is only meant for debug builds
    if [[ "${ISSUE_DEBUG_BUILD}" != "true" ]] && [[ ! -z "${BACKEND_DEBUG_FLAG_OPTION}" ]]; then
        echo "Error: cannot specify FILAMENT_BACKEND_DEBUG_FLAG in non-debug build"
        exit 1
    fi

    set -e
}

function check_debug_release_build {
    if [[ "${ISSUE_DEBUG_BUILD}" == "true" || \
          "${ISSUE_RELEASE_BUILD}" == "true" || \
          "${ISSUE_CLEAN}" == "true" ]]; then
        "$@";
    else
        echo "You must declare a debug or release target for $@ builds."
        echo ""
        exit 1
    fi
}

# Beginning of the script

pushd "$(dirname "$0")" > /dev/null

while getopts ":hacCfgDitmdq:uvk:WEPy:x:" opt; do
    case ${opt} in
        h)
            print_help
            exit 0
            ;;
        a)
            ISSUE_ARCHIVES=true
            INSTALL_COMMAND=install
            ;;
        c)
            ISSUE_CLEAN=true
            ;;
        C)
            ISSUE_CLEAN_AGGRESSIVE=true
            ;;
        d)
            PRINT_MATDBG_HELP=true
            MATDBG_OPTION="-DFILAMENT_ENABLE_MATDBG=ON, -DFILAMENT_BUILD_FILAMAT=ON"
            MATDBG_GRADLE_OPTION="-Pcom.google.android.filament.matdbg"
            ;;
        t)
            PRINT_FGVIEWER_HELP=true
            FGVIEWER_OPTION="-DFILAMENT_ENABLE_FGVIEWER=ON"
            FGVIEWER_GRADLE_OPTION="-Pcom.google.android.filament.fgviewer"
            ;;
        u)
            MUTEX_DEBUG_OPTION="-DFILAMENT_DEBUG_MUTEX=ON"
            MUTEX_DEBUG_GRADLE_OPTION="-Pcom.google.android.filament.mutexdebug"
            echo "Enabled utils::Mutex debugging"
            ;;
        f)
            ISSUE_CMAKE_ALWAYS=true
            ;;
        g)
            MATOPT_OPTION="-DFILAMENT_DISABLE_MATOPT=ON"
            MATOPT_GRADLE_OPTION="-Pcom.google.android.filament.matnopt"
            ;;
        i)
            INSTALL_COMMAND=install
            ;;
        m)
            BUILD_GENERATOR="Unix Makefiles"
            BUILD_COMMAND="make"
            ;;
        q)
            ABI_ARMEABI_V7A=false
            ABI_ARM64_V8A=false
            ABI_X86=false
            ABI_X86_64=false
            ABI_GRADLE_OPTION="${OPTARG}"
            abis=$(echo "${OPTARG}" | tr ',' '\n')
            for abi in ${abis}
            do
                case $(echo "${abi}" | tr '[:upper:]' '[:lower:]') in
                    armeabi-v7a)
                        ABI_ARMEABI_V7A=true
                    ;;
                    arm64-v8a)
                        ABI_ARM64_V8A=true
                    ;;
                    x86)
                        ABI_X86=true
                    ;;
                    x86_64)
                        ABI_X86_64=true
                    ;;
                    all)
                        ABI_ARMEABI_V7A=true
                        ABI_ARM64_V8A=true
                        ABI_X86=true
                        ABI_X86_64=true
                    ;;
                    *)
                        echo "Unknown abi ${abi}"
                        echo "ABI must be one of [armeabi-v7a|arm64-v8a|x86|x86_64|all]"
                        echo ""
                        exit 1
                    ;;
                esac
            done
            ;;
        v)
            VULKAN_ANDROID_OPTION="-DFILAMENT_SUPPORTS_VULKAN=OFF"
            VULKAN_ANDROID_GRADLE_OPTION="-Pcom.google.android.filament.exclude-vulkan"
            echo "Disabling support for Vulkan in the core Filament library."
            echo "Consider using -c after changing this option to clear the Gradle cache."
            ;;
        W)
            WEBGPU_OPTION='-DFILAMENT_SUPPORTS_WEBGPU=ON'

            WEBGPU_ANDROID_GRADLE_OPTION="-Pcom.google.android.filament.include-webgpu"
            echo "Enable support for WebGPU(Experimental) in the core Filament library."
            ;;
        k)
            BUILD_ANDROID_SAMPLES=true
            ANDROID_SAMPLES=$(echo "${OPTARG}" | tr ',' '\n')
            ;;
        P)  ENABLE_PERFETTO="-DFILAMENT_ENABLE_PERFETTO=ON"
            echo "Enabled perfetto"
            ;;
        E)  EXCEPTIONS_OPTION="-DFILAMENT_ENABLE_EXCEPTIONS=OFF"
            echo "Disabling exceptions."
            ;;
        x)  BACKEND_DEBUG_FLAG_OPTION="-DFILAMENT_BACKEND_DEBUG_FLAG=${OPTARG}"
            ;;
        D)
            BUILD_DOKKA_DOCS=true
            ;;
        y)
            SPLIT_BUILD_TYPE=${OPTARG}
            case $(echo "${SPLIT_BUILD_TYPE}" | tr '[:upper:]' '[:lower:]') in
                debug|release)
                    ISSUE_SPLIT_BUILD=true
                    ;;
                none)
                    ISSUE_SPLIT_BUILD=false
                    ;;
                *)
                    echo "Unknown build type for -y: ${SPLIT_BUILD_TYPE}"
                    echo "Build type must be one of [debug|release|none]"
                    echo ""
                    exit 1
                    ;;
            esac
            ;;
        \?)
            echo "Invalid option: -${OPTARG}" >&2
            echo ""
            print_help
            exit 1
            ;;
        :)
            echo "Option -${OPTARG} requires an argument." >&2
            echo ""
            print_help
            exit 1
            ;;
    esac
done

if [[ "$#" == "0" ]] && [[ "${BUILD_DOKKA_DOCS}" != "true" ]]; then
    print_help
    exit 1
fi

shift $((OPTIND - 1))

for arg; do
    if [[ $(echo "${arg}" | tr '[:upper:]' '[:lower:]') == "release" ]]; then
        ISSUE_RELEASE_BUILD=true
    elif [[ $(echo "${arg}" | tr '[:upper:]' '[:lower:]') == "debug" ]]; then
        ISSUE_DEBUG_BUILD=true
    else
        BUILD_CUSTOM_TARGETS="${BUILD_CUSTOM_TARGETS} ${arg}"
    fi
done

validate_build_command

if [[ "${ISSUE_CLEAN}" == "true" ]]; then
    build_clean
fi

if [[ "${ISSUE_CLEAN_AGGRESSIVE}" == "true" ]]; then
    build_clean_aggressive
fi

# Only runs the split build for tools if an actual debug or release build is requested.
# This prevents the split build from being triggered when a clean (-c or -C) is requested.
if [[ "${ISSUE_SPLIT_BUILD}" == "true" ]] && \
   [[ "${ISSUE_DEBUG_BUILD}" == "true" || "${ISSUE_RELEASE_BUILD}" == "true" ]]; then
    # Capitalize first letter of SPLIT_BUILD_TYPE
    SPLIT_BUILD_TYPE_CAPITALIZED="$(echo ${SPLIT_BUILD_TYPE:0:1} | tr '[:lower:]' '[:upper:]')${SPLIT_BUILD_TYPE:1}"
    build_tools_for_split_build "${SPLIT_BUILD_TYPE_CAPITALIZED}"
    IMPORT_EXECUTABLES_DIR_OPTION="-DFILAMENT_IMPORT_PREBUILT_EXECUTABLES_DIR=${PREBUILT_TOOLS_DIR}"
fi

check_debug_release_build build_android

if [[ "${BUILD_DOKKA_DOCS}" == "true" ]]; then
    echo "Generating Android Markdown documentation using Dokka..."
    pushd android > /dev/null
    ./gradlew filament-android:dokkaGfm
    popd > /dev/null
fi

if [[ "${PRINT_MATDBG_HELP}" == "true" ]]; then
    print_matdbg_help
fi

if [[ "${PRINT_FGVIEWER_HELP}" == "true" ]]; then
    print_fgviewer_help
fi
