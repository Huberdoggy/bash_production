#!/bin/bash

### GLOBALS ###
source_dir="/volume2/data/media/" # with trailing '/' -> so that rsync recursively syncs all contents/subdirs and skips the parent dir itself
backup_dir="/volumeUSB1/usbshare/rsync-bkps/media"
log_dir="/volumeUSB1/usbshare/rsync-bkps/rsync-logs"
today="$(date +%Y-%m-%d)"
today_log="rsync-log-${today}.log"
mailto="huberdoggy@gmail.com"
from="Automation"
subject="Rsync script status update"
time_now='date +"%Y-%m-%d %T"'
err_msg="\"${backup_dir}\" not found. ""\
Check USB mount point."

check_usb_path() {
  if [ ! -d "$backup_dir" ]; then # USB drive was ejected or something with expected mount point is wonky
    notify_err
    exit 7
  fi
}

get_last_log() {
  # The following command uses printf with the time specifier to show YYYY-MM-DD fmt & mod time, delimited by '+'. Rev sort and head to grab the newest
  local find_recent="find \"$log_dir\" -maxdepth 1 -type f -name '*.log' \
  -printf '%T+ %p\n' | sort -r | head -n1" >/dev/null 2>&1 # Dont' eval here, just construct the command
  if [ "$(eval "$find_recent" | wc -l)" -ne 1 ]; then      # Find didn't return anything
    printf "%b\n" "No previous backup logs found in the $(basename "$log_dir") directory." \
      "First one will be for: ${today}." >"${log_dir}/${today_log}"
  else
    result_find="$(eval "$find_recent")"
    # Grab basename of log and cut out non digits.
    # Then, sed only the front '-' and final dot. Finally, pipe back to date to get a friendly representation of last backup time
    printf "%b\n" "Last backup was on: $(basename "$result_find" |
      tr -d '[:alpha:]' | sed -E 's/^-+|\.$//g' | date -f - '+%A %b %d %Y')" \
      "Will do a new one today: ${today}." >"${log_dir}/${today_log}"
  fi
}

remove_old_logs() {
  local find_older="find \"$log_dir\" -maxdepth 1 -type f -name '*.log' -mtime +30"
  if [ "$(eval "$find_older" | wc -l)" -eq 0 ]; then
    echo -e "\nNo logs older than 1 month found. Skipping clean-up today...\n" \
      >>"${log_dir}/${today_log}"
  else
    eval "$find_older" -print0 | xargs -0 -I {} bash -c \
      "echo -e '\nRemoving old log {}' && rm {} " \; >>"${log_dir}/${today_log}"
  fi
}

send_status() {
  echo "\
To: $mailto
From: $from
Subject: $subject

$1
" | ssmtp $mailto
}

notify_start() {
  send_status "Rsync job began backup now $(eval "$time_now")."
}

notify_end() {
  send_status "Rsync job finished backup now $(eval "$time_now"). ""\
Rsync return code was: $?"
}

notify_err() {
  send_status "$err_msg"
}

##### BEGIN MAIN #####
check_usb_path
get_last_log
remove_old_logs
notify_start

printf "%b\n" "\n##### BEGIN RSYNC OUTPUT #####\n" >>"${log_dir}/${today_log}"

rsync -av \
  --itemize-changes \
  --delete \
  "$source_dir" "$backup_dir" >>"${log_dir}/${today_log}" 2>&1

# Since task will run as root, change perms on logfile
printf "%b\n" "\nChanging owner and perms on log file" \
  "for the reference of user $(id huberdoggy | cut -d '(' -f2 | sed -E 's/\)\s.*//g')" \
  >>"${log_dir}/${today_log}"
chown huberdoggy:administrators "${log_dir}/${today_log}" &&
  chmod a=,a+rX,u+w,g+w "${log_dir}/${today_log}"

notify_end
