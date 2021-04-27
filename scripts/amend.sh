#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2021 Google LLC

set -e

base_commit=$(cat patches/series | grep "Applies onto" | awk '{print $5}')
last_commit=$(cat patches/series | grep "Matches " | awk '{print $4}')
target=aosp/$(cat patches/series | grep "Matches " | awk '{print $3}')

CLEANUP_PATCHES=1 ~/howto/quilt/update_series.sh $base_commit $last_commit ${target#*/}
#git -C patches/ commit --amend -a -CHEAD
