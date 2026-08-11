# syntax=docker/dockerfile:1.7
ARG UBUNTU_VERSION=26.04
ARG OSXCROSS_VERSION=latest
ARG LLVM_VERSION=22

FROM crazymax/osxcross:${OSXCROSS_VERSION}-ubuntu AS osxcross
FROM ubuntu:${UBUNTU_VERSION} AS toolchain-base

ARG LLVM_VERSION

# ===============================
# Common environment setup
# ===============================
ENV DEBIAN_FRONTEND=noninteractive \
    GEODE_SDK=/opt/geode \
    PATH=/opt/geode-cli:$PATH

# ===============================
# Base system and toolchain
# ===============================
RUN set -eux; \
    NODE_VERSION=24; \
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl gpg nodejs git unzip xz-utils \
        build-essential cmake pkg-config ninja-build jq; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    install -d /etc/apt/keyrings; \
    curl -fsSL https://apt.llvm.org/llvm-snapshot.gpg.key | gpg --dearmor -o /etc/apt/keyrings/llvm.gpg; \
    echo "deb [signed-by=/etc/apt/keyrings/llvm.gpg] http://apt.llvm.org/resolute/ llvm-toolchain-resolute-${LLVM_VERSION} main" > /etc/apt/sources.list.d/llvm.list

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        clang-${LLVM_VERSION} clang-tools-${LLVM_VERSION} lld-${LLVM_VERSION} \
        llvm-${LLVM_VERSION} llvm-${LLVM_VERSION}-dev; \
    rm -rf /var/lib/apt/lists/*

RUN for tool in clang clang++ lld lld-link llvm-ar llvm-ranlib llvm-nm llvm-rc llvm-mt; do \
    ln -sf /usr/bin/${tool}-${LLVM_VERSION} /usr/bin/${tool}; \
    done

# ===============================
# Install Geode CLI
# ===============================
FROM toolchain-base AS geode-sdk-base

ARG GEODE_CLI_VERSION=latest
ARG GEODE_SDK_VERSION=latest
ARG TARGETARCH

RUN --mount=type=secret,id=GITHUB_TOKEN \
    set -eux; \
    GITHUB_TOKEN=$(cat /run/secrets/GITHUB_TOKEN 2>/dev/null || true); \
    AUTH_HEADER=""; \
    if [ -n "$GITHUB_TOKEN" ]; then \
        AUTH_HEADER="Authorization: Bearer $GITHUB_TOKEN"; \
    fi; \
    if [ "${GEODE_CLI_VERSION}" = "latest" ]; then \
        GEODE_CLI_VERSION="$(curl -fsSL ${AUTH_HEADER:+-H "$AUTH_HEADER"} https://api.github.com/repos/geode-sdk/cli/releases/latest \
            | grep -Po '"tag_name":\s*"\Kv[^"]+')"; \
    fi; \
    echo "Installing Geode CLI ${GEODE_CLI_VERSION}"; \
    if [ "${TARGETARCH}" = "arm64" ]; then \
        CLI_SUFFIX="linux-arm"; \
    else \
        CLI_SUFFIX="linux"; \
    fi; \
    curl -fsSL "https://github.com/geode-sdk/cli/releases/download/${GEODE_CLI_VERSION}/geode-cli-${GEODE_CLI_VERSION}-${CLI_SUFFIX}.zip" -o /tmp/geode-cli.zip; \
    unzip -q /tmp/geode-cli.zip -d /opt/geode-cli; \
    rm /tmp/geode-cli.zip; \
    chmod +x /opt/geode-cli/geode; \
    ln -sf /opt/geode-cli/geode /usr/local/bin/geode

# ===============================
# Configure Geode profile
# ===============================
RUN set -eux; \
    CLI_PROFILE="/root/.config/geode"; \
    mkdir -p "${CLI_PROFILE}/geode/mods" "${CLI_PROFILE}/Contents/geode/mods"; \
    geode profile add --name DockerProfile "${CLI_PROFILE}/GeometryDash.exe" win

# ===============================
# Install Geode SDK
# ===============================
RUN set -eux; \
    echo "Installing Geode SDK ${GEODE_SDK_VERSION}"; \
    geode sdk install "${GEODE_SDK}"; \
    case "${GEODE_SDK_VERSION}" in \
        nightly) geode sdk update nightly ;; \
        latest)  geode sdk update stable ;; \
        *)       geode sdk update "${GEODE_SDK_VERSION}" ;; \
    esac; \
    echo "GEODE_SDK=${GEODE_SDK}" >> /etc/environment


# ===============================
# Windows image (LLVM/Clang toolchain + Windows binaries)
# ===============================
FROM geode-sdk-base AS geode-sdk-windows

RUN set -eux; \
    geode sdk install-linux

RUN set -eux; \
    geode sdk install-binaries -p windows


# ===============================
# Android image (Android NDK + Android binaries)
# ===============================
FROM toolchain-base AS android-toolchain

ARG ANDROID_NDK_VERSION=r29
ARG TARGETARCH
ENV ANDROID_NDK_ROOT=/opt/android-ndk

RUN set -eux; \
    if [ "${TARGETARCH}" = "arm64" ]; then \
        echo "Installing Android NDK for aarch64"; \
        curl -fsSL "https://github.com/SnowNF/ndk-aarch64-linux/releases/download/0.0.2/android-ndk-r29-linux-aarch64.tar.gz" -o /tmp/android-ndk.tar.gz; \
        mkdir -p "${ANDROID_NDK_ROOT}"; \
        tar -xzf /tmp/android-ndk.tar.gz -C "${ANDROID_NDK_ROOT}" --strip-components=1; \
        rm /tmp/android-ndk.tar.gz; \
    else \
        echo "Installing Android NDK ${ANDROID_NDK_VERSION}"; \
        curl -fsSL "https://dl.google.com/android/repository/android-ndk-${ANDROID_NDK_VERSION}-linux.zip" -o /tmp/android-ndk.zip; \
        unzip -q /tmp/android-ndk.zip -d /opt; \
        rm /tmp/android-ndk.zip; \
        mv "/opt/android-ndk-${ANDROID_NDK_VERSION}" "${ANDROID_NDK_ROOT}"; \
    fi; \
    echo "ANDROID_NDK_ROOT=${ANDROID_NDK_ROOT}" >> /etc/environment

FROM geode-sdk-base AS geode-sdk-android
COPY --from=android-toolchain /opt/android-ndk /opt/android-ndk
ENV ANDROID_NDK_ROOT=/opt/android-ndk

RUN set -eux; \
    geode sdk install-binaries -p android32; \
    geode sdk install-binaries -p android64


# ===============================
# macOS image (osxcross + macOS binaries)
# ===============================
FROM geode-sdk-base AS geode-sdk-macos

COPY --from=osxcross /osxcross /osxcross

ENV PATH="/osxcross/bin:${PATH}" \
    LD_LIBRARY_PATH="/osxcross/lib:${LD_LIBRARY_PATH}"

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends libxml2-utils; \
    rm -rf /var/lib/apt/lists/*; \
    SYS_LIBXML=$(find /usr/lib/ -name "libxml2.so.*" | head -1); \
    if [ -n "$SYS_LIBXML" ]; then \
        ln -sf "$SYS_LIBXML" $(dirname "$SYS_LIBXML")/libxml2.so.2; \
    fi;

RUN set -eux; \
    OSXCROSS_TARGET=$(ls /osxcross/bin/*-apple-darwin*-clang | head -1 | xargs basename | sed 's/-clang$//'); \
    SDK_PATH=$(ls -d /osxcross/SDK/*.sdk | head -1); \
    cat > /osxcross/macos-toolchain.cmake <<EOF
set(CMAKE_SYSTEM_NAME Darwin)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
if(NOT DEFINED CMAKE_OSX_DEPLOYMENT_TARGET)
    set(CMAKE_OSX_DEPLOYMENT_TARGET 11.0)
endif()
set(CMAKE_OSX_SYSROOT ${SDK_PATH})
set(CMAKE_C_COMPILER /osxcross/bin/${OSXCROSS_TARGET}-clang)
set(CMAKE_CXX_COMPILER /osxcross/bin/${OSXCROSS_TARGET}-clang++)
set(CMAKE_AR /osxcross/bin/${OSXCROSS_TARGET}-ar)
set(CMAKE_RANLIB /osxcross/bin/${OSXCROSS_TARGET}-ranlib)
set(CMAKE_FIND_ROOT_PATH /osxcross)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
EOF

RUN set -eux; \
    OSXCROSS_TARGET=$(ls /osxcross/bin/*-apple-darwin*-clang | head -1 | xargs basename | sed 's/-clang$//'); \
    echo "export CC=/osxcross/bin/${OSXCROSS_TARGET}-clang" >> /etc/profile.d/osxcross.sh; \
    echo "export CXX=/osxcross/bin/${OSXCROSS_TARGET}-clang++" >> /etc/profile.d/osxcross.sh; \
    echo "export CMAKE_TOOLCHAIN_FILE=/osxcross/macos-toolchain.cmake" >> /etc/profile.d/osxcross.sh

ENV CC="/osxcross/bin/x86_64-apple-darwin23-clang" \
    CXX="/osxcross/bin/x86_64-apple-darwin23-clang++" \
    CMAKE_TOOLCHAIN_FILE="/osxcross/macos-toolchain.cmake"

RUN set -eux; \
    CLI_PROFILE="/root/.config/geode"; \
    geode profile add --name DockerProfileMac "${CLI_PROFILE}/GeometryDash" mac

RUN set -eux; \
    geode sdk install-binaries -p mac


# ===============================
# iOS image (osxcross + iPhoneOS SDK)
# ===============================
FROM toolchain-base AS ios-toolchain

ENV OSXCROSS=/osxcross \
    THEOS=/opt/theos \
    PATH="${OSXCROSS}/target/bin:${PATH}"

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libxml2-dev uuid-dev libssl-dev \
        bash patch make xz-utils bzip2 cpio zlib1g-dev; \
    rm -rf /var/lib/apt/lists/*

COPY ios-sdk.tar.xz /tmp/ios-sdk.tar.xz

RUN set -eux; \
    git clone --depth 1 https://github.com/tpoechtrager/osxcross "${OSXCROSS}"; \
    cd "${OSXCROSS}"; \
    sed -i 's/"-mmacosx-version-min"/"-miphoneos-version-min"/g' wrapper/main.cpp; \
    sed -i 's/"-mmacos-version-min"/"-miphoneos-version-min"/g' wrapper/main.cpp; \
    sed -i '/if (!detectTarget(argc, argv, target)) {/i \
  for (auto it = target.fargs.begin(); it != target.fargs.end();) {\
    if (it->find("-mmacosx-version-min") == 0 || it->find("-mmacos-version-min") == 0) {\
      it = target.fargs.erase(it);\
    } else {\
      ++it;\
    }\
  }' wrapper/main.cpp; \
    sed -i 's/set(CMAKE_SYSTEM_NAME "Darwin")/set(CMAKE_SYSTEM_NAME "iOS")/g' tools/toolchain.cmake

RUN set -eux; \
    mkdir -p /tmp/sdk-extract; \
    tar -xf /tmp/ios-sdk.tar.xz -C /tmp/sdk-extract; \
    SDK_DIR=$(ls -d /tmp/sdk-extract/*.sdk | head -1); \
    SDK_VERSION=$(grep -A 1 "ProductVersion" "${SDK_DIR}/System/Library/CoreServices/SystemVersion.plist" 2>/dev/null | tail -1 | sed 's/.*<string>\(.*\)<\/string>.*/\1/' | cut -d. -f1-2 || echo "18.0"); \
    mv "${SDK_DIR}" "/tmp/sdk-extract/MacOSX${SDK_VERSION}.sdk"; \
    tar -cJf "${OSXCROSS}/tarballs/MacOSX${SDK_VERSION}.sdk.tar.xz" -C /tmp/sdk-extract "MacOSX${SDK_VERSION}.sdk"; \
    rm -rf /tmp/sdk-extract

RUN set -eux; \
    cd "${OSXCROSS}"; \
    echo "1" | UNATTENDED=yes ./build.sh; \
    rm -rf target/SDK/MacOSX*.sdk; \
    git clone --depth 1 https://github.com/theos/theos "${THEOS}"; \
    tar -xf /tmp/ios-sdk.tar.xz -C "${THEOS}/sdks"; \
    SDK_NAME=$(ls "${THEOS}/sdks" | grep '\.sdk' | head -1); \
    ln -sf "${THEOS}/sdks/${SDK_NAME}" "${OSXCROSS}/target/SDK/${SDK_NAME}"; \
    ln -sf "${THEOS}/sdks/${SDK_NAME}" "${OSXCROSS}/target/SDK/MacOSX26.1.sdk"; \
    rm /tmp/ios-sdk.tar.xz

FROM geode-sdk-base AS geode-sdk-ios

COPY --from=ios-toolchain /osxcross /osxcross
COPY --from=ios-toolchain /opt/theos /opt/theos

ENV OSXCROSS=/osxcross \
    THEOS=/opt/theos \
    PATH="/osxcross/target/bin:${PATH}"

RUN set -eux; \
    sed -i '/is not an iOS SDK/d; /message(FATAL_ERROR/d' /usr/share/cmake-*/Modules/Platform/iOS-Initialize.cmake; \
    SDK_NAME=$(ls "${THEOS}/sdks" | grep '\.sdk' | head -1); \
    cat > /osxcross/ios-toolchain.cmake <<EOF
set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_SYSTEM_PROCESSOR arm64)
set(CMAKE_OSX_ARCHITECTURES arm64)
set(CMAKE_OSX_DEPLOYMENT_TARGET "14.0")
set(CMAKE_OSX_SYSROOT ${THEOS}/sdks/${SDK_NAME})
set(CMAKE_C_COMPILER ${OSXCROSS}/target/bin/arm64-apple-darwin25.1-clang)
set(CMAKE_CXX_COMPILER ${OSXCROSS}/target/bin/arm64-apple-darwin25.1-clang++)
set(CMAKE_OBJC_COMPILER ${OSXCROSS}/target/bin/arm64-apple-darwin25.1-clang)
set(CMAKE_OBJCXX_COMPILER ${OSXCROSS}/target/bin/arm64-apple-darwin25.1-clang++)
set(FLAGS "-target arm64-apple-ios14.0 -miphoneos-version-min=14.0 -Wno-overriding-option")
set(CMAKE_C_FLAGS_INIT "\${FLAGS}")
set(CMAKE_CXX_FLAGS_INIT "\${FLAGS}")
set(CMAKE_OBJC_FLAGS_INIT "\${FLAGS}")
set(CMAKE_OBJCXX_FLAGS_INIT "\${FLAGS}")
set(CMAKE_C_LINK_FLAGS "-fuse-ld=${OSXCROSS}/target/bin/arm64-apple-darwin25.1-ld")
set(CMAKE_CXX_LINK_FLAGS "-fuse-ld=${OSXCROSS}/target/bin/arm64-apple-darwin25.1-ld")
set(CMAKE_OBJC_LINK_FLAGS "-fuse-ld=${OSXCROSS}/target/bin/arm64-apple-darwin25.1-ld")
set(CMAKE_OBJCXX_LINK_FLAGS "-fuse-ld=${OSXCROSS}/target/bin/arm64-apple-darwin25.1-ld")
set(CMAKE_EXE_LINKER_FLAGS_INIT "-fuse-ld=${OSXCROSS}/target/bin/arm64-apple-darwin25.1-ld")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "-fuse-ld=${OSXCROSS}/target/bin/arm64-apple-darwin25.1-ld")
set(CMAKE_MODULE_LINKER_FLAGS_INIT "-fuse-ld=${OSXCROSS}/target/bin/arm64-apple-darwin25.1-ld")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
EOF

ENV CC="${OSXCROSS}/target/bin/arm64-apple-darwin25.1-clang" \
    CXX="${OSXCROSS}/target/bin/arm64-apple-darwin25.1-clang++" \
    LDFLAGS="-fuse-ld=${OSXCROSS}/target/bin/arm64-apple-darwin25.1-ld" \
    CMAKE_TOOLCHAIN_FILE="/osxcross/ios-toolchain.cmake"

RUN geode sdk install-binaries -p ios
