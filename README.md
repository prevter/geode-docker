# Geode SDK Docker

![Build Docker Images](https://github.com/prevter/geode-docker/actions/workflows/build-images.yml/badge.svg)
[![Docker Hub](https://img.shields.io/badge/docker-hub-blue?logo=docker)](https://hub.docker.com/r/prevter/geode-sdk)

This repository contains the Dockerfile to build the Geode SDK cross-compilation toolchain
that runs on Linux host and can build mods for Windows, Android, macOS and iOS.

## Available Tags

| Platform     | Tags                                         | Image size |
|--------------|----------------------------------------------|------------|
| Windows      | `windows`, `windows-latest`, `windows-5.9.0` | ![Docker Image Size (tag)](https://img.shields.io/docker/image-size/prevter/geode-sdk/windows?label=%20) |
| Android32/64 | `android`, `android-latest`, `android-5.9.0` | ![Docker Image Size (tag)](https://img.shields.io/docker/image-size/prevter/geode-sdk/android?label=%20) |
| macOS        | `macos`, `macos-latest`, `macos-5.9.0`       | ![Docker Image Size (tag)](https://img.shields.io/docker/image-size/prevter/geode-sdk/macos?label=%20) |
| iOS          | `ios`, `ios-latest`, `ios-5.9.0`             | ![Docker Image Size (tag)](https://img.shields.io/docker/image-size/prevter/geode-sdk/ios?label=%20) |

> [!NOTE]
> The `-latest` tags are an alias for non-tagged builds. `windows` and `windows-latest` are identical.

## Usage

Each image already contains pre-installed Geode SDK and the CLI alongside the toolchains required for that specific platform.

### Windows & Android

Navigate to the root of your mod project and run the following command:

```bash
docker run --rm -it -v "$(pwd):/workspace" -w /workspace prevter/geode-sdk:windows /bin/bash
```
*(replace `windows` with `android` for Android builds)*

This should drop you into a bash shell with configured toolchain. To compile your mod, simply run the geode build command:

```bash
# For Windows
geode build -p windows --config Release -- -G Ninja

# For Android (use android64 or android32)
geode build -p android64 --config Release -- -G Ninja
```

### macOS & iOS

First step is similar to Windows and Android, but you need to use the `macos` or `ios` tag instead:

```bash
docker run --rm -it -v "$(pwd):/workspace" -w /workspace prevter/geode-sdk:macos /bin/bash
```
*(replace `macos` with `ios` for iOS builds)*

`geode build` command doesn't support cross-compiling to Apple platforms yet, so we'll need to use CMake directly. To build your mod for macOS, run the following commands:

```bash
cmake -G Ninja -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

No further configuration is required, CMake already picks up the correct toolchain by default.

## License

This project is licensed under the Boost Software License 1.0. See the [LICENSE](LICENSE.txt) file for details.
