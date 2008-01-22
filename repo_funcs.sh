#!/bin/sh

get_rpm_topdir()
{

    # find user's RPM %_topdir.  The user should override
    # the default of /usr/src/redhat in ~/.rpmmacros, in order to be
    # able to build packages as non-root
    # If no definition of %_topdir is found in .rpmmacros, this
    # function will define it with a value of ~/rpmbuild, and
    # create the BUILD,RPMS,SOURCE,SPECS/SRPMS directories on it.

    local needs_topdir=true

    # Where to find user's rpm macro definitions
    local rmacs=~/.rpmmacros

    [ -f $rmacs ] && grep -q "^[[:space:]]*%_topdir[[:space:]]" $rmacs && needs_topdir=false

    if $needs_topdir; then
        mkdir -p ~/rpmbuild/{BUILD,RPMS,S{OURCE,PEC,RPM}S} || exit 1
        echo "%_topdir	%(echo \$HOME)/rpmbuild
# turn off building the debuginfo package
%debug_package	%{nil}\
" > $rmacs
    fi

    local topdir=`rpm --eval %_topdir`

    # It is very unlikely that %_topdir is not defined, but...
    if [ `echo $topdir | cut -c 1` == "%" ]; then
        echo "%_topdir not defined in $rmacs or /usr/lib/rpm"
        topdir="unknown_topdir"
    fi
    echo "$topdir"
}
get_eol_repo_root()
{
    # Return path of top of EOL repository, above the
    # fedora or centos directories
    return /net/www/docs/software/rpms
}

get_repo_path()
{
    # return a repository directory path matching my distribution,
    # looking like the following:
    #   fedora/8
    #   centos/5
    # Note it doesn't have an architecture directory, like i386.
    local rrel=/etc/redhat-release
    local dist="unknown"
    if [ -f $rrel ]; then
        n=`sed 's/^.*release *\([0-9]*\).*/\1/' $rrel`
        if fgrep -q Enterprise $rrel; then
            dist=centos/$n
        elif fgrep -q CentOS $rrel; then
            dist=centos/$n
        elif fgrep -q Fedora $rrel; then
            dist=fedora/$n
        fi
    fi
    echo $dist
}

get_repo_paths_from_rpm()
{
    # SPEC files of rpms often specify "Release: N%{dist}".
    # %{dist} on Fedora expands to ".fc8". on centos or EL it is null.
    # Parse the release field to try to figure out whether it is
    # a fedora or centos package.
    #
    # This will return one or more strings looking like the following:
    #   fedora/8/`uname -i`
    #   centos/5/`uname -i`
    #   fedora/8/SRPMS
    #   centos/5/SRPMS
    #
    # It can return more than one path if the rpm is for "noarch".
    # In this case it returns paths to all the architectures found
    # on the repo, like: fedora/8/i386 fedora/8/x86_64

    #
    local rpm=$1
    rpm=${rpm%.*}               # lop off .rpm
    local arch=${rpm##*.}       # get arch:  i386, x86_64, src, noarch, etc
    rpm=${rpm%.*}               # lop off arch
    local rel=${rpm##*-}         # get release
    local dist = `echo "$rel" | sed 's/^[0-9.]*//'`
    local -a rpaths

    case $dist in
    fc*)
        dist="fedora/`echo $dist | cut -c3-`"
        ;;
    *)
        # get repo path matching for machine
        dist=`get_repo_path`
        ;;
    esac

    case $arch in
    src)
        rpaths=("$dist/SRPMS")
        ;;
    noarch)
        local -a apaths=(`get_eol_repo_root`/$dist/*)
        for a in ${apaths[*]}; do
            arch=${a##*/}
            if [ "$arch" != SRPMS ]; then
                rpaths=(${rpaths[*]} $dist/$arch} 
            fi
        done
        ;;
    *)
        rpaths=($dist/"$arch")
        ;;
    esac

    echo "${rpaths[*]}"
}

