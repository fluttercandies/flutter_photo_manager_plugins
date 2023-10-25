#!/usr/bin/env zsh

# read $0 path
workdir=$(cd $(dirname $0); cd ..; pwd)
cd $workdir

# check upload flag(-f)

if [ "$1" = "-f" ]; then
    echo "uploading..."
    melos publish --scope="photo_manager_*" --yes --no-dry-run
else
    echo "dry run..."
    melos publish --scope="photo_manager_*" --yes --dry-run 
fi