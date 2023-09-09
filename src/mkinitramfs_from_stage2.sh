#!/bin/bash

stage2_dir="/local/xcomp/simple_catalyst/build/livecd-tiny-2023.09-amd64/stage2"
out_fname='initramfs-tiny-2023.09'

cd "${stage2_dir}" || {
    exit 1
}

ln -s /sbin/init init
chmod +x init

find ./ | cpio --quiet -o -H newc --owner root:root --force-local > "../${out_fname}.cpio"
xz -e --check=none --compress --force -9 < "../${out_fname}.cpio" > "../${out_fname}.igz" &&
	rm "../${out_fname}.cpio"

