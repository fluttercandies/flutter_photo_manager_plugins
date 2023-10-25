#!/usr/bin/env zsh

# read $0 path
workdir=$(cd $(dirname $0); cd ..; pwd)
cd $workdir

melos version --scope="photo_manager_*" $@