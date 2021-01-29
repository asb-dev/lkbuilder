Automated build script of Linux kernel for Debian GNU/Linux.
===

Install prerequisites, clone the repository, setup and run the script. It will build a new version of stable kernel available at kernel.org.

Required packages
---

```
apt-get install git wget build-essential kernel-package make libncurses-dev flex bison libelf-dev libssl-dev rsync bc
```

Setup
---

```
mkdir /root/lkbuilder && cd lkbuilder
git clone https://github.com/asb-dev/lkbuilder.git .
ln -s /root/lkbuilder/build.sh /usr/src/build.sh
```

Build kernel
---

```
cd /usr/src
./build.sh
```
