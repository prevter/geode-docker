# syntax=docker/dockerfile:1.7
ARG UBUNTU_VERSION=24.04
ARG OSXCROSS_VERSION=latest

FROM crazymax/osxcross:${OSXCROSS_VERSION}-ubuntu AS osxcross
FROM ubuntu:${UBUNTU_VERSION} AS geode-sdk-base

# ===============================
# Common environment setup
# ===============================
ENV DEBIAN_FRONTEND=noninteractive \
    GEODE_SDK=/opt/geode \
    CPM_SOURCE_CACHE=/opt/cpm-cache \
    PATH=/opt/geode-cli:$PATH

# ===============================
# Base system and toolchain
# ===============================
RUN set -eux; \
    NODE_VERSION=24; \
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl nodejs git unzip xz-utils \
        build-essential cmake pkg-config ninja-build; \
    rm -rf /var/lib/apt/lists/*

# ===============================
# Install Geode CLI
# ===============================
ARG GEODE_CLI_VERSION=latest
RUN set -eux; \
    if [ "${GEODE_CLI_VERSION}" = "latest" ]; then \
        GEODE_CLI_VERSION="$(curl -fsSL https://api.github.com/repos/geode-sdk/cli/releases/latest \
            | grep -Po '"tag_name":\s*"\Kv[^"]+')"; \
    fi; \
    echo "Installing Geode CLI ${GEODE_CLI_VERSION}"; \
    curl -fsSL "https://github.com/geode-sdk/cli/releases/download/${GEODE_CLI_VERSION}/geode-cli-${GEODE_CLI_VERSION}-linux.zip" -o /tmp/geode-cli.zip; \
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
ARG GEODE_SDK_VERSION=latest
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

ARG LLVM_VERSION=20

RUN set -eux; \
    geode sdk install-linux

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        clang-${LLVM_VERSION} clang-tools-${LLVM_VERSION} lld-${LLVM_VERSION} llvm-${LLVM_VERSION}; \
    rm -rf /var/lib/apt/lists/*

RUN for tool in clang clang++ lld lld-link llvm-ar llvm-ranlib llvm-nm llvm-rc llvm-mt; do \
    ln -sf /usr/bin/${tool}-${LLVM_VERSION} /usr/bin/${tool}; \
    done

RUN set -eux; \
    geode sdk install-binaries -p windows


# ===============================
# Android image (Android NDK + Android binaries)
# ===============================
FROM geode-sdk-base AS geode-sdk-android

ARG ANDROID_NDK_VERSION=r29
ENV ANDROID_NDK_ROOT=/opt/android-ndk
RUN set -eux; \
    echo "Installing Android NDK ${ANDROID_NDK_VERSION}"; \
    curl -fsSL "https://dl.google.com/android/repository/android-ndk-${ANDROID_NDK_VERSION}-linux.zip" -o /tmp/android-ndk.zip; \
    unzip -q /tmp/android-ndk.zip -d /opt; \
    rm /tmp/android-ndk.zip; \
    mv "/opt/android-ndk-${ANDROID_NDK_VERSION}" "${ANDROID_NDK_ROOT}"; \
    echo "ANDROID_NDK_ROOT=${ANDROID_NDK_ROOT}" >> /etc/environment

RUN set -eux; \
    geode sdk install-binaries -p android32; \
    geode sdk install-binaries -p android64


# ===============================
# macOS image (osxcross + macOS binaries)
# ===============================
FROM geode-sdk-base AS geode-sdk-macos

COPY --from=osxcross /osxcross /osxcross

ENV PATH="/osxcross/bin:${PATH}"
ENV LD_LIBRARY_PATH="/osxcross/lib:${LD_LIBRARY_PATH}"

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends clang; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    echo 'set(CMAKE_OSX_SYSROOT ${OSXCROSS_SDK})' >> /osxcross/toolchain.cmake

RUN set -eux; \
    CLI_PROFILE="/root/.config/geode"; \
    geode profile add --name DockerProfileMac "${CLI_PROFILE}/GeometryDash" mac

RUN set -eux; \
    geode sdk install-binaries -p mac
