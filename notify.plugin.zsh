# vim: set nowrap filetype=zsh:

plugin_dir="$(dirname $0:A)"

if [[ "$TERM_PROGRAM" == 'iTerm.app' ]] || [[ "$TERM_PROGRAM" == 'Apple_Terminal' ]] || [[ -n "$ITERM_SESSION_ID" ]] || [[ -n "$TERM_SESSION_ID" ]]; then
    source "$plugin_dir"/applescript/functions
elif [[ "$DISPLAY" != '' ]] && command -v xdotool > /dev/null 2>&1 &&  command -v wmctrl > /dev/null 2>&1; then
    source "$plugin_dir"/xdotool/functions
else
    echo "zsh-notify: unsupported environment" >&2
    return
fi

zstyle ':notify:*' plugin-dir "$plugin_dir"
zstyle ':notify:*' command-complete-timeout 10
zstyle ':notify:*' error-log /dev/stderr
zstyle ':notify:*' notifier zsh-notify
zstyle ':notify:*' expire-time 0
zstyle ':notify:*' app-name ''
zstyle ':notify:*' success-title 'Command succeeded (in #{time_elapsed} seconds)'
zstyle ':notify:*' success-sound 'Submarine'
zstyle ':notify:*' success-icon ''
zstyle ':notify:*' error-title 'Command failed (in #{time_elapsed} seconds)'
zstyle ':notify:*' error-sound 'Basso'
zstyle ':notify:*' error-icon ''
zstyle ':notify:*' disable-urgent no
zstyle ':notify:*' activate-terminal no
zstyle ':notify:*' always-check-active-window no
zstyle ':notify:*' check-focus yes
zstyle ':notify:*' blacklist-regex ''
zstyle ':notify:*' enable-on-ssh yes
zstyle ':notify:*' always-notify-on-failure no

unset plugin_dir

# See https://unix.stackexchange.com/q/150649/126543
function _zsh-notify-expand-command-aliases() {
    cmd="$1"
    functions[__expand-aliases-tmp]="${cmd}"
    print -rn -- "${functions[__expand-aliases-tmp]#$'\t'}"
    unset 'functions[__expand-aliases-tmp]'
}

SKIP_NOTIFY_COMMANDS=(
  find
  git
  fg
  bat
  cat
  lazygit
  lg
  man
  nb
  nvim
  ssh
  vim
  watch
  "vagrant ssh"
  "mise run emulate"
  "npm run dev"
  "npm run preview"
  "npm run server"
  "npm run start"
  "pnpm dev"
  "pnpm run dev"
  "pnpm run preview"
  "pnpm run server"
  "pnpm run start"
  "yarn run dev"
  "yarn run preview"
  "yarn run server"
  "yarn run start"
  "gcloud auth application-default login"
)

function _zsh-notify-is-command-blacklisted() {
    local cmd
    cmd="$(_zsh-notify-expand-command-aliases "$zsh_notify_last_command")"
    for skip_cmd in "${SKIP_NOTIFY_COMMANDS[@]}"; do
        if [[ "$cmd" == "$skip_cmd" || "$cmd" == "$skip_cmd"* ]]; then
            return 0
        fi
    done

    local blacklist_regex
    zstyle -s ':notify:*' blacklist-regex blacklist_regex
    if [[ -z "$blacklist_regex" ]]; then
        return 1
    fi

    print -rn -- "$cmd" | grep -q -E "$blacklist_regex"
}

function _zsh-notify-is-ssh() {
    [[ -n ${SSH_CLIENT-} || -n ${SSH_TTY-} || -n ${SSH_CONNECTION-} ]]
}

function _zsh-notify-should-notify() {
    local last_status="$1"
    local time_elapsed="$2"
    if [[ -z $zsh_notify_start_time ]] || _zsh-notify-is-command-blacklisted; then
        return 1
    fi
    local enable_on_ssh
    zstyle -b ':notify:*' enable-on-ssh enable_on_ssh || true
    if _zsh-notify-is-ssh && [[ $enable_on_ssh == 'no' ]]; then
        return 2
    fi
    local always_notify_on_failure
    zstyle -b ':notify:*' always-notify-on-failure always_notify_on_failure
    if ((last_status == 0)) || [[ $always_notify_on_failure == "no" ]]; then
        local command_complete_timeout
        zstyle -s ':notify:*' command-complete-timeout command_complete_timeout
        if (( time_elapsed < command_complete_timeout )); then
            return 3
        fi
    fi
    # this is the last check since it will be the slowest if
    # `always-check-active-window` is set.
    local check_focus
    zstyle -b ':notify:*' check-focus check_focus
    if [[ $check_focus != no ]] && is-terminal-active; then
        return 4
    fi
    return 0
}

# store command line and start time for later
function zsh-notify-before-command() {
    declare -g zsh_notify_last_command="$1"
    declare -g zsh_notify_start_time=$EPOCHSECONDS
}

# notify about the last command's success or failure -- maybe.
function zsh-notify-after-command() {
    local last_status=$?

    local error_log notifier now time_elapsed

    zstyle -s ':notify:' error-log error_log
    zstyle -s ':notify:' notifier notifier

    touch "$error_log"
    (
        (( time_elapsed = EPOCHSECONDS - zsh_notify_start_time ))
        if _zsh-notify-should-notify "$last_status" "$time_elapsed"; then
            local result
            result="$(((last_status == 0)) && echo success || echo error)"
            "$notifier" "$result" "$time_elapsed" <<< "$zsh_notify_last_command"
        fi
    )  2>&1 | sed 's/^/zsh-notify: /' >> "$error_log"

    unset zsh_notify_last_command zsh_notify_start_time

    # Enforce loading of this function
    zsh-notify-list-sounds "true"
}

function zsh-notify-list-sounds() {
    local load
    load=$1

    # When called with "true", just load the function without executing it
    if [[ "$load" == "true" ]]; then
        return
    fi

    if [[ "$TERM_PROGRAM" == 'iTerm.app' ]] || [[ "$TERM_PROGRAM" == 'Apple_Terminal' ]] || [[ -n "$ITERM_SESSION_ID" ]] || [[ -n "$TERM_SESSION_ID" ]]; then
        ls /System/Library/Sounds/ | \
        grep '\.aiff$' | sed 's/\.aiff$//' | \
        fzf --prompt='Select sound: ' --style=minimal --height=40% --layout=reverse --preview='afplay /System/Library/Sounds/{}.aiff' --preview-window=down,border-top,10% | \
        xargs -I{} echo "Execute: zstyle ':notify:*' success-sound '{}' or zstyle ':notify:*' error-sound '{}'"
    else
        echo "zsh-notify-list-sounds: not supported" >&2
        return
    fi
}

zmodload zsh/datetime

autoload -U add-zsh-hook
add-zsh-hook preexec zsh-notify-before-command
add-zsh-hook precmd zsh-notify-after-command
