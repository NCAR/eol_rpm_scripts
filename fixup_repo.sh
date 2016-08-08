#!/bin/sh

# makes sure all the user's files in the repository
# have group eol write permission.

repotop=/net/www/docs/software/rpms 
echo=

find $repotop -user $USER \! -group eol -print0 | xargs -0r $echo chgrp eol
find $repotop -user $USER \! -perm -664 -print0 | xargs -0r $echo chmod ug+w,ugo+r

# bug in some versions of createrepo, leaves garbageid directories around
# https://bugzilla.redhat.com/show_bug.cgi?id=728584
find $repotop -type d -name garbageid -print0 | xargs -0r $echo rm -rf

# Not sure what circumstance results in .olddata directories
# laying around. createrepo fails if it finds them.
oldies=($(find $repotop -name .olddata))
if [ ${#oldies[*]} -gt 0 ]; then
    echo "Warning: found ${#oldies[*]} .olddata directories. Deleting..."
    rm -rf ${oldies[*]}
fi

