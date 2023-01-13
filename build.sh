#!/bin/bash

# unpack and prepare
cd /usr/src || exit

# check for new file
kernelfile=$(wget -O - 2>&1 https://www.kernel.org | grep "latest_link" -A 2 | grep -o 'https://[^"]*')
newkernel=$(expr match "$kernelfile" '.*\([0-9]\+\.[0-9]\+\.[0-9]\+\)')
currentkernel=$(grep -o 'Linux version [^ ]*' /proc/version)
currentkernel=$(expr match "$currentkernel" '.*\([0-9]\+\.[0-9]\+\.[0-9]\+\)')
# will use all available cores
cpucores=$(nproc)

# you can specify here your kernel config file
config=$(/boot/config-`uname -r`)

# check new kernel version
if [ "$newkernel" != "$currentkernel" ];
then
    echo "New kernel found!"
    mkdir /usr/src/linux
    mount -t tmpfs -o size=8G,mode=0700 tmpfs /usr/src/linux
    /usr/bin/wget -c "$kernelfile"
    archname=$(find *.xz)
    tar xxf "$archname"
    dirsrc=$(find -P linux-* -maxdepth 0 -type d | head -n 1)
    shopt -s dotglob
    mv $dirsrc/* /usr/src/linux

    # compile
    cd /usr/src/linux || exit
    make mrproper
    cp $config ./.config
    sed -i "s/CONFIG_MODULE_SIG_ALL/#CONFIG_MODULE_SIG_ALL/g" ./.config
    sed -i "s/CONFIG_MODULE_SIG_KEY/#CONFIG_MODULE_SIG_KEY/g" ./.config
    sed -i "s/CONFIG_SYSTEM_TRUSTED_KEYS/#CONFIG_SYSTEM_TRUSTED_KEYS/g" ./.config
    sed -i "s/CONFIG_DEBUG_INFO/#CONFIG_DEBUG_INFO/g" ./.config
    make menuconfig
    make-kpkg clean
    startdate=$(date)
    make -j "$cpucores" deb-pkg
    finishdate=$(date)

    cd /usr/src
    rm -rf "$dirsrc"
    rm "$archname"
    umount /usr/src/linux
    rm -rf /usr/src/linux

    echo "Start time: $startdate"
    echo "Finish time: $finishdate"
else
    echo "No new kernel found"
fi
