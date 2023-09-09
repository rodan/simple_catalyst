#!/bin/bash

src_dir="${prefix}/src"
portage_confdir="${prefix}/portage"
build_dir="${prefix}/build/${version_stamp}"
pkgcache_path="${build_dir}/portage/packages/"

unpack_portage() {
    mkdir -p "${build_dir}/portage"
    mkdir -p "${build_dir}/status"

    [ ! -e "${build_dir}/status/portage_unpacked" ] && {
        ebegin "     unpacking ${snapshot} to ${build_dir}/portage/"
        tar -xf "${build_dir}/../${snapshot}" --directory="${build_dir}/portage/"
		rl=$?
        if [[ "${rl}" == "0" ]]; then
            eend '' 0
            date > "${build_dir}/status/portage_unpacked"
        else
            eend '' 1
        fi
    }

    return 0
}

stage1_unpack_upstream_seed() {
    mkdir -p "${build_dir}/stage1"

    [ ! -e "${build_dir}/status/stage1_upstream_unpacked" ] && {
        ebegin "     unpacking ${source_subpath} to ${build_dir}/stage1/"
        tar -xf "${build_dir}/../${source_subpath}" --directory="${build_dir}/stage1/"
        rl=$?
        if [[ "${rl}" == "0" ]]; then
            eend '' 0
            date > "${build_dir}/status/stage1_upstream_unpacked"
        else
            eend '' 1
        fi
    }

    return 0
}

stage2_rsync() {
    mkdir -p "${build_dir}/stage2"

    [ ! -e "${build_dir}/status/stage2_synced" ] && {
        ebegin "     rsync ${build_dir}/stage1 to ${build_dir}/stage2/"
        rsync -a --delete "${build_dir}/stage1/" "${build_dir}/stage2/"
        rl=$?
		rm -rf "${build_dir}/stage2/tmp/*.spec"
        if [[ "${rl}" == "0" ]]; then
            eend '' 0
            date > "${build_dir}/status/stage2_synced"
        else
            eend '' 1
        fi
    }

    return 0
}

stage2_rsync_root_overlay() {
    [ -n "${livecd_root_overlay}" ] && [ -e "${livecd_root_overlay}" ] && {
        ebegin "     rsync ${livecd_root_overlay} to ${build_dir}/stage2/"
        rsync -a "${livecd_root_overlay}/" "${build_dir}/stage2/"
        rl=$?
		eend '' $rl
    }
    return 0
}

prepare_etc_portage() {
	stage=$1
	rl=0
    ebegin '     prepare configs and overlays'
    rsync -a --delete "${portage_confdir}/" "${build_dir}/stage${stage}/etc/portage/"
	rl=$((rl + $?))
    mkdir -p "${build_dir}/stage1/local/portage/overlay"
	rl=$((rl + $?))
    rsync -a --delete "${portage_overlay}/" "${build_dir}/stage${stage}/local/portage/overlay"
	rl=$((rl + $?))
    cp -f /etc/resolv.conf "${build_dir}/stage${stage}/etc/"
	rl=$((rl + $?))
	mkdir -p "${build_dir}/stage${stage}/dev/shm/"
	[ -e "${spec}_emerge" ] && {
		cp -f "${spec}_emerge" "${build_dir}/stage${stage}/dev/shm/emerge.spec"
		rl=$((rl + $?))
	}
	[ -e "${spec}_unmerge" ] && {
		cp -f "${spec}_unmerge" "${build_dir}/stage${stage}/dev/shm/unmerge.spec"
		rl=$((rl + $?))
	}
	[ -e "${spec}_empty" ] && {
		cp -f "${spec}_empty" "${build_dir}/stage${stage}/dev/shm/empty.spec"
		rl=$((rl + $?))
	}
	[ -e "${spec}_rm" ] && {
		cp -f "${spec}_rm" "${build_dir}/stage${stage}/dev/shm/rm.spec"
		rl=$((rl + $?))
	}
	[ -n "${livecd_fsscript}" ] && [ -e "${src_dir}/${livecd_fsscript}" ] && {
		cp -f "${src_dir}/${livecd_fsscript}" "${build_dir}/stage${stage}/dev/shm/fsscript.sh"
	}
	eend '' ${rl}
    return ${rl}
}


mount_bind_start() {
    stage=$1

    [[ "${stage}" == "0" ]] && exit 1
    CHROOT_DIR=$(readlink -f "${build_dir}/stage${stage}")

    [[ "${stage}" == "1" ]] && {
            mount | grep -q "${CHROOT_DIR}/local/portage/packages" || {
            mkdir -p "${CHROOT_DIR}/local/portage/packages"
            mkdir -p "${pkgcache_path}"
            echo "bind mount ${pkgcache_path} to ${CHROOT_DIR}/local/portage/packages"
            mount -o bind "${pkgcache_path}" "${CHROOT_DIR}/local/portage/packages"
        }
        mkdir -p "${CHROOT_DIR}/local/distfiles"
        mount | grep -q "${CHROOT_DIR}/local/portage/distfiles" || {
            mkdir -p "${CHROOT_DIR}/local/portage/distfiles"
            mount -o bind /local/portage/distfiles "${CHROOT_DIR}/local/portage/distfiles"
        }
    }

    mount | grep -q "${CHROOT_DIR}/usr/portage" || {
        mkdir -p "${CHROOT_DIR}/usr/portage"
        mount -o bind "${build_dir}/portage/portage" "${CHROOT_DIR}/usr/portage"
    }

    mount | grep -q "${CHROOT_DIR}/dev " || \
        mount -o bind /dev "${CHROOT_DIR}/dev"
    mount | grep -q "${CHROOT_DIR}/dev/shm " || \
        mount -t tmpfs none "${CHROOT_DIR}/dev/shm"
    mount | grep -q "${CHROOT_DIR}/sys " || \
        mount -o bind /sys "${CHROOT_DIR}/sys"
    mount | grep -q "${CHROOT_DIR}/proc " || \
        mount -o bind /proc "${CHROOT_DIR}/proc"
    mount | grep -q "${CHROOT_DIR}/tmp " || \
        mount -t tmpfs none "${CHROOT_DIR}/tmp"
    mount | grep -q "${CHROOT_DIR}/tmp/status " || {
        mkdir -p "${CHROOT_DIR}/tmp/status"
        mount -o bind "${build_dir}/status/" "${CHROOT_DIR}/tmp/status"
    }

    return 0
}

mount_bind_stop() {
    stage=$1

    [[ "${stage}" == "0" ]] && exit 1
    CHROOT_DIR=$(readlink -f "${build_dir}/stage${stage}")

    mount | grep -q "${CHROOT_DIR}/local/portage/distfiles " && \
        umount "${CHROOT_DIR}/local/portage/distfiles"
    mount | grep -q "${CHROOT_DIR}/local/portage/packages " && \
        umount "${CHROOT_DIR}/local/portage/packages"
    mount | grep -q "${CHROOT_DIR}/usr/portage " && \
        umount "${CHROOT_DIR}/usr/portage"
    mount | grep -q "${CHROOT_DIR}/dev/shm " && \
        umount "${CHROOT_DIR}/dev/shm"
    mount | grep -q "${CHROOT_DIR}/dev " && \
        umount "${CHROOT_DIR}/dev"
    mount | grep -q "${CHROOT_DIR}/sys " && \
        umount "${CHROOT_DIR}/sys"
    mount | grep -q "${CHROOT_DIR}/proc " && \
        umount "${CHROOT_DIR}/proc"
    mount | grep -q "${CHROOT_DIR}/tmp/status " && \
        umount "${CHROOT_DIR}/tmp/status"
    mount | grep -q "${CHROOT_DIR}/tmp " && \
        umount "${CHROOT_DIR}/tmp"

    return 0
}

mount_bind_stop_partial() {
    stage=$1

    [[ "${stage}" == "0" ]] && exit 1
    CHROOT_DIR=$(readlink -f "${build_dir}/stage${stage}")

    mount | grep -q "${CHROOT_DIR}/local/portage/distfiles " && \
        umount "${CHROOT_DIR}/local/portage/distfiles"
    mount | grep -q "${CHROOT_DIR}/local/portage/packages " && \
        umount "${CHROOT_DIR}/local/portage/packages"
    mount | grep -q "${CHROOT_DIR}/usr/portage " && \
        umount "${CHROOT_DIR}/usr/portage"

    return 0
}

stage1_chroot() {

    ebegin "     chroot into ${build_dir}/stage1/"
    chroot "${build_dir}/stage1/" /bin/bash << EOF
        eselect news read &> /dev/null
        export FEATURES="-collision-protect"
        echo "   * update portage if needed"
        emerge -uq --usepkg portage portage-utils
        [ ! -e "/tmp/status/stage1_unmerge" ] && {
            [ -e "/dev/shm/unmerge.spec" ] && {
                echo "   * unmerge custom list of packages"
                emerge -q --unmerge \$(grep -Ev '(^#)|(^$)' /dev/shm/unmerge.spec | xargs)
                rl=$?
                if [[ "${rl}" == "0" ]]; then
                    eend '' 0
                    date > "/tmp/status/stage1_unmerge"
                else
                    eend '' 1
                fi
            }
        }
        [ ! -e "/tmp/status/stage1_update" ] && {
            echo "   * update stage3 image"
            emerge -qN --usepkg \$(qlist -IC)
            #emerge -pvN --usepkg \$(qlist -IC)
            rl=$?
            if [[ "${rl}" == "0" ]]; then
                eend '' 0
                date > "/tmp/status/stage1_update"
            else
                eend '' 1
            fi
        }
        [ -e "/dev/shm/emerge.spec" ] && {
            echo "   * install custom list of packages"
			emerge -uq --usepkg \$(grep -Ev '(^#)|(^$)' /dev/shm/emerge.spec | xargs)
			#emerge -upv --usepkg \$(grep -Ev '(^#)|(^$)' /dev/shm/emerge.spec | xargs)
			exit $?
		}
		exit 0
EOF
    return 0
}

stage2_0_chroot() {
    ebegin "chroot (1/2) into ${build_dir}/stage2/"
    chroot "${build_dir}/stage2/" /bin/bash << EOF
		[ ! -e /usr/bin/emerge ] && exit 0
        [ -e "/dev/shm/unmerge.spec" ] && {
        	echo "   * uninstall packages"
			emerge --unmerge \$(grep -Ev '(^#)|(^$)' /dev/shm/unmerge.spec | xargs)
		}
		exit 0
EOF
    return 0
}

stage2_1_chroot() {
    ebegin "chroot (2/2) into ${build_dir}/stage2/"
    chroot "${build_dir}/stage2/" /bin/bash << EOF
        eselect news read &> /dev/null
        [ -e "/dev/shm/rm.spec" ] && {
            grep -Ev '(^#)|(^$)' /dev/shm/rm.spec | while read i; do
                echo "\${i}"
				rm -rf "\${i}"
			done
		}
        [ -e "/dev/shm/empty.spec" ] && {
            grep -Ev '(^#)|(^$)' /dev/shm/empty.spec | while read i; do
				rm -rf \${i}/*
			done
		}
		[ -e /dev/shm/fsscript.sh ] && bash /dev/shm/fsscript.sh
		exit 0
EOF
    return 0
}

stage2_mksquashfs() {
    ebegin "     create squashfs image"
	mkdir -p "${build_dir}/cd"
	mksquashfs "${build_dir}/stage${stage}" "${build_dir}/cd/image.squashfs" -noappend > /dev/null
	rl=$?
	eend '' ${rl}
    return ${rl}
}

stage2_rsync_cd_overlay() {
	rl=0
    [ -n "${livecd_overlay}" ] && [ -e "${livecd_overlay}" ] && {
        ebegin "     rsync ${livecd_overlay} to ${build_dir}/cd/"
        rsync -a "${livecd_overlay}/" "${build_dir}/cd/"
        rl=$?
		eend '' $rl
    }
    return $rl
}

stage2_mkisofs() {
	rl=0
    [ -n "${livecd_iso}" ] && {
        ebegin "     do mkisofs"
		cd "${build_dir}/cd/" || exit
		mkisofs -quiet -J -R -l  -V "${livecd_volid}" -o "${livecd_iso}" -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table "${build_dir}/cd/"
        rl=$?
		eend '' $rl
		ls -al "${livecd_iso}"
    }
    return $rl
}

