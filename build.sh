#!/bin/sh

# unpack and prepare
cd /usr/src

# check for new file
kernelfile=`wget -O - 2>&1 https://www.kernel.org | grep "latest_link" -A 2 | grep -o 'https://[^"]*'`
newkernel=`expr match "$kernelfile" '.*\([0-9]\+\.[0-9]\+\.[0-9]\+\)'`
currentkernel="`cat /proc/version | grep -o 'Linux version [^ ]*'`"
currentkernel=`expr match "$currentkernel" '.*\([0-9]\+\.[0-9]\+\.[0-9]\+\)'`

# check new kernel version
if [ "$newkernel" != "$currentkernel" ];
then
    echo "New kernel found!"
    /usr/bin/wget -c $kernelfile
    archname=`find *.xz`
    tar xxf $archname
    dirsrc=`find -P linux-* -maxdepth 0 -type d | head -n 1`
    rm linux
    ln -s $dirsrc linux

    # compile
    cd /usr/src/linux
    make clean && make mrproper
    cp /boot/config-`uname -r` ./.config
    sed -i "s/CONFIG_MODULE_SIG_ALL/#CONFIG_MODULE_SIG_ALL/g" ./.config
    sed -i "s/CONFIG_MODULE_SIG_KEY/#CONFIG_MODULE_SIG_KEY/g" ./.config
    sed -i "s/CONFIG_SYSTEM_TRUSTED_KEYS/#CONFIG_SYSTEM_TRUSTED_KEYS/g" ./.config
    sed -i "s/CONFIG_DEBUG_INFO/#CONFIG_DEBUG_INFO/g" ./.config
    make menuconfig
    startdate=`date`
    make clean
    make deb-pkg
    finishdate=`date`

    cd /usr/src
    rm -rf $dirsrc
    rm $archname

    echo "Start time: $startdate"
    echo "Finish time: $finishdate"
else
    echo "No new kernel found"
fi
