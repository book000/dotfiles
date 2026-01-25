# コマンド履歴の設定

# 履歴ファイルに保存される履歴の数
HISTSIZE=10000
# 履歴ファイル自体の最大行数
HISTFILESIZE=20000
# ignoreboth: 空白で始まるコマンドと、重複したコマンドを履歴に保存しない
# erasedups: 以前の履歴から重複を除去する
HISTCONTROL=ignoreboth:erasedups
# 履歴に日時を記録するフォーマット (YYYY-MM-DD HH:MM:SS )
HISTTIMEFORMAT="%F %T "
# histappend: シェル終了時に履歴を上書きせず追記する
# checkwinsize: ウィンドウサイズ変更時にLINESとCOLUMNSを更新する
shopt -s histappend checkwinsize

# 複数の端末間で履歴を同期するための関数
__bashrc_history_sync() {
  history -a # メモリ上の履歴をファイルに追記
  history -c # メモリ上の履歴をクリア
  history -r # ファイルから履歴を読み込む
}

# プロンプト表示の直前に履歴同期関数を実行するように設定
if [ -n "${PROMPT_COMMAND:-}" ]; then
  PROMPT_COMMAND="__bashrc_history_sync;${PROMPT_COMMAND}"
else
  PROMPT_COMMAND="__bashrc_history_sync"
fi