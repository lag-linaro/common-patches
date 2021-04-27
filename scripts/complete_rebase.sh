#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2021 Google LLC

set -e

base=$1
up_to=$2

CLEANUP_PATCHES=1 ~/howto/quilt/update_series.sh $1 $2
git -C patches add .
git -C patches commit -s -F- <<EOF
aosp/android-mainline: update series (rebase onto $(git describe --tags $base))

up to $(git one $up_to)
EOF

git tag -f processed $up_to
