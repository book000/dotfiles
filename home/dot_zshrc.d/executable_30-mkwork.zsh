# mkwork (https://github.com/book000/mkwork) の設定
# mkwork用のスクリプトが存在すれば読み込む
if [ -f "$HOME/.local/share/mkwork/mkwork.sh" ]; then
  # shellcheck source=/dev/null
  . "$HOME/.local/share/mkwork/mkwork.sh"
fi
