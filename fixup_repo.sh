#!/bin/sh

# script to run createrepo on all directories in the repository
# that have a repodata directory, then makes sure all the user's
# files have group eol write permission.

repotop=/net/www/docs/software/rpms 
echo=

# createrepo version 0.4.9 (EL5) complains about --checksum sha,
# "This option is deprecated", but the option is necessary with
# newer versions of createrepo to create repositories compatible with
# yum 3.2.*

crver4=false
createrepo --version | grep -q -E "^0\.4\.[0-9]+$" > /dev/null && crver4=true

repos=
if [ $# -gt 0 ]; then
    repos=($1)
else
    repos=($(find $repotop -name .svn -prune -o -name repodata -type d -print))
fi

for d in ${repos[*]}; do
    cd ${d%/repodata} || exit 1
    echo $PWD

    if $crver4; then
        echo "createrepo ."
        flock . -c "createrepo ." || exit 1
    else
        if echo $d | fgrep -q epel/5; then
            echo "createrepo --checksum sha ."
            flock . -c "createrepo --checksum sha ." || exit 1
        elif echo $d | fgrep -q ael; then
            echo "createrepo --checksum sha ."
            flock . -c "createrepo --checksum sha ." || exit 1
        else
            echo "createrepo ."
            flock . -c "createrepo ." || exit 1
        fi
    fi

    cd - > /dev/null
done

find $repotop -user $USER \! -group eol -print0 | xargs -0r $echo chgrp eol
find $repotop -user $USER \! -perm -020 -print0 | xargs -0r $echo chmod g+w 

# bug in some versions of createrepo, leaves garbageid directories around
# https://bugzilla.redhat.com/show_bug.cgi?id=728584
find $repotop -type d -name garbageid -print0 | xargs -0r $echo rm -rf
