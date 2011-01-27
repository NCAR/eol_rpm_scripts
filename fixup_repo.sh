#!/bin/sh

# script to run createrepo on all directories in the repository
# that have a repodata directory, then makes sure all the user's
# files have group eol write permission.

repo=/net/www/docs/software/rpms 

# createrepo version 0.4.9 (EL5) complains about --checksum sha,
# "This option is deprecated", but the option is necessary with
# version 0.9.8 (Fedora 12, etc) to create repodata that is compatible
# with 0.4.9.
ver4=false
createrepo --version | grep -E "^0\.4\.[0-9]+$" > /dev/null && ver4=true

for d in `find $repo -name repodata -type d -print`; do
    cd ${d%/repodata} || exit 1
    echo $PWD
    if $ver4; then
        createrepo --update --checkts .
    else
        createrepo --checksum sha --update --checkts .
    fi
    cd - > /dev/null
done

find $repo -user $USER \! -group eol -exec chgrp eol {} \;
find $repo -user $USER \! -perm -020 -exec chmod g+w {} \;

