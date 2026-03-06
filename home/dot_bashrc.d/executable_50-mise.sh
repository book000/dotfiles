# mise が利用可能な場合、activate する
if ! command -v mise &> /dev/null; then
    # mise が見つからない場合は何もしない
    return
fi

# mise を有効化
eval "$(mise activate bash)"