#!/bin/sh

# script to rename Debian packages which were created with
# the Arcom Embedded Linux dpkg command
#
# The dpkg command creates packages with names like libxerces-c.deb
# This script scans the package, then adds the version and architecture
# to the name, with a result like: libxerces-c_2.8.0-1_arm.deb
#
# One argument: the name of the debian package to be renamed
#   
dpkg=$1
d=`dirname $dpkg`
p=`dpkg -I $dpkg | fgrep Package: | awk '{print $2}'`
v=`dpkg -I $dpkg | fgrep Version: | awk '{print $2}'`
a=`dpkg -I $dpkg | fgrep Architecture: | awk '{print $2}'`

if [ -n "$a" -a "$a" != "all" ]; then
    new=$d/${p}_${v}_${a}.deb
else
    new=$d/${p}_${v}.deb
fi

mv $dpkg $new
echo "package: $new"
