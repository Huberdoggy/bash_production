#!/bin/bash

yaml_dir="/volume1/docker/compose"
plex_yaml_path="${yaml_dir}/media"
arr_yaml_path="${yaml_dir}/downloader"
mailto="huberdoggy@gmail.com"
from="Automation"
subject="Docker image updates detected"
log_file="${PWD}/docker-image-updates.txt"
today="$(date +%Y-%m-%d)"

wipe_log() {
  if [ ! -f "$log_file" ]; then
    touch "$log_file" &&
      chgrp administrators "$log_file" &&
      chmod a=,a+rX,u+w,g+w "$log_file"
  else
    cat /dev/null >"$log_file"
  fi
  printf "%b\n\n" "$today" >"$log_file"
}

send_status() {
  echo "\
To: $mailto
From: $from
Subject: $subject

$1
" | ssmtp $mailto
}

cleanup_container() {
  docker stop "$(docker container ls -q --filter "name=${1}" --filter "status=running")" &&
    echo "Removed container ID: $(docker rm -v "$_")" >>"$log_file"
}

re_up() {
  for f in "${file_arr[@]}"; do
    if [ "$f" == "media" ]; then
      yml_file="$(eval "$compose_file_plex" | awk '{print $1}')"
    elif [ "$f" == "downloader" ]; then
      yml_file="$(eval "$compose_file_arrs" | awk '{print $1}')"
    else
      continue
    fi
    grep -m 1 "$1" "$yml_file"
    if [ $? -eq 0 ]; then
      if [[ "$1" =~ (plex|jackett|transmission*) ]]; then
        # I have a deps chain in compose for these srvcs, so restart the whole chain
        docker-compose -f "$yml_file" \
          up -d >>"$log_file"
      else
        docker-compose -f "$yml_file" \
          up -d --no-deps "$1" >>"$log_file"
      fi
      break
    fi
  done
}

check_img_hashes() {
  count=0
  im_ids=("$(docker image ls | awk '{print $3}' | grep -Evi "^\<image\>$")")
  while read data; do
    repo_tag="$(docker image inspect --format "{{.RepoTags}}" "$data" |
      sed --regexp-extended 's!\[\<.*(lscr\.io|linuxserver|haugene)\>\/|:\<latest\>\]$!!g')"
    latest="docker image ls | grep -Es \"\b${repo_tag}\s+latest\b\""
    dangling="docker image ls | grep -Es \"\b${repo_tag}\b\s+<?none>?\""
    if [ "$(eval "$dangling" | wc -l)" -gt 0 ]; then
      old_hash="$(eval "$dangling" | awk '{print $3}')"
      new_hash="$(eval "$latest" | awk '{print $3}')"
      printf "%b\n\n" "\nDocker image is: ${repo_tag}\nCurrent image hash: $old_hash\n" \
        "Will attempt to stop, remove, and restart container using latest hash: $new_hash" \
        >>"$log_file"
      cleanup_container "$repo_tag" 2>>"$log_file" 1>/dev/null
      re_up "$repo_tag" 2>>"$log_file" 1>/dev/null
      printf "%b\n" "#########################################################" >>"$log_file"
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
  printf "%b\n\n" "BEGIN CONTAINER PULLS" >>"$log_file"
  file_arr+=("${@:1}")
  for f in "${file_arr[@]}"; do
    if [ "$f" == "media" ]; then
      compose_file_plex="find \"$plex_yaml_path\" -mindepth 1 -maxdepth 1 \
      -type f -name \"${f}.yml\""
      docker-compose -f "$(eval "$compose_file_plex" | awk '{print $1}')" pull >>"$log_file" 2>&1
    elif [ "$f" == "downloader" ]; then
      compose_file_arrs="find \"$arr_yaml_path\" -mindepth 1 -maxdepth 1 \
      -type f -name \"${f}.yml\""
      docker-compose -f "$(eval "$compose_file_arrs" | awk '{print $1}')" pull >>"$log_file" 2>&1
    else
      continue # Invalid path so do nothinig with it
    fi
  done
  printf "%b\n" "#########################################################" >>"$log_file"
}

if [ "$#" -lt 1 ]; then
  echo "Usage: $(basename "$0") <compose-file basename>"
  exit 1
fi

wipe_log
do_pull "$@"
check_img_hashes

if [ $? -eq 1 ]; then
  printf "\n%b\n" "Cleaning up outdated images..." >>"$log_file"
  docker image prune --filter "dangling=true" --force >>"$log_file"
  send_status "$(cat "$log_file")"
fi
