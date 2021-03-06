#!/bin/bash

# check permissions on our local yum repositories and
# email people whose files don't have group write permission

touser=
[ $# -gt 0 ] && touser=$1

repo=/net/www/docs/software/rpms

tmpfile=$(mktemp)
tmpfile2=$(mktemp)
trap "{ rm -f $tmpfile $tmpfile2; }" EXIT

find $repo -name .svn -prune -o \! -perm -020 -ls > $tmpfile

offenders=(`awk '/^[0-9]+/{print $5}' $tmpfile | sort -u`)

for o in ${offenders[*]}; do

    cat << EOD > $tmpfile2
A friendly reminder from $0 ...

The following files on $repo are owned by $o and don't have
group write permission, preventing others from updating the repository.

The rmpbuild and createrepo commands ignore your umask and create files without 
group write access.

Under subversion, at http://svn.eol.ucar.edu/svn/eol/repo/scripts, is a script
called fixup_repo.sh which enable group write permission on all files that are
owned by you.

A working copy of http://svn.eol.ucar.edu/svn/eol/repo/scripts is at
/net/www/docs/software/rpms/scripts. You can run the fixup script directly,
from the $o login:
    /net/www/docs/software/rpms/scripts/fixup_repo.sh

The scripts repository also includes a bash function called
move_rpms_to_eol_repo, in repo_funcs.sh, which can also be used to copy RPMs
to the repository, with the right permissions.

Corruption of the repository can occur if multiple instances of createrepo are
run at the same time. If you need to run createrepo, please run it on
jenkins.eol.ucar.edu via the update_eol_repo function:
    source /net/www/docs/software/rpms/scripts/repo_funcs.sh
    update_eol_repo

EOD

    awk '$5 == "'$o'"{print $0}' $tmpfile >> $tmpfile2
    to=$o
    case $o in
        ads)
            to=cjw
            ;;
    esac

    env MAILRC=/dev/null smtp=smtp.eol.ucar.edu from=$USER@ucar.edu mailx -s "File(s) on $repo without group write" $to  < $tmpfile2

    [ $touser ] && \
        env MAILRC=/dev/null smtp=smtp.eol.ucar.edu from=$USER@ucar.edu mailx -s "File(s) on $repo without group write" $touser  < $tmpfile2
done

