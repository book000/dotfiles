# History behavior.
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoreboth:erasedups
HISTTIMEFORMAT="%F %T "
shopt -s histappend checkwinsize

__bashrc_history_sync() {
  history -a
  history -c
  history -r
}
if [ -n "${PROMPT_COMMAND:-}" ]; then
  PROMPT_COMMAND="__bashrc_history_sync;${PROMPT_COMMAND}"
else
  PROMPT_COMMAND="__bashrc_history_sync"
fi
