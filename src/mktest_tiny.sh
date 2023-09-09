#!/bin/bash

. ../specs/livecd-tiny-stage2.spec

qemu-system-x86_64 -m 2G -cdrom ../build/${version_stamp}/cd/${livecd_iso}
