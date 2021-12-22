#!/bin/bash

set -o pipefail

main() {

  if [[ $# -gt 0 ]]; then
    local var="$1"
    case "${var}" in
      --install|-i) install;;
      --run|-r) run;;
      --kill|-k) kill_proc;;
      --watch|-w) watch;;
      --check|-c) check_proc;;
      *) echo "Do nothing!" ;;
    esac
    
    shift 1

  fi

  exit 0

}

install() {

  # install inotify-tools if not installed
  if ! type inotifywait >/dev/null 2>&1; then
    apt-get install inotify-tools
  fi

  if ! type "$HOME/inotify-wordpress" >/dev/null 2>&1; then
    cp ./inotify-wordpress.sh "$HOME/inotify-wordpress"
    chmod 755 "$HOME/inotify-wordpress"
  fi

  # add cron
  if [[ ! -f /etc/cron.d/inotify-wordpress ]]; then
    echo "* * * * * root $HOME/inotify-wordpress" | tee /etc/cron.d/inotify-wordpress
  fi

  exit 0

}

run() {

  # verify process isn't already running
  if [[ -f /var/tmp/inotify-wordpress.pid ]]; then
    local pid="$(cat /var/tmp/inotify-wordpress.pid)"
    printf "PID file /var/tmp/inotify-wordpress.pid exists! "

    if ! ps -p "${pid}" > /dev/null; then
      printf "But it appears the process ID %s isn't running so I'm deleting it..." "${pid}"
      rm /var/tmp/inotify-wordpress.pid
    else
      exit 1
    fi

    printf "\\n"

  fi

  if [[ ! -f sites.conf || ! -f excludes.conf ]]; then
    echo "Missing sites.conf or excludes.conf..."
    exit 1
  fi

  # define site folders
  local site_folders=()
  local line
  while read -r line; do
    site_folders+=("${line}")
  done < sites.conf

  # define excludes
  local regex_exclude=()
  while read -r line; do
    regex_exclude+=("${line}")
  done < excludes.conf

  # format the regex exclude list to include a pipe between iterations
  IFS='|'
  local regex_exclude_piped
  regex_exclude_piped="${regex_exclude[*]}"
  unset IFS
  
  #regex_exclude+=('.*/wp-content/temp-write-test-.*|')
  #regex_exclude+=('.*/wc-logs/.*\.log|')
  #regex_exclude+=('.*/astra/db/.*|')
  #regex_exclude+=('.*/astra-gk/var/db/.*|')
  #regex_exclude+=('.*/mailchimp-for-wp/debug-log.php|')
  #regex_exclude+=('.*\.(css|je?pg|json|xml|csv|png|docx\.?.*)')

  # run inotifywait
  IFS=
  local run_command=()
  run_command=(inotifywait -d -m -r -q -e "modify,attrib,close_write,moved_to,moved_from,move,create,delete,delete_self,unmount" -o $HOME/inotify-wordpress.log --format "%w%f %e" "${site_folders[@]}" --exclude "${regex_exclude_piped}")
  ${run_command[@]} && \
  pgrep -f "${run_command[*]}" | tee /var/tmp/inotify-wordpress.pid || \
    echo "Something went wrong..." && \
    exit 1

  exit 0

}

watch() {

  local alert=0
  local count=0
  local line

  while read -r line; do
    ((count++))
  done < "$HOME/inotify-wordpress.log"

  if [[ ${alert} -gt 0 ]]; then
    echo "sending alert..."
  fi

  exit 0

}

check_proc() {

  local pid
  pid=$(cat /var/tmp/inotify-wordpress.pid)

  if [[ -n "${pid}" ]]; then
    if ! ps -p "${pid}" > /dev/null; then
      "$HOME/inotify-wordpress" --run
    fi
  fi

  exit 0

}

kill_proc() {

  if [[ -f /var/tmp/inotify-wordpress.pid ]]; then
    local pid=$(cat /var/tmp/inotify-wordpress.pid)
    echo "Killing ${pid}..."
    kill "${pid}" && \
    rm /var/tmp/inotify-wordpress.pid
  else
    echo "No PID file exists..."
  fi

  exit 0

}

main "$@"