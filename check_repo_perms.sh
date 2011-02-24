#!/bin/sh

# check permissions on our local yum repositories and
# email people whose files don't have group write permission

repo=/net/www/docs/software/rpms

tmpfile=`mktemp`
trap "{ rm -f $tmpfile; }" EXIT
tmpfile2=`mktemp`
trap "{ rm -f $tmpfile2; }" EXIT

find $repo -name .svn -prune -o \! -perm -020 -ls > $tmpfile

offenders=(`awk '/^[0-9]+/{print $5}' $tmpfile | sort -u`)

for o in ${offenders[*]}; do

    cat << EOD > $tmpfile2
A friendly reminder from $0 ...

The following files on $repo are owned by you and don't have
group write permission, preventing others from updating the repository.

The rmpbuild and createrepo commands ignore your umask and create files without 
group write access.

Suggestion: use these commands to allow write permission to members of group eol:

find $repo -user $o \! -group eol -exec chgrp eol {} \;
find $repo -user $o \! -perm -020 -exec chmod g+w {} \;

Or, under subversion, at http://svn.eol.ucar.edu/svn/eol/repo/scripts, is a script
called fixup_repo.sh which will run createrepo on all repositories in $repo
and then enable group write permission on all files owned by you.

The scripts also include a bash function called copy_rpms_to_eol_repo,
in repo_funcs.sh, which can also be used to copy RPMs to the repository,
run createrepo and fix the permissions.

EOD

    awk '$5 == "'$o'"{print $0}' $tmpfile >> $tmpfile2

    env MAILRC=/dev/null smtp=smtp.eol.ucar.edu from=$USER@ucar.edu mailx -s "File(s) on $repo without group write" $o  < $tmpfile2
    env MAILRC=/dev/null smtp=smtp.eol.ucar.edu from=$USER@ucar.edu mailx -s "File(s) on $repo without group write" $USER  < $tmpfile2
done

