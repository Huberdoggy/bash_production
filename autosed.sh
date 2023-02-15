#!/usr/bin/env bash

yaml_file=main.yml
v_arr+="${@:1}"

if [ "$1" == "--undo-all" ]; then
  sed -i "s/^#    - import_tasks: V-/    - import_tasks: V-/g" "$yaml_file"
  echo "Successfully reverted everything!"
elif [[ "$1" =~ [-]{1,2}(h|help) ]]; then
  echo -e "Usage: $(basename "$0") <VID/s>.\nInitially, script will comment out all VID's.\nYour supplied args will be stored, to un-comment relevant VID's for testing.\n"
  echo "Run with '--undo-all' and no VIDs to uncomment entire file."
  exit 1
else # Default to commenting out the entire file for starters
  sed -i "s/^    - import_tasks: V-/#    - import_tasks: V-/g" "$yaml_file"
fi

echo -e "Would you like to uncomment your specified tests?[S]\nOr leave it alone?[N]"

read response

case $response in

S | s)
  if [ -z "$v_arr" ]; then
    echo "Ran script with no args. Nothing to do."
  else
    for vid in $v_arr; do
      if [[ $vid =~ [-]{2}[a-z]+ ]]; then
        echo "Nothing to do. Arg $vid was specified." # Since --undo-all or --comment-all won't make this part applicable
      else
        echo "Un-commenting test for ${vid}"
        sed -i "s/^#    - import_tasks: ${vid}/    - import_tasks: ${vid}/g" "$yaml_file"
      fi
    done
  fi
  ;;

N | n)
  echo "Okay. Leaving everything as is."
  ;;

*)
  exit 1
  ;;
esac
