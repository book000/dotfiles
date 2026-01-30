# コマンド履歴の設定

# メモリ上に保存される履歴の数
HISTSIZE=10000
# 履歴ファイルに保存される最大履歴数
SAVEHIST=20000

# 重複するコマンドは履歴に追加しない
setopt hist_ignore_dups
# スペースで始まるコマンドは履歴に追加しない
setopt hist_ignore_space
# 複数の端末間で履歴をリアルタイムに共有する
setopt share_history
