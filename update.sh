#!/bin/bash
cd "$HOME" || exit
sh -c "$(curl -fsSL get.chezmoi.io)" -- update
