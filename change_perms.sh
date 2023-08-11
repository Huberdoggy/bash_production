#!/bin/bash

LOG_ROOT="${PWD}/logs"
DATESTR="$(date +'%m/%d/%Y %r')"
LOGFILE="${LOG_ROOT}/change_perms_log.txt"
MAILTO="huberdoggy@gmail.com"
FROM="Automation"
SUBJECT="Routine Permission Check Report from NASBOX"

check_posit_params() {
  if [ "$#" -lt 1 ]; then
    echo "Usage => $(basename "$0") <root path/s to recursively check/fix permissions>"
    exit 1
  fi
}

check_create_log_file() {
  if [ ! -d "$LOG_ROOT" ]; then
    mkdir "$LOG_ROOT" &&
      printf "%b\n" "Creating new directory '$(basename "$LOG_ROOT")' to hold" \
        "future logs for $(basename "$0")...\n\n"
  fi

  if [ ! -f "$LOGFILE" ]; then
    touch "$LOGFILE" &&
      chgrp administrators "$LOGFILE" &&
      chmod a=,u+rw,g+rw "$LOGFILE"
  else
    cat /dev/null >"$LOGFILE"
  fi
  printf "%b\n\n" "$DATESTR" >"$LOGFILE"
}

check_exist() {
  if [ "$(id "$1")" ]; then
    grep -Eq "^${2}:" "/etc/group"
    if [ "$?" -eq 0 ]; then
      return 0 # Valid user AND valid group
    else
      return 99 # Valid user but NOT valid group
    fi
  else
    return 98 # Invalid user
  fi
}

get_user_group() {
  read -t 10 -rp "Enter the user and group of the person who will own the files [medialord] [users]"$'\n> ' U_NAME U_GRP
  U_NAME="${U_NAME:-medialord}"
  U_GRP="${U_GRP:-users}"
  check_exist "$U_NAME" "$U_GRP" >/dev/null 2>&1 # Also silence output from stderr 1.
  # Down in main, since I explicitly match custom return codes in 'case' -> 0, 98, or 99
}

check_new_media() {
  if [[ -n "$1" && -n "$2" && -n "$3" ]]; then
    local dir_array+=("${@:3}") # all posit params from 3 onward (a.k.a, the dirs user passed as cmd args)
    local len=${#dir_array[@]}
    for ((i = 0; i < len; i++)); do
      local root_find_dir="${dir_array[$i]}"
      if [ -d "$root_find_dir" ]; then
        local find_cmd="find \"$root_find_dir\" -mindepth 1 -perm -o=w -print -quit"
        case "$(eval "$find_cmd")" in
        '') printf "%b\n" "All files and directories under '$root_find_dir' have correct umask of 002\n" \
          "Nothing to do." >>"$LOGFILE" ;; # Null output of 'find'

        *)
          local username="$1"
          local grp_name="$2"
          printf "%b\n" "QUEUED FOR FIX\n--------------\n" >>"$LOGFILE"
          find "${root_find_dir}" -mindepth 1 -perm -o=w -exec sh -c 'for item do \
          printf "%b\n" "$item has write perms set for OTHERS\n" \
          "Will ensure umask is set to 002...\n"; \
          printf "%b\n" "Chowning user: '"$username"' and group: '"$grp_name"'...\n"; \
          chown '"${username}:${grp_name}"' "$item" && chmod a=,a+rX,u+w,g+w "$item"; \
          [ -d "$item" ] && ls -ld "$item" || ls -l "$item"; \
          printf "%b\n" "------------------------------------------------------------------------------------------------------\n"; \
          done' find-sh {} \; >>"$LOGFILE"
          ;;
        esac
      else
        printf "%b\n" "\nERROR! User supplied directory:\n" "${dir_array[$i]}" \
          "\nCheck validity and/or existence of the above.\n\n" >>"$LOGFILE"
      fi
    done
  else
    exit 1
  fi
}

send_status() {
  echo "\
To: $MAILTO
From: $FROM
Subject: $SUBJECT

$1
" | ssmtp $MAILTO
}

check_posit_params "$@"
check_create_log_file
get_user_group
case "$?" in

99)
  printf "%b\n" "No group \"$U_GRP\" found on $(hostname)\n" >>"$LOGFILE"
  exit 1
  ;;

98)
  printf "%b\n" "No user \"$U_NAME\" found on $(hostname)\n" >>"$LOGFILE"
  exit 1
  ;;

0)
  printf "%b\n" "User \"$U_NAME\" and group \"$U_GRP\" found on $(hostname)\n" >>"$LOGFILE"
  check_new_media "$U_NAME" "$U_GRP" "$@"
  send_status "$(cat "$LOGFILE")"
  # Plan to run as cron job using user/group default params (which exist on NAS), so shouldn't ever hit the above 2 cases
  # Email should always be sent. Otherwise, just cat LOGFILE from the local path
  ;;

esac
