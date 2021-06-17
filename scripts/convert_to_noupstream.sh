#!/bin/bash

set -e
set -x

pushd $(dirname $0)/../android-mainline

for f in `git status --short | grep "?? NOUPSTREAM" | sed 's/?? //'`; do
    orig=`echo ${f} | sed 's/NOUPSTREAM-//'`

    mv ${f} ${orig}
    git mv ${orig} ${f}
done

popd
