#!/bin/bash
cd "$HOME" || exit
# コンフリクト発生時に対話プロンプトが出た場合、自動で "s"（skip）を送信する
yes "s" | sh -c "$(curl -fsSL get.chezmoi.io)" -- update
