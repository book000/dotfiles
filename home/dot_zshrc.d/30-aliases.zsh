# 一般的なエイリアスの設定
alias ll='ls -alF'             # 詳細リスト表示、隠しファイル含む、ファイル種別識別子付き
alias l='ls -CF'               # 列表示、ファイル種別識別子付き
alias la='ls -A'               # . と .. を除くすべてのファイルを表示
alias ..='cd ..'               # 親ディレクトリへ移動
alias ...='cd ../..'           # 2階層上のディレクトリへ移動
alias grep='grep --color=auto' # grepの検索結果をカラー表示