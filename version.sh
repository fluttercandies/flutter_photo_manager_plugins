#!/usr/bin/env zsh

melos version --scope="photo_manager_*"

# sign off all commits
git commit --amend -S --signoff --no-edit