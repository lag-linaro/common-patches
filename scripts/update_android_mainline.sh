#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2021 Google LLC

#set -x # Uncomment to enable debugging
set -e

trap "tput smam; exit 1" SIGINT SIGTERM

print_red()
{
    echo -e "\e[01;31m$@\e[0m"
}

print_blue()
{
    echo -e "\e[01;34m$@\e[0m"
}

function is_merge_commit()
{
    local commit=${1}

    if [ $(git show --no-patch --format="%p" ${commit} | wc -w) -gt 1 ]; then
        return 0
    else
        return 1
    fi
}

function read_series_file()
{
    base_commit=$(cat patches/series | grep "Applies onto" | awk '{print $5}')
    last_commit=$(cat patches/series | grep "Matches " | awk '{print $4}')
    target=aosp/$(cat patches/series | grep "Matches " | awk '{print $3}')
}

function sanity_check()
{
    if [[ ! -L patches || ! -d patches || ! -e patches/series ]]; then
        print_red "'patches' symlink to 'common-patches' repo is missing"
        exit 1
    fi
}

function setup()
{
    sanity_check

    read_series_file

    if ! git remote | grep -q "^stable$"; then
        print_blue "Couldn't find repo 'stable' - adding it now"
        git remote add stable git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
    fi

    if ! git remote | grep -q "^mainline$"; then
        print_blue "Couldn't find repo 'mainline' - adding it now"
        git remote add mainline git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
    fi

    # For `repo checkout` managed repositories (see: https://source.android.com/setup/build/building-kernels)

    if which repo > /dev/null && repo > /dev/null 2>&1; then
        repo sync -n && git fetch --all
        return 0
    fi

    # For non-`repo`/manually managed repositories

    if ! git remote | grep -q "^aosp$"; then
        print_blue "Couldn't find repo 'aosp' - adding it now"
        git remote add aosp https://android.googlesource.com/kernel/common.git
    fi

    print_blue "Fetching from Mainline"
    git fetch mainline
    print_blue "Fetching from Stable"
    git fetch stable
    print_blue "Fetching from AOSP"
    git fetch aosp
    echo
}

function preamble()
{
    setup # Conduct sanity checks, update remotes and read series file

    # Ensure repo is in expected state
    if ! git diff ${last_commit} --exit-code > /dev/null; then
        print_blue "Tree is out of sync with 'common-patches' - resetting\n"
        git reset --hard ${base_commit}
        git quiltimport
    fi

    # Obtain list of patches to be processed
    pick_list=$(git rev-list --first-parent ${last_commit}..${target} --reverse)

    # Exit successfully if there's nothing to be done
    if [ -z "$pick_list" ] ; then
        print_blue "Great news - we're up-to-date"
        exit 0
    fi

    print_blue "Patches to process from ${target}"
    tput rmam    # Don't wrap
    git --no-pager log --first-parent --format="%C(auto)  %h %s" ${last_commit}..${target} --reverse
    tput smam    # Reset wrapping
    echo
}

function rebase_no_fail
{
    local args=${@}

    git rebase ${args} && true
    while [ $? -ne 0 ]; do
        print_red "\nRebase failed\n"
        print_blue "Either use another shell or Ctrl+z this one to fix, then \`fg\` and hit return"
        read
        if git rebase --show-current-patch 2>&1 | grep -q "No rebase in progress"; then
            print_blue "Rebase no longer in progress - assuming the issue was rectified"
        else
            git rebase --continue && true
        fi
    done
    echo
}
function create_series_and_patch_files()
{
    up_to=${1}
    branch=${target#*/}

    rm patches/*.patch

    echo "# Android Series" > patches/series
    cat <<EOT > patches/series
#
# $branch patches
#
# Applies onto upstream $(git log -1 --format=%h $base_commit) Linux $(git describe --tags $base_commit)
# Matches $branch $(git show -s --pretty='format:%h ("%s")' $up_to)
#
EOT

    files=()  # Keep track of used *.patch file names to deal with collisions

    print_blue "Updating 'series' file\n"
    for sha1 in $(git rev-list ${base_commit}.. --reverse); do

        # Create the *.patch filename
        patchfilename=$(git show -s --format=%f ${sha1})
        printf -v patch_file "%s.patch" ${patchfilename}

        # Identify and work around collisions (<name>-<index>.patch)
        index=1
        while [[ " ${files[@]} " =~ " ${patch_file} " ]]; do
            ((index++))
            printf -v patch_file "%s-%d.patch" ${patchfilename} ${index}
        done
        files+=(${patch_file})

        # Write the actual patch file and update the series file
        git format-patch ${sha1} -1 \
            --no-signoff    \
            --keep-subject  \
            --zero-commit   \
            --no-signature  \
            --stdout > patches/${patch_file}

        # Remove 'index' changes - they are not required and clog up the diff
        sed -i '/index [0-9a-f]\{12,\}\.\.[0-9a-f]\{12,\} [0-9]\{6\}/d' patches/$patch_file
        sed -i '/index [0-9a-f]\{12,\}\.\.[0-9a-f]\{12,\}$/d' patches/$patch_file

        print_blue "Adding ${patch_file}"
        echo ${patch_file} >> patches/series
    done
    echo
}

commit_patches () {
    local commit=${1}

    if ! git --no-pager diff ${commit} --exit-code > /dev/null; then
        print_red -e "Failure: Unexpected diff found:\n"
        git --no-pager diff ${commit}
        exit 1
    fi

    if ! is_merge_commit ${commit}; then
        print_blue "Entering interactive rebase to rearrange (press return to continue or Ctrl+c to exit)"
        read

        rebase_no_fail -i ${base_commit}
    fi

    create_series_and_patch_files ${commit}

    print_blue "Committing all changes into 'common-patches' repo\n"
    git -C patches/ add .
    git -C patches commit -s -F- <<EOF
$target: update series${commit_additional_text}

up to $(git --no-pager show -s --pretty='format:%h ("%s")' ${commit})
EOF
    echo

    # Read new (base, last and target) variables
    read_series_file
}

function process_merge_commit()
{
    local commit=${1}

    base_commit=$(git show --no-patch --format="%p" ${commit} | awk '{print $2}')
    base_commit_desc=$(git describe --tags $base_commit)

    print_blue "Found merge (new base) commit - rebasing onto ${base_commit_desc}\n"

    rebase_no_fail ${base_commit}
    echo

    commit_additional_text=" (rebase onto ${base_commit_desc})"
    commit_patches ${commit}
}

function process_normal_commit()
{
    local commit=${1}

    print_blue "Applying: "

    git cherry-pick ${commit}

    echo
}

function process_pick_list()
{
    local commit=${1}

    # Handle merge commit - ${target} has a new merge-base
    if is_merge_commit ${commit}; then

        # Apply any regular patches already processed before this merge
        if [ "$(git diff ${last_commit}..HEAD)" != "" ]; then
            commit_additional_text=""
            commit_patches ${commit}~1    # This specifies the last 'normal commit' before the 'merge commit'
        fi

        process_merge_commit ${commit}
        return
    fi

    process_normal_commit ${commit}
}

function start()
{
    preamble    # Start-up checks and initialisation

    for commit in ${pick_list}; do
        process_pick_list ${commit}
    done

    # Apply any regular patches already processed
    if [ "$(git diff ${last_commit}..HEAD)" != "" ]; then
        commit_additional_text=""
        commit_patches ${commit}    # Commit up to last 'normal commit' processed
    fi

    print_blue "That's it, all done!"
    exit 0
}

start
