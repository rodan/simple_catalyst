#!/bin/bash

prefix=$(pwd)

. /etc/init.d/functions.sh

abort()
{
    echo 'execution has been canceled due to an error, exiting' >&2
    exit 1
}

trap 'abort' 0
# exit if any error is detected
set -e

live_do_mount=false
live_do_umount=false
live_do_spec=false

while (( "$#" )); do
        if [ "$1" == "--spec" ] || [ "$1" == "-s" ]; then
            shift;
            spec=$1
            live_do_spec=true
            shift;
        elif [ "$1" == "--mount" ] || [ "$1" == "-m" ]; then
            live_do_mount=true
            shift;
        elif [ "$1" == "--umount" ] || [ "$1" == "-u" ]; then
            live_do_umount=true
            shift;
        elif [ "$1" == "--verbose" ] || [ "$1" == "-v" ]; then
            set -x
            shift;
        else
            shift;
        fi
done

[ ! -e "${spec}" ] && {
    echo 'spec file not provided, exiting'
    exit 1
}

. "${spec}"
. "${prefix}/src/sc_functions.sh"

[ -z "${stage}" ] && {
	echo 'stage not defined in the spec file, exiting'
	exit 1
}

${live_do_mount} && {
    mount_bind_start "${stage}"
    trap : 0
    exit 0
}

${live_do_umount} && {
    mount_bind_stop "${stage}"
    trap : 0
    exit 0
}

mkdir -p "${build_dir}"
unpack_portage

if [ "${stage}" == "1" ]; then
	stage1_unpack_upstream_seed
	mount_bind_start 1
	prepare_etc_portage 1
	stage1_chroot
	mount_bind_stop 1
elif [ "${stage}" == "2" ]; then
	stage2_rsync
	mount_bind_start 2
	prepare_etc_portage 2
	stage2_0_chroot
	mount_bind_stop_partial 2
	stage2_1_chroot
	mount_bind_stop 2
	stage2_rsync_root_overlay
	stage2_mksquashfs
	stage2_rsync_cd_overlay
	stage2_mkisofs
fi

# disable trap
trap : 0

