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
    # Given a passed parameter of the repository type, either "" or "-signed",
    # return a repository directory path matching my distribution,
    # looking like the following:
    #   fedora$repotype/$releasever
    #   epel$repotype/$releasever
    # where $releasever is determined using the same method yum uses
    #
    # repotype should be either an empty string, or "-signed"

    # Note it doesn't have an architecture directory, like i386.

    local repotype=$1
    # This is what yum does to determine $releasever
    local releaserpm=$(rpm -q --whatprovides redhat-release)
    local releasever=$(rpm -q --queryformat "%{VERSION}\n" $releaserpm)

    local rrel=/etc/redhat-release
    local repo
    if [ -f $rrel ]; then
        if fgrep -q Fedora $rrel; then
            repo=fedora$repotype/$releasever
        else
            repo=epel$repotype/$releasever
        fi
    fi
    echo $repo
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

move_rpms_to_eol_repo()
{
    if [ $((`umask`)) -ne  $((0002)) ]; then
        echo "setting umask to 0002 to allow group write permission"
        umask 0002
    fi

    # move list of rpms to the correct eol repository
    local rroot=`get_eol_repo_root`
    while [ $# -gt 0 ]; do
        local rpmfile=$1
        shift
        [ -f $rpmfile ] || continue
        local rpm=${rpmfile%.*}     # lop off .rpm
        local arch=${rpm##*.}       # get arch:  i386, x86_64, src, noarch, etc

        # repo type "" or "-signed"
        local repotype=""
        # SIGGPG is listed as an rpm --querytag in addition to SIGPGP,
        # but returns (none) for rpms signed with gpg (rpm bug?). SIGPGP works
        rpm -qp --qf "%{SIGPGP}" $rpmfile | fgrep -qv "(none)" && repotype="-signed"
        echo "repotype=$repotype"

        local basearch=$arch
        local repo=$(get_host_repo_path $repotype)

        local -a repos=()

        case $arch in
        src)
            repos=($rroot/$repo/SRPMS)
            ;;
        noarch)
            # find all non-source repositories, include the path for this machine
            # Exclude ael, old, repodata and any SRPMS directories
            if [ "$repotype" == "-signed" ]; then
                repos=(`find $rroot -maxdepth 3 -mindepth 3 \( -wholename "*/ael/*" -o -name "*repodata" -o -name SRPMS -o -wholename "*/old/*" -o -wholename "*/.svn/*" \) -prune -o -type d -wholename "*-signed/*" -print` $rroot/$(get_host_repo_path $repotype)/$(uname -i))
            else
                repos=(`find $rroot -maxdepth 3 -mindepth 3 \( -wholename "*/ael/*" -o -name "*repodata" -o -name SRPMS -o -wholename "*/old/*" -o -wholename "*/.svn/*" -o -wholename "*-signed/*" \) -prune -o -type d -print` $rroot/$(get_host_repo_path $repotype)/$(uname -i))
            fi
            repos=(`unique_strings ${repos[*]}`)
            ;;
        i?86)
            basearch=i386
            repos=($rroot/$repo/$basearch)
            ;;
        x86_64)
            repos=($rroot/$repo/$basearch)
            ;;
        *)
            echo "rpm architecture $arch not supported in ${FUNCNAME[0]}"
            exit 1
            ;;
        esac

        for d in ${repos[*]}; do
            [ -d $d ] || mkdir -p $d

            echo rsync $rpmfile $d
            rsync $rpmfile $d
            chmod g+w $d/${rpmfile##*/}
        done
        rm -f $rpmfile
    done
}

move_ael_rpms_to_eol_repo()
{
    if [ $((`umask`)) -ne  $((0002)) ]; then
        echo "setting umask to 0002 to allow group write permission"
        umask 0002
    fi

    # move of list of rpms to the correct eol repository
    local rroot=`get_eol_repo_root`
    while [ $# -gt 0 ]; do
        local rpmfile=$1
        shift
        [ -f $rpmfile ] || continue
        local rpm=${rpmfile%.*}     # lop off .rpm
        local arch=${rpm##*.}       # get arch:  i386, x86_64, src, noarch, etc

        local -a repos
        case $arch in
        src)
            repos=($rroot/ael/SRPMS)
            ;;
        noarch)
            repos=($rroot/ael/i386)
            ;;
        i?86)
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
            chmod g+w $d/${rpmfile##*/}
        done
        rm -f $rpmfile
    done
}

update_eol_repo_unlocked()
{
    if [ $((`umask`)) -ne  $((0002)) ]; then
        echo "setting umask to 0002 to allow group write permission"
        umask 0002
    fi

    if [ $# -lt 1 ]; then
        echo "Usage ${0} repo-root-directory"
        exit 1
    fi

    rroot=$1

    if ! which createrepo > /dev/null; then
        echo "createrepo command not found. Run createrepo on a system with the createrepo package"
    fi

    # Look for these files in the repository
    local radmfile=repomd.xml
    local -a repoxmls=$(find $rroot -name $radmfile)

    for rxml in ${repoxmls[*]}; do
        local rdir=${rxml%/$radmfile}
        rdir=${rdir%/repodata}

        cd $rdir > /dev/null || exit 1

        # rpms that are newer than $radmfile
        local -a rpms=($(find . -name "*.rpm" -newer repodata/$radmfile))
        # echo "rpms=${rpms[*]}, #=${#rpms[*]}"

        # clean up old revisions, keeping two
        for rpm in ${rpms[*]}; do
            local nf=$(echo $rpm | sed 's/[^-]//g' | wc -c)
            echo "rpmf=$rpm, nf=$nf"

            # list all but last two rpms with the same version
            # but different release, treating release as a numeric
            # field, not alpha
            local -a oldrpms=( $(shopt -u nullglob; ls ${rpm%-*}*.rpm 2>/dev/null | sort -t- -k1,$((nf-1)) -k${nf}n | head -n-2) )
            if [ ${#oldrpms[*]} -gt 0 ]; then
                echo "cleaning up: ${oldrpms[*]}"
                rm -f ${oldrpms[*]}
            fi
        done

        cd - > /dev/null

        # If there are any new rpms, run createrepo
        if [ ${#rpms[*]} -gt 0 ]; then

            if echo $rdir | fgrep -q epel/5; then
                echo createrepo --checksum sha --update $rdir
                flock $rdir -c "createrepo --checksum sha --update $rdir" > /dev/null || { echo "createrepo error"; exit 1; }
            else
                echo createrepo --update $rdir
                flock $rdir -c "createrepo --update $rdir > /dev/null" || { echo "createrepo error"; exit 1; }
            fi

            # createrepo creates files without group
            # write permission, even if umask is 0002.
            flock $rdir -c "find $rdir -user $USER \! -perm -020 \
                -exec chmod g+w {} \;"
            flock $rdir -c "find $rdir -user $USER \! -group eol \
                -exec chgrp eol {} \;"
        fi
    done
}

update_eol_repo()
{
    local rroot
    if [ $# -ge 1 ]; then
        rroot=$1
    else
        rroot=`get_eol_repo_root`
    fi

    flock $rroot bash -c "
        n=$((${#BASH_SOURCE[*]}-1));
        source ${BASH_SOURCE[$n]};
        update_eol_repo_unlocked $rroot"
}

