#!/bin/bash
set -euo pipefail

# Ensure script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

# Configuration
WORKDIR="/usr/src"
TEMPMOUNT="/usr/src/linux"
CONFIG="/boot/config-$(uname -r)"
CPUCORES=$(nproc)
KERNEL_JSON_URL="https://www.kernel.org/releases.json"
GPG_KEYRING="/usr/share/keyrings/linux-kernel.gpg"

# Cleanup function
cleanup() {
    echo "Performing cleanup..."
    if mountpoint -q "$TEMPMOUNT"; then
        umount "$TEMPMOUNT" || true
    fi
    rm -rf "$TEMPMOUNT" || true
    # Don't remove downloaded files - they might be useful for debugging
}

trap cleanup EXIT ERR

# Verify we have required tools
for cmd in curl jq wget gpg tar make find; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: Required command '$cmd' not found" >&2
        exit 1
    fi
done

# Get kernel information
echo "Fetching kernel release information..."
kernel_info=$(curl -fsSL "$KERNEL_JSON_URL") || {
    echo "Error: Failed to fetch kernel releases" >&2
    exit 1
}

kernelfile=$(echo "$kernel_info" | jq -r 'first(.releases | to_entries[] | select(.value.moniker == "stable") | .value.source)')
signature_file=$(echo "$kernel_info" | jq -r 'first(.releases | to_entries[] | select(.value.moniker == "stable") | .value.pgp)')
newkernel=$(echo "$kernelfile" | grep -oP '\d+\.\d+\.\d+')
currentkernel=$(grep -oP 'Linux version \K\d+\.\d+\.\d+' /proc/version)

if [ "$newkernel" != "$currentkernel" ]; then
    echo "New kernel found: $newkernel (current: $currentkernel)"
else
    echo "No new kernel found (current: $currentkernel)"
    exit 0
fi

# Prepare working directory
mkdir -p "$TEMPMOUNT"
mount -t tmpfs -o size=12G,mode=0700 tmpfs "$TEMPMOUNT" || {
    echo "Error: Failed to mount tmpfs" >&2
    exit 1
}

# Download kernel source
archive_name=$(basename "$kernelfile")

if [ ! -f "$WORKDIR/$archive_name" ]; then
    echo "Downloading kernel source..."
    wget --no-verbose --show-progress -O "$WORKDIR/$archive_name" "$kernelfile" || {
        echo "Error: Failed to download kernel source" >&2
        exit 1
    }

    echo "Downloading signature..."
    wget --no-verbose --show-progress -O "$WORKDIR/$signature_file" "${signature_file}" || {
        echo "Error: Failed to download signature" >&2
        exit 1
    }

    echo "Verifying signature..."
    if ! gpgv --keyring "$GPG_KEYRING" "$WORKDIR/$signature_file" "$WORKDIR/$archive_name"; then
        echo "Error: Signature verification failed!" >&2
        exit 1
    fi
else
    echo "Kernel source already exists, skipping download"
fi

# Extract source
echo "Extracting kernel source..."
tar -xf "$WORKDIR/$archive_name" -C "$TEMPMOUNT" || {
    echo "Error: Failed to extract kernel source" >&2
    exit 1
}

src_dir=$(find "$TEMPMOUNT" -maxdepth 1 -type d -name 'linux-*' -print -quit)
if [ -z "$src_dir" ]; then
    echo "Error: Could not find extracted linux source directory" >&2
    exit 1
fi

# Prepare build directory
build_dir="$TEMPMOUNT/build"
mkdir -p "$build_dir"
shopt -s dotglob
mv "$src_dir"/* "$build_dir/" || {
    echo "Error: Failed to move source files to build directory" >&2
    exit 1
}
shopt -u dotglob

# Confirm before building
read -p "Start to compile new kernel? (y/N) " -n 1 -r
echo
if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
    echo "Build cancelled"
    exit 0
fi

# Build kernel
cd "$build_dir" || exit 1

echo "Preparing build environment..."
make mrproper || {
    echo "Error: make mrproper failed" >&2
    exit 1
}

if [ -f "$CONFIG" ]; then
    cp "$CONFIG" .config || {
        echo "Error: Failed to copy config file" >&2
        exit 1
    }
else
    echo "Warning: No existing config file found at $CONFIG" >&2
fi

echo "Running menuconfig..."
make menuconfig || {
    echo "Error: menuconfig failed" >&2
    exit 1
}

# Store configuration in git for tracking
if command -v git >/dev/null 2>&1; then
    git init --quiet
    git checkout -b master --quiet
    git add . >/dev/null
    git commit -m "Initial config for kernel $newkernel" --quiet || {
        echo "Warning: Failed to create git commit" >&2
    }
fi

echo "Starting build process..."
startdate=$(date)
if ! make -j "$CPUCORES" deb-pkg; then
    echo "Error: Kernel build failed!" >&2
    exit 1
fi
finishdate=$(date)

# Move packages to WORKDIR
mv "$TEMPMOUNT"/*.deb "$WORKDIR/" || {
    echo "Error: Failed to move .deb packages" >&2
    exit 1
}

cd "$WORKDIR"

echo "Build completed successfully!"
echo "Start time: $startdate"
echo "Finish time: $finishdate"
echo "Debian packages created in $WORKDIR"
