#!/bin/bash
# Note. This file needs to be updated on the server manually.

export tmptree=$(mktemp -d)
# Prevent tput from throwing an error by ensuring that $TERM is always set
if [[ -z "$TERM" ]]; then
    TERM=dumb
fi
export TERM

# Only push those templates that have changed.
push_all=false

while read -r oldrev newrev refname; do
  git archive "$newrev" | tar x -C "$tmptree"

  # for a new branch oldrev is 0{40}, set oldrev to the commit where we branched off the parent
  if [[ $oldrev == "0000000000000000000000000000000000000000" ]]; then
    oldrev=$(git rev-list --boundary $newrev --not --all | sed -n 's/^-//p')
  fi

  # Get a list of files that changed.
  files_list=''
  if [[ "x$oldrev" == 'x' ]]; then
    if [[ $CHECK_INITIAL_COMMIT != "disabled" ]] ; then
      files_list=$(git ls-tree --full-tree -r HEAD --name-only)
    else
      echo "Skipping file checks this is the initial commit..."
    fi
  else
    files_list=$(git diff --name-only "$oldrev" "$newrev" --diff-filter=ACM)
  fi

  # Push all templates if clusters have changed.
  if [[ " ${files_list[@]} " =~ " clusters.txt " ]]; then
    echo "Cluster changed pushing to all clusters."
    push_all=true
  fi
  if $push_all; then
    while read cluster; do
      for template in $(ls $tmptree/templates); do
        echo "Uploading template ${template} to cluster ${cluster}."
        curl -XPUT -Ss ${cluster}/_template/$(basename -s .json $template)?pretty -H 'Content-Type: application/json' --upload-file ${tmptree}/templates/${template}
      done
    done <$tmptree/clusters.txt
  else
    # Only push changed templates.
    for changedfile in $files_list; do
      if [[ $(echo "$changedfile" | grep -q 'templates/.*.json$'; echo $?) -eq 0 ]]; then
        template=$(basename $changedfile)
        while read cluster; do
          echo "Uploading template ${template} to cluster ${cluster}."
          curl -XPUT -Ss ${cluster}/_template/$(basename -s .json $template)?pretty -H 'Content-Type: application/json' --upload-file ${tmptree}/templates/${template}
        done <$tmptree/clusters.txt
      fi
    done
  fi
done
rm -rf "$tmptree"
