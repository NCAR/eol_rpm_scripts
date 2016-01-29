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

repotop=/net/www/docs/software/rpms

for s in SRPMS x86_64; do
    echo "creating $repotop/$repo/$s/repodata"
    mkdir -p $repotop/$repo/$s/repodata || exit 1
done

# create symbolic links for epel
if [[ $repo =~ ^epel/[0-9]+$ ]]; then
    eversion=${1##*/}
    ln -s $eversion $repotop/${1}Client
    ln -s $eversion $repotop/${1}Server
    ln -s $eversion $repotop/${1}Workstation
fi

# Run createrepo
dir=`dirname $0`
for s in SRPMS x86_64; do
    $dir/fixup_repo.sh $repo/$s
done


