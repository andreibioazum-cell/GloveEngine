# GloveEngine

GloveEngine is a real-time physically based rendering engine for **Android**,
based on [Google Filament](https://github.com/google/filament).

The repository is configured for Android only:

| | |
| --- | --- |
| Minimum Android version | Android 10 (API level 29) |
| Architectures | 64-bit: `arm64-v8a`, `x86_64` · 32-bit: `armeabi-v7a`, `x86` |
| GPU backends | OpenGL ES 3.0 and Vulkan |

## Prerequisites

* CMake (3.19 or newer) and Ninja (or Make)
* Android SDK with `ANDROID_HOME` set, including NDK `29.0.14206865`
  (the exact version is pinned in `build/common/versions` and `android/build.gradle`)
* JDK 21 for the Gradle builds

## Building

Everything is built from the repository root:

```bash
# Release build for all ABIs (arm64-v8a, armeabi-v7a, x86_64, x86)
./build.sh release

# Debug build
./build.sh debug

# Only specific ABIs, e.g. the two 64-bit ones
./build.sh -q arm64-v8a,x86_64 release
```

The build first compiles the host-side tools (`matc`, `resgen`, `cmgen`,
`filamesh`, `uberz`) and then cross-compiles the engine for every requested
ABI. Gradle then packages the AARs. Outputs land in `out/`:

* `out/filament-android-release.aar` — the engine itself
* `out/gltfio-android-release.aar` — glTF 2.0 loader
* `out/filament-utils-android-release.aar` — KTX loading and camera utilities
* `out/filamat-android-release.aar` — runtime material builder/compiler
* `out/android-release/filament/` — headers, libraries per ABI and host tools

Useful options (`./build.sh -h` for the full list):

* `-q armeabi-v7a,arm64-v8a,x86,x86_64|all` — ABIs to build (default: all)
* `-v` — exclude Vulkan support
* `-k sample-gltf-viewer` — also build a sample APK
* `-c` / `-C` — clean build directories
* `-a` / `-i` — archive / install the build output

You can also build only the Gradle part if the native libraries are already
built (for example from a previous `./build.sh` run):

```bash
cd android
./gradlew -Pcom.google.android.filament.dist-dir=../out/android-release/filament \
          -Pcom.google.android.filament.tools-dir=../out/release/filament \
          :filament-android:assembleRelease
```

## Using the engine in an app

Add the AARs produced by the build (or copy the contents of
`out/android-release/filament` and link against the static/shared libraries):

```gradle
dependencies {
    implementation files('libs/filament-android-release.aar')
    implementation files('libs/gltfio-android-release.aar')
}
```

Sample Android apps live in `android/samples/`.

## Repository layout

| Directory | Description |
| --- | --- |
| `android/` | Android AAR modules and samples (Gradle) |
| `filament/`, `libs/` | Engine core (C++) |
| `shaders/` | Shader sources |
| `tools/` | Host-side build tools (`matc`, ...) |
| `third_party/` | Third-party dependencies |
| `build/` | Android NDK toolchain files and build scripts |

## License

The engine is licensed under the Apache License 2.0 — see [LICENSE](LICENSE).
