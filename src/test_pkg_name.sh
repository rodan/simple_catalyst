#!/bin/bash

cat $1 | while read line; do
    [ -z "${line}" ] && continue
    [ -d "/usr/portage/${line}" ] || echo "${line} is missing!"
done

