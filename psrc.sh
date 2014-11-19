#!/bin/bash

########################################################################
# Copyright (c) 2014, NDP, LLC
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#
# 1. Redistributions of source code must retain the above copyright
# notice, this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright
# notice, this list of conditions and the following disclaimer in the
# documentation and/or other materials provided with the distribution.
#
# 3. Neither the name of the copyright holder nor the names of its
# contributors may be used to endorse or promote products derived from
# this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
########################################################################

psrc_init() {
  trap psrc_cleanup 0 1 2 3 4 5 7 8 9 10 11 12 14 15
  export TZ=UTC
  mkdir -p "$PSRC_TMP" "$PSRC_CTRL"
}

psrc_log() {
  echo "$@" >&2
}

psrc_debug() {
  if [ "$PSRC_DEBUG" != 0 ]; then
    psrc_log "$@"
  fi
}

psrc_log_remote() {
  local host="$1"
  shift
  echo "$host <<" "$@" >&2
}

psrc_cleanup() {
  rmdir "$PSRC_CTRL" "$RM_TMP" >/dev/null 2>&1
}

psrc_stop() {
  local host=""
  for host in `psrc_list_hosts`; do
    psrc_stop_slave "$host"
  done
  if [ -n "$PSRC_TMP" ] && [ -d "$PSRC_TMP" ]; then
    /bin/rm -rf "$PSRC_TMP" >/dev/null 2>&1
  fi
}

psrc_set_env() {
  local f
  TMPDIR=${TMPDIR:-/tmp}
  for f in "${BASH_SOURCE[0]}" "$0"; do
    if [ -e "$f" ]; then
      PSRC_HOME="`dirname "$f"`"
      PSRC_HOME="`cd "$PSRC_HOME" >/dev/null 2>&1 && pwd`"
      [ -d "$PSRC_HOME" ] && break
    fi
  done
  PSRC_NAME="`basename $0`"
  PSRC_TMP="$TMPDIR/${PSRC_NAME}.${USER:-unknown}.${HOSTNAME:-unknown}"
  PSRC_CTRL="$PSRC_TMP/control"
  PSRC_CMD="$PSRC_HOME/commands.d"
  PSRC_DEBUG="${PSRC_DEBUG:-0}"
  if [ "$PSRC_DEBUG" != 0 ]; then
    PSRC_DEBUG_X="-x"
  else
    PSRC_DEBUG_X=""
  fi
  PSRC_UNBUFFER="/usr/bin/stdbuf -i0 -oL -eL"
  PSRC_TAG="+PSRC::"
}

psrc_load_commands() {
  local f
  for f in "$PSRC_CMD"/*.sh; do
    if [ -e "$f" ]; then
      . "$f"
    fi
  done
}

psrc_list_hosts() {
  (test -d "$PSRC_CTRL" && cd "$PSRC_CTRL" && /bin/ls -1 *.ctrl 2>/dev/null | sed 's/.ctrl$//')
}

psrc_call() {
  local host="$1"
  shift
  local cmd="$1"
  shift
  if [ x"$host" = x"ALL" ]; then
    psrc_send_command "ALL" "$cmd" "$@"
    psrc_recv_return "ALL"
  else
    psrc_send_command "$host" "$cmd" "$@"
    psrc_recv_return "$host"
  fi
}

psrc_send_command() {
  local host="$1"
  shift
  local cmd="$1"
  shift
  if [ x"$host" = x"ALL" ]; then
    psrc_all psrc_send_command "$cmd" "$@"
  else
    local arg
    local i=0
    while [ $i -lt $# ]; do
      arg="${arg}${arg+ }%q"
      i=`expr $i + 1`
    done
    psrc_debug "arg = $arg"
    printf -v arg "$arg" "$@"
    if [ -e "$PSRC_CTRL/$host.ctrl" ]; then
      psrc_debug "$host >>" "$cmd" "$arg"
      echo "$cmd" "$arg" >> "$PSRC_CTRL/$host.ctrl"
    fi
  fi
}

psrc_recv_return() {
  local host="$1"
  shift
  local timeout="${1+-t }$1"
  shift
  if [ x"$host" = x"ALL" ]; then
    psrc_all psrc_recv_return $timeout
  else
    local line=""
    local stat=1
    if [ -e "$PSRC_CTRL/$host.out" ]; then
      exec 3<"$PSRC_CTRL/$host.out"
      while read -r -s $timeout -u 3 line >/dev/null; do
        case "${line%% *}" in
          "${PSRC_TAG}RETURN")
            psrc_log_remote "$host" "$line"
            stat="`echo "$line" | cut -d ' ' -f 2`"
            break
            ;;
          "${PSRC_TAG}"*)
            psrc_log_remote "$host" "$line"
            stat=2
            #break
            ;;
          *)
            psrc_log_remote "$host" "$line"
            ;;
        esac
      done
      exec 3<&-
    fi
    psrc_debug "[$host] recv $stat"
    return $stat
  fi
}

psrc_slave() {
  psrc_load_commands
  local line=""
  local cmd=""
  local arg=""
  while read -r -s line >/dev/null; do
    psrc_debug "[slave]" "$line"
    cmd="${line%% *}"
    arg="${line#* }"
    case "$cmd" in
      "${PSRC_TAG}ENV")
        # EXPLOITABLE: Using $arg unquoted allows exploitation by anyone
        # able to write to the control socket on the controlling host
        eval psrc_slave_env $arg
        ;;
      "${PSRC_TAG}EXIT")
        psrc_slave_exit
        ;;
      "${PSRC_TAG}HELLO")
        psrc_slave_return 0 "$line"
        ;;
      "${PSRC_TAG}INFO")
        psrc_slave_info
        ;;
      "${PSRC_TAG}PING")
        psrc_slave_return 0 "$line"
        ;;
      "${PSRC_TAG}RUN")
        # EXPLOITABLE: Using $arg unquoted allows exploitation by anyone
        # able to write to the control socket on the controlling host
        eval psrc_slave_run $arg
        ;;
      "${PSRC_TAG}"*)
        # unknown
        psrc_slave_return 1 "$line"
        ;;
      ""|"#"*)
        # ignore
        ;;
      *)
        ;;
    esac
  done
  psrc_slave_exit
}

psrc_slave_return() {
  echo "${PSRC_TAG}RETURN" "$@"
}

psrc_slave_info() {
  echo "=== Startup:"
  echo "\$0=$0"
  echo "id=`id -a`"
  echo "umask=`umask`"
  echo "CWD=`pwd`"
  echo "HOST=`hostname -f`"
  echo "PID=$$"
  local var
  for var in PSRC_HOME PSRC_CMD PSRC_TMP PSRC_CTRL USER HOSTNAME SHELL SHELLOPTS BASH BASHOPTS BASHPID BASH_ARGC BASH_ARGV BASH_COMMAND BASH_ENV BASH_SOURCE BASH_SUBSHELL BASH_VERSINFO BASH_VERSION UID EUID OSTYPE; do
    printf '%q=%q\n' "$var" "`eval echo \\$$var`"
  done
  echo "=== Environment:"
  /usr/bin/env | /usr/bin/env LC_ALL=C /usr/bin/sort
  psrc_slave_return 0 "${PSRC_TAG}INFO"
}

psrc_slave_exit() {
  psrc_slave_return 0 "Exiting..."
  exit 0
}

psrc_slave_run() {
  local cmd="$1"
  shift
  cmd="${cmd##*/}"
  if [ -e "$PSRC_CMD/$cmd.sh" ]; then
    "$cmd" "$@"
    psrc_slave_return $? "$cmd" "$@"
  else
    psrc_slave_return 1 "Invalid command: $cmd"
  fi
}

psrc_slave_env() {
  local var="$1"
  shift
  local val="$1"
  shift
  local tvar="`echo $var | sed 's/[^A-Z0-9a-z_]//g'`"
  if [ "$var" != "$tvar" ]; then
    psrc_slave_return 1 "Invalid environment variable: $var"
    return 1
  fi
  case "$var" in
    PATH|SHELL|LD_*)
      psrc_slave_return 1 "Denied modification of system environment variable: $var"
      return 1
      ;;
    PSRC_*)
      psrc_slave_return 1 "Denied modification of program environment variable: $var"
      return 1
      ;;
    *)
      ;;
  esac
  eval "`printf '%q=%q' "$var" "$val"`"
  export $var
  psrc_slave_return 0 "$var=$val"
}

psrc_foreach() {
  local cmd="$1"
  shift
  local each=""
  local stat=0
  for each in "$@"; do
    "$cmd" "$each"
    if [ $? != 0 ]; then
      stat=1
    fi
  done
  return $stat
}

psrc_ssh() {
  exec /usr/bin/ssh \
    -q \
    -x \
    -T \
    -o BatchMode=yes \
    -o EscapeChar=none \
    "$@"
}

psrc_sigpipe() {
  PSRC_EPIPE=1
}

psrc_obuffer() {
  trap psrc_sigpipe PIPE
  local out="$1"
  shift
  local sleeplen="${1:-0.1}"
  shift
  local buf
  local fd
  local stat
  exec {fd}>"$out"
  psrc_debug "obuffer: fd = $fd"
  IFS=''
  while read -rs -N 1 buf; do
    while [ -e "$out" ]; do
      PSRC_EPIPE=0
      printf '%c' "$buf" >&$fd 2>/dev/null
      stat="$?"
      psrc_debug "obuffer: wrote '$buf' ($stat) (pipe=$PSRC_EPIPE)"
      if [ $stat != 0 ] || [ $PSRC_EPIPE = 1 ]; then
        psrc_debug "obuffer: sleeping ($stat)"
        sleep $sleeplen
      else
        break
      fi
    done
  done
  trap - PIPE
}

psrc_bootstrap_slave() {
  local host="$1"
  shift
  local umask="`umask`"
  (cd "$PSRC_HOME" && \
    find . -type f -name "*.sh" | \
    env LC_ALL=C sort | \
    shar -q -Q -S -x | \
    psrc_ssh "$host" "`printf 'umask %q && mkdir -p %q && cd %q && /bin/sh' "$umask" "$PSRC_TMP" "$PSRC_TMP"`" \
  )
}

psrc_start_slave() {
  local host="$1"
  shift
  local umask="`umask`"
  if [ -e "$PSRC_CTRL/$host.out" ] || [ -e "$PSRC_CTRL/$host.ctrl" ]; then
    psrc_log "Control fifo already exists for: $host"
    return 1
  fi
  if ! mkfifo -m 0600 "$PSRC_CTRL/$host.out"; then
    psrc_log "Failed to create control fifo for: $host"
    psrc_cleanup_slave "$host"
    return 1
  fi
  if ! mkfifo -m 0600 "$PSRC_CTRL/$host.ctrl"; then
    psrc_log "Failed to create control fifo for: $host"
    psrc_cleanup_slave "$host"
    return 1
  fi
  ( \
    exec tail -q -f "$PSRC_CTRL/$host.ctrl" 2>/dev/null | \
    psrc_ssh "$host" \
      "`printf 'umask %q && exec env PATH=%q:%q:$PATH %s bash %s %q --slave' "$umask" "$PSRC_HOME" "$PSRC_TMP" "$PSRC_UNBUFFER" "$PSRC_DEBUG_X" "$PSRC_NAME"`" \
      2>"$PSRC_CTRL/$host.err" | \
      psrc_obuffer "$PSRC_CTRL/$host.out" ; \
    /bin/rm "$PSRC_CTRL/$host.out" "$PSRC_CTRL/$host.ctrl" >/dev/null 2>&1 \
  ) &
  if psrc_init_slave "$host"; then
    psrc_log "Connected to: $host"
  else
    psrc_log "Failed to connect to: $host"
    psrc_cleanup_slave "$host"
    return 1
  fi
}

psrc_cleanup_slave() {
  local host="$1"
  /bin/rm -f "$PSRC_CTRL/$host.out" "$PSRC_CTRL/$host.ctrl" >/dev/null 2>&1
  pkill -f -u $USER "tail -q -f $PSRC_CTRL/$host.ctrl" >/dev/null 2>&1
}

psrc_stop_slave() {
  local host="$1"
  psrc_send_command "$host" "${PSRC_TAG}EXIT"
  psrc_recv_return "$host" 3.0
  psrc_cleanup_slave "$host"
}

psrc_init_slave() {
  local host="$1"
  shift
  local timeout="${1:-3.0}"
  shift
  psrc_send_command "$host" "${PSRC_TAG}HELLO"
  psrc_recv_return "$host" $timeout
}

psrc_all() {
  local cmd="$1"
  shift
  local host=""
  local stat=0
  for host in `psrc_list_hosts`; do
    "$cmd" "$host" "$@"
    if [ $? != 0 ]; then
      stat=1
    fi
  done
  return $stat
}

psrc_env() {
  local host="$1"
  shift
  local var="$1"
  shift
  local val
  if [ $# = 0 ]; then
    val="${var#*=}"
    var="${var%%=*}"
  else
    val="$1"
  fi
  psrc_send_command "$host" "${PSRC_TAG}ENV" "$var" "$val"
  psrc_recv_return "$host"
}

psrc_ping() {
  local host="${1:-ALL}"
  shift
  local timeout=$1
  shift
  psrc_send_command "$host" "${PSRC_TAG}PING"
  psrc_recv_return "$host" $timeout
}

psrc_info() {
  local host="${1:-ALL}"
  shift
  local timeout=$1
  shift
  if [ x"$host" = x"ALL" ]; then
    psrc_all psrc_info $timeout
  else
    psrc_send_command "$host" "${PSRC_TAG}INFO"
    psrc_recv_return "$host" $timeout
  fi
}

psrc_run() {
  local host="$1"
  shift
  psrc_call "$host" "${PSRC_TAG}RUN" "$@"
}

psrc_usage() {
  cat - <<EOF >&2
usage: $PSRC_NAME command [args...]

commands:
  $PSRC_NAME bootstrap <hosts...>
  $PSRC_NAME connect <hosts...>
  $PSRC_NAME disconnect <hosts...>
  $PSRC_NAME run <host> <command> [ <args...> ]
  $PSRC_NAME run ALL <command> [ <args...> ]
  $PSRC_NAME env <host> <variable> <value>
  $PSRC_NAME env ALL <variable> <value>
  $PSRC_NAME stop
  $PSRC_NAME info [ <host> ]
  $PSRC_NAME ping [ <host> ]

example session:
  $PSRC_NAME connect slave-host1 slave-host2
  $PSRC_NAME run ALL do_something
  $PSRC_NAME run ALL do_something_else
  $PSRC_NAME stop
EOF
}

######################################################################

psrc_set_env

# check if running in slave mode right away
if [ x"$1" = x"--slave" ]; then
  psrc_slave
  exit 0
fi

case "$1" in
  h|help|--help|-h|-?|"")
    psrc_usage
    exit 64
    ;;
  *)
    ;;
esac

psrc_init
cmd="$1"
shift
case "$cmd" in
  a|all)
    psrc_run "ALL" "$@"
    ;;
  b|bootstrap)
    psrc_foreach psrc_bootstrap_slave "$@"
    ;;
  c|connect)
    psrc_foreach psrc_start_slave "$@"
    ;;
  d|disconnect)
    psrc_foreach psrc_stop_slave "$@"
    ;;
  e|env|environment)
    psrc_env "$@"
    ;;
  i|info)
    psrc_info "$@"
    ;;
  p|ping)
    psrc_ping "$@"
    ;;
  r|run)
    psrc_run "$@"
    ;;
  s|stop)
    psrc_stop
    ;;
  *)
    echo "Invalid command: $cmd" >&2
    psrc_usage
    exit 1
    ;;
esac
