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
    #   fedora/$releasever
    #   epel/$releasever
    # where $releasever is determined using the same method yum uses

    # Note it doesn't have an architecture directory, like i386.

    # This is what yum does to determine $releasever
    local releaserpm=$(rpm -q --whatprovides redhat-release)
    local releasever=$(rpm -q --queryformat "%{VERSION}\n" $releaserpm)

    local rrel=/etc/redhat-release
    local repo
    if [ -f $rrel ]; then
        if fgrep -q Fedora $rrel; then
            repo=fedora/$releasever
        else
            repo=epel/$releasever
        fi
    fi
    echo $repo
}

copy_rpms_to_eol_repo()
{
    if [ $((`umask`)) -ne  $((0002)) ]; then
        echo "setting umask to 0002 to allow group write permission"
        umask 0002
    fi

    if ! which createrepo > /dev/null; then
        echo "createrepo command not found. Run createrepo on a system with the createrepo package"
    fi

    local crver4=false
    createrepo --version | grep -E "^0\.4\.[0-9]+$" > /dev/null && crver4=true

    # copy of list of rpms to the correct eol repository
    local -a allrepos
    local rroot=`get_eol_repo_root`
    while [ $# -gt 0 ]; do
        local rpmfile=$1
        shift
        local rpm=${rpmfile%.*}           # lop off .rpm
        local arch=${rpm##*.}       # get arch:  i386, x86_64, src, noarch, etc

        local basearch=$arch
        local repo=$(get_host_repo_path)

        local -a repos=()

        case $arch in
        src)
            repos=($rroot/$repo/SRPMS)
            ;;
        noarch)
            # find all non-source repositories, include the path for this machine
            # Exclude ael, old, repodata and any SRPMS directories
            repos=(`find $rroot -maxdepth 3 -mindepth 3 \( -wholename "*/ael/*" -o -name "*repodata" -o -name SRPMS -o -wholename "*/old/*" -o -wholename "*/.svn/*" -prune \) -o -type d -print` $rroot/`get_host_repo_path`/`uname -i`)
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
            echo "rpm architecture $arch not supported in $0"
            exit 1
            ;;
        esac

        # clean up all but last two releases
        # the following assumes that the field after the last
        # dash '-' is the release, e.g.: nidas-libs-1.1-7002.el6.x86_64.rpm
        # count number of fields separated by dashes in rpmfile 
        # this would break if a dash is in the arch (x86_64) or dist (el6) fields.
        local rpmf=$(basename $rpmfile)
        local nf=$(echo $rpmf | sed 's/[^-]//g' | wc -c)
        echo "rpmf=$rpmf, nf=$nf"

        for d in ${repos[*]}; do
            [ -d $d ] || mkdir -p $d

            # list all but last two rpms with the same version but different release,
            # treating release as a numeric field, not alpha
            cd $d
            local -a oldrpms=( $(shopt -s nullglob; echo ${rpmf%-*}* | sort -t- -k1,$((nf-1)) -k${nf}n | head -n-2) )
            if [ ${#oldrpms[*]} -gt 0 ]; then
                echo "cleaning up: ${oldrpms[*]}"
                rm -f ${oldrpms[*]}
            fi
            cd - > /dev/null

            echo rsync $rpmfile $d
            rsync $rpmfile $d
            chmod g+w $d/${rpmfile##*/}
        done
        rm -f $rpmfile
        allrepos=(`unique_strings ${allrepos[*]} ${repos[*]}`)
    done

    for r in ${allrepos[*]}; do
        # --update is not supported on all versions of createrepo, but
        # seems to be valid on 0.4.9, which is in RHEL5.

        # Create sha1 checksums, which are compatible with rhel5.
        # yum on CentOS 5.10 is version 3.2.22. If the repo does not
        # have sha1 checksum that version of yum will report
        # "Error performing checksum" on the primary.sqlite.bz2 file
        # and not be able to access the repo.
        # 
        # rhel5 systems have version 0.4.9 of createrepo which apparently can only
        # create sha1 checksums. When passed "--checksum sha" the old createrepo reports
        # "This option is deprecated" (sic), but seems to succeed.
        # Fedora systems (10,11,??) have 0.9.7 of createrepo.

        # If yum on an rhel5 system cannot find createrepo package:
        # sudo rpm -ihv http://mirror.centos.org/centos/5.4/os/x86_64/CentOS/createrepo-0.4.11-3.el5.noarch.rpm

        # Apr 27, 2012:
        # removed --checkts option to createrepo.  The find -exec chmod command changes
        # the ctime of the files it changes, which *might* screw up the checkts option.
        # --checkts doesn't mention which timestamps it uses. 
        # We've been getting "Package does not match intended download." errors, even
        # after "yum clean all", and "createrepo -q --update --checkts".  

        if $crver4; then
            echo createrepo --update $r
            createrepo --update $r > /dev/null || { echo "createrepo error"; exit 1; }
        else
            if echo $r | fgrep -q epel/5; then
                echo createrepo --checksum sha --update $r
                createrepo --checksum sha --update $r > /dev/null || { echo "createrepo error"; exit 1; }
            else
                echo createrepo --update $r
                createrepo --update $r > /dev/null || { echo "createrepo error"; exit 1; }
            fi
        fi

        # For some reason createrepo is creating files without group write permission
        # even if umask is 0002.
        find $r -user $USER \! -perm -020 -exec chmod g+w {} \;
    done
}

rsync_rpms_to_eol_repo()
{
    local host=$1
    shift
    local tardir=$(mktemp -d /tmp/XXXXXX)
    cp repo_scripts/repo_funcs.sh $tardir
    while [ $# -gt 0 ]; do
	cp $1 $tardir
	shift
    done
    local tarball=$(mktemp /tmp/XXXXXX.tar.gz)
    tar czf $tarball -C $tardir .
    scp $tarball $host:/tmp
    ssh $host 'td=$(mktemp -d /tmp/XXXXXX); cd $td; tar xzf '$tarball'; source repo_funcs.sh; copy_rpms_to_eol_repo *.rpm; cd /tmp; rm -rf $td;'rm $tarball
    rm -rf $tardir $tarball
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
        allrepos=(`unique_strings ${allrepos[*]} ${repos[*]}`)
    done
    if ! which createrepo > /dev/null; then
        echo "createrepo command not found. Run createrepo on a system with the createrepo package"
    fi
    for r in ${allrepos[*]}; do
        echo createrepo --checksum sha --update $r
        # --update is not supported on all versions of createrepo, but
        # seems to be valid on 0.4.9, which is in RHEL5.

        # Create sha1 checksums, which are compatible with rhel5 and fedora yum.
        # rhel5 systems have version 0.4.9 of createrepo which apparently can only
        # create sha1 checksums. When passed "--checksum sha" the old createrepo reports
        # "This option is deprecated" (sic), but seems to succeed.
        createrepo --checksum sha --update $r > /dev/null || { echo "createrepo error"; exit 1; }

        # For some reason createrepo is creating files without group write permission
        # even if umask is 0002.
        find $r -user $USER \! -perm -020 -exec chmod g+w {} \;
    done
}

rsync_ael_rpms_to_eol_repo()
{
    local host=$1
    shift
    local tardir=$(mktemp -d /tmp/XXXXXX)
    cp repo_scripts/repo_funcs.sh $tardir
    while [ $# -gt 0 ]; do
	cp $1 $tardir
	shift
    done
    local tarball=$(mktemp /tmp/XXXXXX.tar.gz)
    tar czf $tarball -C $tardir .
    scp $tarball $host:/tmp
    ssh $host 'td=$(mktemp -d /tmp/XXXXXX); cd $td; tar xzf '$tarball'; source repo_funcs.sh; copy_ael_rpms_to_eol_repo *.rpm; cd /tmp; rm -rf $td;'rm $tarball
    rm -rf $tardir $tarball
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

foldertab()
{
    fill="________________________________________________________________________________"
    maxlen=${#fill}
    cmd_args=$@
    len=${#cmd_args}

    echo ${fill:0:${len}+1}
    echo -n $cmd_args
    echo -n " \\"
    echo ${fill:0:${maxlen}-${len}-2}
    echo
}
