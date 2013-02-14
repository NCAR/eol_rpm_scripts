#!/bin/sh

# script to run createrepo on all directories in the repository
# that have a repodata directory, then makes sure all the user's
# files have group eol write permission.

repo=/net/www/docs/software/rpms 
echo=

# createrepo version 0.4.9 (EL5) complains about --checksum sha,
# "This option is deprecated", but the option is necessary with
# version 0.9.8 (Fedora 12, etc) to create repodata that is compatible
# with 0.4.9.
createrepo="createrepo --checksum sha --update"
if createrepo --version | grep -Eq "^0\.4\.[0-9]+$" ; then
    createrepo="createrepo --update"
fi

find $repo -name .svn -prune -o -name repodata -type d -print | \
while read d ; do
    d=`dirname "$d"`
    (set -x; $echo $createrepo "$d")
done

find $repo -user $USER \! -group eol -print0 | xargs -0r $echo chgrp eol
find $repo -user $USER \! -perm -020 -print0 | xargs -0r $echo chmod g+w 

# bug in some versions of createrepo, leaves garbageid directories around
# https://bugzilla.redhat.com/show_bug.cgi?id=728584
find $repo -type d -name garbageid -print0 | xargs -0r $echo rm -rf
