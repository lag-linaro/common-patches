#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2021 Google LLC

if [ "$#" -gt 3 ]; then
    echo "Usage: $0 <base> <up_to> <name>"
    exit 1
fi

base=$1
up_to=${2:-aosp/android-mainline}
name=${3:-android-mainline}

if [ -n "$CLEANUP_PATCHES" ]; then
    rm patches/*.patch
fi

echo "# Android Series" > patches/series
cat <<EOT > patches/series
#
# $name patches
#
# Applies onto upstream $(git log -1 --format=%h $base) Linux $(git describe --tags $base)
# Matches $name $(git show -s --pretty='format:%h ("%s")' $up_to)
#
EOT

files=()  # keep track of used file names to deal with collisions

for sha1 in $(git rev-list $base.. --reverse); do

  # get the file name
  name=$(git show -s --format=%f $sha1)
  printf -v patch_file "%s.patch" $name

  # check for and work around collisions
  index=1
  while [[ " ${files[@]} " =~ " ${patch_file} " ]]; do
    ((index++))
    printf -v patch_file "%s-%d.patch" $name $index
  done
  files+=($patch_file)

  # write the actual patch file and update the series
  git format-patch $sha1 -1 --no-signoff    \
                            --keep-subject  \
                            --zero-commit   \
                            --no-signature  \
                            --stdout > patches/$patch_file
  sed -i '/index [0-9a-f]\{12,\}\.\.[0-9a-f]\{12,\} [0-9]\{6\}/d' patches/$patch_file
  sed -i '/index [0-9a-f]\{12,\}\.\.[0-9a-f]\{12,\}$/d' patches/$patch_file
  echo $patch_file >> patches/series

done
