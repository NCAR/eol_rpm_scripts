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
    mkdir -p $topdir/{BUILD,RPMS,S{OURCE,PEC,RPM}S} || exit 1
    echo "$topdir"
}
get_eol_repo_root()
{
    # Return path of top of EOL repository, above the
    # fedora or epel directories
    # If /net/www/docs/software/rpms does not exist,
    # try a local apache directory, which may not exist.
    # The calling script should check that the returned path exists.

    local d=/net/www/docs/software/rpms 
    if [ -d $d ]; then
        echo $d
    else
        d=/var/www/html/software/rpms
        [ ! -d $d ] || mkdir -p $d
        echo $d
    fi
}

get_host_repo_path()
{
    # return a repository directory path matching my distribution,
    # looking like the following:
    #   fedora/8
    #   epel/5
    # Note it doesn't have an architecture directory, like i386.
    local rrel=/etc/redhat-release
    local dist="unknown"
    if [ -f $rrel ]; then
        local n=`sed 's/^.*release *\([0-9]*\).*/\1/' $rrel`
        if fgrep -q Enterprise $rrel; then
            dist=epel/$n
        elif fgrep -q CentOS $rrel; then
            dist=epel/$n
        elif fgrep -q Fedora $rrel; then
            dist=fedora/$n
        fi
    fi
    echo $dist
}

copy_rpms_to_eol_repo()
{
    if [ $((`umask`)) -ne  $((0002)) ]; then
        echo "setting umask to 0002 to allow group write permission"
        umask 0002
    fi
    # copy of list of rpms to the correct eol repository
    local -a allrepos
    local rroot=`get_eol_repo_root`
    while [ $# -gt 0 ]; do
        local rpmfile=$1
        shift
        local rpm=${rpmfile%.*}           # lop off .rpm
        local arch=${rpm##*.}       # get arch:  i386, x86_64, src, noarch, etc
        rpm=${rpm%.*}               # lop off arch
        local rel=${rpm##*-}         # get release
        local dist=`echo "$rel" | sed 's/^[0-9.]*//'`

        local -a repos=()
        case $arch in
        src)
            # find all SRPMS directories in eol repository
            # repos=(`find $rroot -maxdepth 3 -mindepth 3 \( -name ael -prune \) -o -type d -name SRPMS -print`)
            case $dist in
            fc*)
                # if fc* in the rpm name, then copy to specific repository
                repos=($rroot/fedora/`echo $dist | cut -c3-`/SRPMS)
                ;;
            *)
                # get repo path for this machine
                repos=($rroot/`get_host_repo_path`/SRPMS)
                ;;
            esac
            ;;
        noarch)
            # find all non-source repositories, include the path for this machine
            # Exclude ael, old, repodata and any SRPMS directories
            repos=(`find $rroot -maxdepth 3 -mindepth 3 \( -wholename "*/ael/*" -o -name repodata -o -name SRPMS -o -wholename "*/old/*" -prune \) -o -type d -print` $rroot/`get_host_repo_path`/`uname -i`)
            repos=(`unique_strings ${repos[*]}`)
            ;;
        *)
            case $dist in
            fc*)
                # if fc* in the rpm name, then copy to specific repository
                repos=($rroot/fedora/`echo $dist | cut -c3-`/$arch)
                ;;
            *)
                # get repo path for this machine
                repos=($rroot/`get_host_repo_path`/$arch)
                ;;
            esac
            ;;
        esac
        for d in ${repos[*]}; do
            [ -d $d ] || mkdir -p $d
            echo rsync $rpmfile $d
            rsync $rpmfile $d
            chmod g+w $d/$rpmfile
        done
        rm -f $rpmfile
        allrepos=(`unique_strings ${allrepos[*]} ${repos[*]}`)
    done

    if ! which createrepo; then
        echo "createrepo command not found. Run createrepo on a system with the createrepo package"
    fi
    for r in ${allrepos[*]}; do
        echo createrepo $r
        # --update is not supported on all versions of createrepo
        createrepo $r > /dev/null || { echo "createrepo error"; exit 1; }
        # For some reason createrepo is creating files without group write permission
        # even if umask is 0002.
        find $r -user $USER \! -perm -020 -exec chmod g+w {} \;
    done
}
copy_ael_rpms_to_eol_repo()
{
    if [ $((`umask`)) -ne  $((0002)) ]; then
        echo "setting umask to 0002 to allow group write permission"
        umask 0002
    fi
    # copy of list of rpms to the correct eol repository
    local -a allrepos
    local rroot=`get_eol_repo_root`
    while [ $# -gt 0 ]; do
        local rpmfile=$1
        shift
        local rpm=${rpmfile%.*}           # lop off .rpm
        local arch=${rpm##*.}       # get arch:  i386, x86_64, src, noarch, etc

        local -a repos
        case $arch in
        src)
            repos=($rroot/ael/SRPMS)
            ;;
        noarch)
            repos=($rroot/ael/i386)
            ;;
        i386)
            repos=($rroot/ael/i386)
            ;;
        *)
            echo "only i386 rpms allowed in ael repository, skipping $rpmfile"
            ;;
        esac
        for d in ${repos[*]}; do
            [ -d $d ] || mkdir -p $d
            echo rsync $rpmfile $d
            rsync $rpmfile $d
            chmod g+w $d/$rpmfile
        done
        rm -f $rpmfile
        allrepos=(`unique_strings ${allrepos[*]} ${repos[*]}`)
    done
    if ! which createrepo; then
        echo "createrepo command not found. Run createrepo on a system with the createrepo package"
    fi
    for r in ${allrepos[*]}; do
        echo createrepo $r
        # --update is not supported on all versions of createrepo
        createrepo $r > /dev/null || { echo "createrepo error"; exit 1; }
        # For some reason createrepo is creating files without group write permission
        # even if umask is 0002.
        find $r -user $USER \! -perm -020 -exec chmod g+w {} \;
    done
}

unique_strings()
{
    # remove duplicate strings from a list by piping to sort -u,
    local OLDIFS=$IFS
    IFS=$'\n'
    res=(`echo "$*" | sort -u`)
    IFS=$OLDIFS
    echo ${res[*]}
}

get_version_from_spec () {
    if [ $# -eq 1 ]; then
        awk '/^Version:/{print $2}' $1
    else
        echo "get_version_from_spec:no_spec_file_arg"
    fi
}

