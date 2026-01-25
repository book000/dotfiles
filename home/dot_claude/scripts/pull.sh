#!/bin/bash
set -e

cd ~/.claude/ || exit
git pull 2>&1 | grep -v "Already up to date."
git_status=${PIPESTATUS[0]}
exit "$git_status"
