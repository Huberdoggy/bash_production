#!/bin/bash

DOCKER_BINARY_NAME="docker-compose"
YAML_DIR="/volume1/docker/compose"
PLEX_YAML_PATH="${YAML_DIR}/media"
ARR_YAML_PATH="${YAML_DIR}/downloader"
FILE_ARR=()
MAILTO="huberdoggy@gmail.com"
FROM="Automation"
SUBJECT="Routine Docker Image Checks Completed"
LOGFILE="${PWD}/logs/docker-image-updates.txt"
TODAY="$(date +%Y-%m-%d)"

check_posit_params() {
  if [ "$#" -lt 1 ]; then # mainly applicable for interactive mode
    echo "Usage: $(basename "$0") <compose-file basename/s>"
    exit 1
  fi
}

wipe_log() {
  if [ ! -f "$LOGFILE" ]; then
    touch "$LOGFILE" &&
      chgrp administrators "$LOGFILE" &&
      chmod a=,u+rw,g+rw "$LOGFILE"
  else
    cat /dev/null >"$LOGFILE"
  fi
  printf "%b\n\n" "$TODAY" >"$LOGFILE"
}

check_docker_cmd() {
  if [ "$(command -v "$DOCKER_BINARY_NAME")" -eq 1 ] >/dev/null 2>&1; then
    DOCKER_BINARY_NAME="$(echo "$DOCKER_BINARY_NAME" | sed --regexp-extended 's!\b-\b! !')" # upgrading to compose v2 gets rid of the hyphen
  fi
  printf "%b\n" "Script will run with compose command syntax \"$DOCKER_BINARY_NAME\"\n" >>"$LOGFILE"
}

do_pull() {
  {
    printf "%b\n\n" "BEGIN CONTAINER PULLS"
    FILE_ARR+=("${@:1}")
    for f in "${FILE_ARR[@]}"; do
      if [ "$f" == "media" ]; then
        COMPOSE_FILE_PLEX="find \"$PLEX_YAML_PATH\" -mindepth 1 -maxdepth 1 -type f -name \"${f}.yml\""
        "$DOCKER_BINARY_NAME" -f "$(eval "$COMPOSE_FILE_PLEX" | awk '{print $1}')" pull
      elif [ "$f" == "downloader" ]; then
        COMPOSE_FILE_ARRS="find \"$ARR_YAML_PATH\" -mindepth 1 -maxdepth 1 -type f -name \"${f}.yml\""
        "$DOCKER_BINARY_NAME" -f "$(eval "$COMPOSE_FILE_ARRS" | awk '{print $1}')" pull
      else
        continue # Invalid path so do nothinig with it
      fi
    done
    printf "%b\n" "#########################################################"
  } >>"$LOGFILE" 2>&1
}

cleanup_container() {
  docker stop "$(docker container ls -q --filter "name=${1}" --filter "status=running")" &&
    echo "Removed container ID: $(docker rm -v "$_")" >>"$LOGFILE"
}

re_up() {
  local yml_file
  for f in "${FILE_ARR[@]}"; do
    if [ "$f" == "media" ]; then
      yml_file="$(eval "$COMPOSE_FILE_PLEX" | awk '{print $1}')"
    elif [ "$f" == "downloader" ]; then
      yml_file="$(eval "$COMPOSE_FILE_ARRS" | awk '{print $1}')"
    else
      continue
    fi
    grep -qm 1 "$1" "$yml_file"
    if [ $? -eq 0 ]; then
      if [[ "$1" =~ (plex|jackett|transmission*) ]]; then
        # I have a deps chain in compose for these srvcs, so restart the whole chain
        "$DOCKER_BINARY_NAME" -f "$yml_file" up -d >>"$LOGFILE"
      else
        "$DOCKER_BINARY_NAME" -f "$yml_file" up -d --no-deps "$1" >>"$LOGFILE"
      fi
      break
    fi
  done
}

check_img_hashes() {
  local old_count=0
  local static_count=0
  local repo_tag old_hash after_pull_hash semver dangling check_static
  im_ids=("$(docker image ls | awk '{print $3}' | grep -Evi "^\<image\>$")")
  while read data; do
    repo_tag="$(docker image inspect --format "{{.RepoTags}}" "$data" |
      sed --regexp-extended 's!\[\b(lscr\.io|haugene)\b\/(linuxserver\/)?|\b:(latest|version.*|[0-9](\.[0-9]\.[0-9])?)\b\]$!!g')" # Will extract name
    semver="docker image ls | grep -E \"\b${repo_tag}\b\s+(latest|version.*|[0-9](\.[0-9]\.[0-9])?)\" "                           # Will extract version
    dangling="docker image ls | grep -E \"\b${repo_tag}\b\s+<?none>?\""
    check_static="$(eval "$semver" | awk '{print $2}')"
    if [[ "$check_static" =~ ^version.*$ ]] || [[ "$check_static" =~ [0-9](\.[0-9]\.[0-9])? ]]; then # We can skip remaining logic for specific semver images - a.k.a version-1.399.xxxxx
      printf "%b\n\n" "\nDocker image ${repo_tag} has a statically assigned version of: ${check_static}.\nNo action needed." >>"$LOGFILE"
      static_count+=1
    elif [[ ! "$repo_tag" =~ ^\[\]$ ]]; then # Addl check since it seems that pulling 'latest' replaces JSON in the old with null brackets
      if [ "$(eval "$dangling" | wc -l)" -gt 0 ]; then
        old_hash="$(eval "$dangling" | awk '{print $3}')"      # Corresponds to "Image ID" col output of 'docker image ls'
        after_pull_hash="$(eval "$semver" | awk '{print $3}')" # Same here ...
        printf "%b\n\n" "\nDocker image is: ${repo_tag}\nDangling image hash is: $old_hash\n" \
          "Will attempt to stop, remove, and restart container using latest hash: $after_pull_hash" >>"$LOGFILE"
        {
          cleanup_container "$repo_tag"
          re_up "$repo_tag"
        } 2>>"$LOGFILE" 1>/dev/null
        printf "%b\n" "#########################################################" >>"$LOGFILE"
        old_count+=1
      fi # Endif - dangling img found on current iteration
    fi   # Endif - null RepoTag JSON check
  done < <(echo "${im_ids[@]}")
  if [[ "$old_count" -ge 1 && "$static_count" -eq 0 ]] || [[ "$old_count" -ge 1 && "$static_count" -ge 1 ]]; then
    return 0 # Also run image prune before exit
  elif [[ "$old_count" -eq 0 && "$static_count" -ge 1 ]]; then
    return 5 # Don't run image prune, but still email full details
  else
    return 7 # Code for brief Gmail 'all imgs up to date and I don't currently have any static semvers on images'
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

perform_wrap_up() {
  case "$1" in

  0)
    {
      printf "\n%b\n" "Cleaning up outdated images..."
      docker image prune --filter "dangling=true" --force
    } >>"$LOGFILE"
    send_status "$(cat "$LOGFILE")"
    ;;

  5)
    printf "%b\n" "All images using 'latest' tag are still current from last script run." >>"$LOGFILE"
    send_status "$(cat "$LOGFILE")"
    ;;

  7) send_status "All Docker images are up to date on $(eval hostname)." ;;

  *) send_status "Unknown error occurred when updating containers on $(eval hostname)." ;;

  esac
}

check_posit_params "$@"
wipe_log
check_docker_cmd
do_pull "$@"
check_img_hashes
RET_CODE="$?" # Must be assigned immediately after calling check_img_hashes to store the return value
perform_wrap_up "$RET_CODE"
