#!/bin/bash

yaml_dir="/volume1/docker/compose"
plex_yaml_path="${yaml_dir}/media"
arr_yaml_path="${yaml_dir}/downloader"
mailto="huberdoggy@gmail.com"
from="Automation"
subject="Docker image updates detected"
log_file="${PWD}/docker-image-updates.txt"
today="$(date +%Y-%m-%d)"

send_status() {
  echo "\
To: $mailto
From: $from
Subject: $subject

$1
" | ssmtp $mailto
}

check_img_hashes() {
  if [ ! -f "$log_file" ]; then
    touch "$log_file" &&
      chgrp administrators "$log_file" &&
      chmod a=,a+rX,u+w,g+w "$log_file"
  else
    cat /dev/null >"$log_file"
  fi
  printf "%b\n\n" "$today" >"$log_file"
  count=0
  im_ids=("$(docker image ls | awk '{print $3}' | grep -Evi "^\<image\>$")")
  while read data; do
    repo_tag="$(docker image inspect --format "{{.RepoTags}}" "$data" |
      sed --regexp-extended 's!\[\<.*(lscr\.io|linuxserver|haugene)\>\/|:\<latest\>\]$!!g')"
    latest="docker image ls | grep -E \"\<${repo_tag}\s+latest\>\""
    dangling="docker image ls | grep -E \"\<${repo_tag}\s+.?none.?\>\""
    if [ "$(eval "$dangling" | wc -l)" -gt 0 ]; then
      old_hash="$(eval "$dangling" | awk '{print $3}')"
      new_hash="$(eval "$latest" | awk '{print $3}')"
      printf "%b\n\n" "Docker image is: ${repo_tag}\nRunning Container hash: $old_hash\n" \
        "Latest hash is: $new_hash" \
        "#########################################################" >>"$log_file"
      count+=1
    else
      continue
    fi
  done < <(echo "${im_ids[@]}")
  if [ "$count" -ge 1 ]; then
    return 1
  else
    return 7
  fi
}

do_pull() {
  if [ "$#" -lt 1 ]; then
    echo "Usage: $(basename "$0") <compose-file basename>"
    exit 1
  else
    file_arr+=("${@:1}")
    for f in "${file_arr[@]}"; do
      if [ "$f" == "media" ]; then
        compose_file="find \"$plex_yaml_path\" -mindepth 1 -maxdepth 1 \
      -type f -name \"${f}.yml\""
        docker-compose -f "$(eval "$compose_file" | awk '{print $1}')" up -d
      elif [ "$f" == "downloader" ]; then
        compose_file="find \"$arr_yaml_path\" -mindepth 1 -maxdepth 1 \
      -type f -name \"${f}.yml\""
        docker-compose -f "$(eval "$compose_file" | awk '{print $1}')" up -d
      else
        continue # Invalid path so do nothing with it
      fi
    done
  fi
}

do_pull "$@"
check_img_hashes
if [ $? -eq 1 ]; then
  send_status "$(cat "$log_file")"
fi
