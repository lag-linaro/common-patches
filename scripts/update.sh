#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2021 Google LLC

#set -x
set -e

repo sync -n && git fetch --all

base_commit=$(cat patches/series | grep "Applies onto" | awk '{print $5}')
last_commit=$(cat patches/series | grep "Matches " | awk '{print $4}')
target=aosp/$(cat patches/series | grep "Matches " | awk '{print $3}')

commit_work () {
    _commit=$1
    echo "CHECK THIS DIFFSTAT!!!"
    git diff --stat $_commit
    CLEANUP_PATCHES=1 $(dirname $0)/update_series.sh $base_commit $_commit ${target#*/}
    git -C patches/ add .
    commit_additional_text=""
    if [ $rebase_active -eq 1 ]; then
        commit_additional_text=" (rebase onto $(git describe --tags $base_commit))"
    fi
    git -C patches commit -s -F- <<EOF
$target: update series${commit_additional_text}

up to $(git one $_commit)
EOF
git tag -f processed $_commit
}

reset_tree () {
  git reset --hard $base_commit
  git quiltimport
}

rebase_tree() {
  git rebase $base_commit
}

pick_list=$(git rev-list --first-parent ${last_commit}..${target} --reverse)

if [ -z "$pick_list" ] ; then
    echo "NOTHING TO DO"
    exit
fi

echo "TO UPDATE:"
git --no-pager log --first-parent --oneline ${last_commit}..${target} --reverse

if ! git diff $last_commit --exit-code > /dev/null; then
  echo "Resetting to base"
  reset_tree
fi
work_done=0
for commit in $pick_list; do
    rebase_active=0
    if [ $(git show --no-patch --format="%p" ${commit} | wc -w) -gt 1 ]; then
        if [ $work_done == 1 ]; then
            commit_work ${commit}~1
            echo "NOW REARRANGE THE NEW COMMITS, base is $base_commit"
            exit 0
        fi
        rebase_active=1
        base_commit=$(git show --no-patch --format="%p" ${commit} | awk '{print $2}')
        rebase_tree
        commit_work ${commit}
        work_done=0
        continue
    fi

    set +e
    echo "Applying" `git one $commit`
    git cherry-pick $commit
    if [ $? != 0 ]; then
        git rm -f abi_gki_*
        git cherry-pick --continue
        if [ -z $(git diff --cached) ]; then
            git cherry-pick --skip
        fi
    fi
    set -e
    work_done=1
done

if [ $work_done == 1 ]; then
    commit_work ${commit}
    echo "NOW REARRANGE THE NEW COMMITS, base is $base_commit"
    exit 0
fi
