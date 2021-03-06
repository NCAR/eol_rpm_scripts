#!/bin/sh

# use this script to create a repository, like fedora/15, or epel/6
# in /net/www/docs/software/rpms

if [ $# -lt 1 ]; then
    echo "Usage: $0 subdir"
    echo "Examples:
$0 fedora/15
$0 epel/6
$0 fedora-signed/15
$0 epel-signed/6"
    exit 1
fi

repo=$1

dir=$(readlink  -f $0) 
dir=$(dirname $dir)

repotop=/net/www/docs/software/rpms

for s in SRPMS x86_64; do
    [ -d $repotop/$repo/$s ] || mkdir -p $repotop/$repo/$s
    echo "running: createrepo $repotop/$repo/$s"
    createrepo $repotop/$repo/$s || exit 1
done

# create symbolic links for epel
if [[ $repo =~ ^epel.*/[0-9]+$ ]]; then
    eversion=${1##*/}
    ln -s $eversion $repotop/${1}Client
    ln -s $eversion $repotop/${1}Server
    ln -s $eversion $repotop/${1}Workstation
fi

$dir/fixup_repo.sh


