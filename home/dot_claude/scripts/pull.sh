#!/bin/bash
cd ~/.claude/ || exit
git pull 2>&1 | grep -v "Already up to date."
