# mise が利用可能な場合、activate する
if ! command -v mise >/dev/null 2>&1; then
    # mise が見つからない場合は何もしない
    return 0
fi

# mise を有効化
eval "$(mise activate bash)"