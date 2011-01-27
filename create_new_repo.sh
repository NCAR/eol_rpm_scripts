#!/bin/sh

# use this script to create a repository, like fedora/15, or epel/6
# in /net/www/docs/software/rpms

if [ $# -lt 1 ]; then
    echo "Usage: $0 subdir"
    echo "Examples:
$0 fedora/15
$0 epel/6"
    exit 1
fi

repo=/net/www/docs/software/rpms

for s in SRPMS i386 x86_64; do
    echo "creating $repo/$1/$s/repodata"
    mkdir -p $repo/$1/$s/repodata || exit 1
done

# create symbolic links for epel
if [[ $1 =~ ^epel/[0-9]+$ ]]; then
    eversion=${1##*/}
    ln -s $eversion $repo/${1}Client
    ln -s $eversion $repo/${1}Server
    ln -s $eversion $repo/${1}Workstation
fi

# Run createrepo
dir=`dirname $0`
$dir/fixup_repo.sh

