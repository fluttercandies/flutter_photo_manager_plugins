#!/bin/bash

# check hugo installed
if ! [ -x "$(command -v hugo)" ]; then
  echo 'Error: hugo is not installed.' >&2
  exit 1
fi

pwd=$(cd `dirname $0`; pwd)
cd "$pwd/hugo"
hugo serve -D --bind 0.0.0.0