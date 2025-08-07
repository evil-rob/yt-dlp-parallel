#!/bin/sh
# vim: set tabstop=2 shiftwidth=2 expandtab:

set -eu
name=$(basename "$0" | cut -d. -f1)
yt_command=$(command -v yt-dlp)
max_jobs="${1:-4}"
fifo_path=$(mktemp -u "/tmp/${name}_XXXXXX")
worker=$((max_jobs-1))
lines=$(tput lines)
columns=$(tput cols)
gauge_size=$((columns*2/3-4))
bar_location=$(tput hpa $((columns-gauge_size)))
cursor_to_eol=$(tput hpa "$columns")
bottom=$(tput cup "$lines" 0)
clear_line=$(printf "\033[2K")
pids=""
to_mark=""

trap 'SIGINT_handler' INT
SIGINT_handler()
{
  printf '\033[r%s%s\n' "$bottom" "Ctrl-C caught"
  for pid in $pids
  do
    kill "$pid"
  done
  exit 130
}

setup_terminal()
{
  printf '\n%.0s' $(seq 1 $lines)
  tput vpa "$max_jobs"
  printf "█%.0s" $(seq 1 "$columns")
  tput csr "$((max_jobs+1))" "$((lines-1))"
  tput vpa "$((max_jobs+1))"
}

# Sit in a while loop and poll each PID. For each completed PID, add to a list
# of completed PIDs and remove it from the argument list. Break out of the loop
# either if there are fewer than $max_jobs active PIDs or if there are more
# than $max_jobs completed PIDs. Print the list of completed PIDs.
get_completed_pids()
{
  completed_pids=""
  while :
  do
    new_args=""
    for arg
    do
      if ! ps -p "$arg" >/dev/null 2>&1
      then
        if [ -z "$completed_pids" ]
        then
          completed_pids="$arg"
        else
          completed_pids="$completed_pids $arg"
        fi
        continue
      fi

      if [ -z "$new_args" ]
      then
        new_args="$arg"
      else
        new_args="$new_args $arg"
      fi
    done
    
    set -- $new_args

    [ "$#" -lt "$max_jobs" ] && break
    sleep 1
  done
  [ -n "$completed_pids" ] && echo $completed_pids
  return
}

# Iterate over positional arguments and call wait
# on each one. Remove each $arg from the $pids list.
wait_on()
{
  for arg
  do
    if wait "$arg"
    then
      echo "PID $arg completed normally."
    else
      echo "PID $arg completed with errors."
    fi
    new_pids=""
    for p in $pids
    do
      [ "$arg" = "$p" ] && continue
      if [ -z "$new_pids" ]
      then
        new_pids="$p"
      else
        new_pids="$new_pids $p"
      fi
    done
    pids="$new_pids"
  done
  return 0
}

# draw_gauge - Draw a horizontal percentage gauge
# Usage: draw_gauge <percentage> <width> [filled_char] [empty_char]
# $1: percentage (0.0 to 100.0)
# $2: width in characters
# $3: filled character (default: #)
# $4: empty character (default:  )

draw_gauge()
{
  # Validate required parameters
  if [ $# -lt 2 ]; then
    echo "Usage: draw_gauge <percentage> <width> [filled_char] [empty_char]" >&2
    return 1
  fi
  
  # Get parameters with defaults
  percentage="$1"
  width="$(($2-2))" # Subtract 2 to account for the addition of [ ]
  filled_char="${3:-#}"
  empty_char="${4:- }"
  
  # Validate percentage range (0.0 to 100.0)
  # Using awk for floating point comparison since POSIX sh doesn't support it natively
  if ! echo "$percentage" | awk '{ exit !($1 >= 0 && $1 <= 100) }'; then
    echo "Error: percentage must be between 0.0 and 100.0" >&2
    return 1
  fi
  
  # Validate width is positive integer
  case "$width" in
    ''|*[!0-9]*) 
      echo "Error: width must be a positive integer" >&2
      return 1
      ;;
    *)
      if [ "$width" -le 0 ]; then
        echo "Error: width must be greater than 0" >&2
        return 1
      fi
      ;;
  esac
  
  # Calculate filled positions using awk for floating point arithmetic
  # Multiply percentage by width and divide by 100, then round to nearest integer
  filled_count=$(echo "$percentage $width" | awk '{ 
    result = ($1 * $2) / 100 + 0.5
    printf "%.0f", result
  }')
  
  # Ensure filled_count doesn't exceed width
  if [ "$filled_count" -gt "$width" ]; then
    filled_count="$width"
  fi
  
  # Calculate empty positions
  empty_count=$((width - filled_count))
  
  # Build the gauge string
  gauge=""
  
  # Add filled characters
  i=0
  while [ "$i" -lt "$filled_count" ]; do
    gauge="${gauge}${filled_char}"
    i=$((i + 1))
  done
  
  # Add empty characters
  i=0
  while [ "$i" -lt "$empty_count" ]; do
    gauge="${gauge}${empty_char}"
    i=$((i + 1))
  done
  
  # Output the gauge
  echo -n "[$gauge]"
}

# Example usage (uncomment to test):
# draw_gauge 25.5 20          # 25.5% with default characters
# draw_gauge 75.0 30 "#" " "  # 75% with # for filled and space for empty  
# draw_gauge 100.0 15 "=" "." # 100% with block characters
# draw_gauge 0.0 10           # 0% gauge

# Condense a long string to fit a fixed column
# width and not overflow into the progress gauge.
condense_string()
{
  max_len=$((columns-gauge_size-1))
  start_chars=$((max_len/2))
  string_len="${#1}"
  if [ "$string_len" -gt "$max_len" ]
  then
    end_chars=$((max_len - start_chars - 1))
    end_start=$((string_len - end_chars + 1))
    start_part=$(printf '%s' "$1" | cut -c1-"$start_chars")
    end_part=$(printf '%s' "$1" | cut -c"$end_start"-"$string_len")
    echo "$start_part…$end_part"
  else
    echo "$1"
  fi
}

handle_preproc_msg()
{
  #echo "${status_line}${bar_location}[$(((gauge_size-16)/2))C Pre-pcocessing ${bottom}[$url]${*}"
  echo "[$url] $*"
}

handle_download_msg()
{
  if [ "$2" = "Destination:" ]
  then
    filename=$(condense_string $(basename "$3"))
    echo -n "${status_line}${clear_line}${filename}${bottom}"
  elif [ "$2" = "100%" ]
  then
    echo -n "${status_line}${bar_location}[$(((gauge_size-11)/2))C Completed ${bottom}"
  else
    progress=$(draw_gauge "${2%\%}" "$gauge_size")
    echo -n "${status_line}${bar_location}${progress}${bottom}"
  fi
}

handle_postproc_msg()
{
  #echo "${status_line}${bar_location}[$(((gauge_size-17)/2))C Post-pcocessing ${bottom}[$url]${*}"
  echo "[$url] $*"
}

# Setup the fifo for status messages and initiate the download.
download()
{
  trap '[ -p "$fifo" ] && rm -f "$fifo"' EXIT
  trap 'echo "[$url] SIGTERM received."; kill $reader_pid $yt_pid; exit 1' TERM
  
  url="$1"
  status_line="$2"
  fifo="$3"

  mkfifo "$fifo" || \
    {
      echo "Failed to create FIFO for $url" >&2
      exit 1
    }
  echo -n "${status_line}${clear_line}${url}${bar_location}${empty_gauge}${bottom}"
  while read -r line
  do
    case "$line" in
      \[youtube\]*|\[info\]*|\[lbry\]*)
        handle_preproc_msg $line
        ;;
      \[download\]*)
        handle_download_msg $line
        ;;
      \[ThumbnailsConvertor\]*|\[Merger\]*|\[Metadata\])
        handle_postproc_msg $line
        ;;
      *)
        echo "[$url] $line"
        ;;
    esac
  done < "$fifo" &
  reader_pid=$!
  "$yt_command" $opts "$url" > "$fifo" 2>&1 &
  yt_pid=$!
  wait
}

launch_workers()
{
  opts="--ignore-config
--format-sort height:720,codec:h264:mp4a
--newline
--paths $HOME/Videos/yt-dlp
--output %(title)s.%(ext)s
--restrict-filenames
--no-mtime
--embed-metadata
--embed-thumbnail"
  urls=""
  # Parse args for options to pass to yt-dlp.
 
  while [ $# -gt 0 ]
  do
    case "$1" in
      http://*|https://*)
        if [ -z "$urls" ]
        then
          urls="$1"
        else
          urls="$urls $1"
        fi
        ;;
      -*)
        opts="$opts $1"
        # Check if an argument follows this option.
        # It's an argument if it's not a URL.
        arg="${2:-x}"
        if [ "$arg" = "${arg#http}" ]
        then
          # Not a URL.
          opts="$opts $arg"
          # We need an extra shift to parse the argument.
          shift
        fi
        ;;
      *)
        # Neither an option nor a URL.
        echo "[launch_workers] Invalid parameter: \"$1\"" >&2
        ;;
    esac
    shift
  done

  empty_gauge=$(draw_gauge 0 "$gauge_size")

  # Spawn a background process to download each URL.
  # Keep track of each PID in a list. Spaces will be the delimiter.
  for url in $urls
  do
    # Fifo name is calculated from SHA-1 of the URL in $1 and encoded as base32.
    fifo="$fifo_path/$(echo -n "$url" | sed -r 's/https?:\/\///' | sha1sum | xxd -p -r | base32)"
    
    worker=$(( (worker+1) % max_jobs ))
    (download "$url" $(tput vpa "$worker") "$fifo") &

    if [ -z "$pids" ]
    then
      pids="$!"
    else
      pids="$pids $!"
    fi

    # Save only YouTube URLs into a list so they will be marked as played.
    # Before the first URL to be saved, the list is not initialiazed. Just
    # copy $url into to_mark. Subsequent URLs will be added to the list
    # following a newline.
    if [ -n "${cookies+x}" -a -z "${url##*youtube*}" ]
    then
      if [ -z "$to_mark" ]
      then
        to_mark="$url"
      else
        to_mark="$to_mark
$url"
      fi
    fi

    # get_completed_pids() will return false if there are no completed PIDs
    pids_to_wait_on="$(get_completed_pids $pids)" && \
      wait_on $pids_to_wait_on
  done
  return 0
}

get_query_param()
{
  if [ "$1" = "-q" ]
  then
    quiet=1
    shift
  else
    quiet=0
  fi

  # $1 - URL
  # $2 - key

  found_key=0

  # Save the current IFS
  old_IFS="$IFS"

  # --- Extract the query string safely using [?] for literal '?' ---
  # This removes the longest prefix ending with a literal '?'
  query_string="${1##*[?]}"

  # Check if a '?' was actually found (i.e., query_string is different from original url)
  # If query_string is same as url, no '?' was found.
  # If url ended with '?', query_string will be empty.
  [ "$query_string" = "$1" ] || [ -z "$query_string" ] && return 1

  # --- Process the query string ---
  IFS='&' # Set IFS to '&' for splitting parameters
  for param in $query_string
  do
    # --- Extract key and value using parameter expansion ---
    key="${param%=*}"   # Get everything before the last '='
    value="${param#*=}" # Get everything after the first '='

    # Handle cases where there might not be an '=' (e.g., "key_only")
    if [ "${key}" = "${param}" ]
    then # If no '=' was found (param_key equals original param)
      # Check if param_value is also equal to param (means no '=' found at all)
      if [ "${value}" = "${param}" ] && [ -n "$param" ]
      then # And it's not an empty string
        value="" # It's a key-only parameter, so value is empty
      fi
    fi

    # --- Basic URL Decoding (still the same limitations as before) ---
    # Decode + and %20 to space
    key=$(echo "$key" | sed 's/+/ /g; s/%20/ /g')
    value=$(echo "$value" | sed 's/+/ /g; s/%20/ /g')

    if [ "$key" = "$2" ]
    then
      [ "$quiet" = "1" ] || echo "$value"
      found_key=1 # Set flag to indicate success
      break     # Terminate the loop early using 'break'
    fi
  done

  # Restore original IFS before function exit
  IFS="$old_IFS"

  # --- Return the negated flag's logical value as exit status ---
  # If found_key is 0 (not found), [ "$found_key" -eq 0 ] is true (exit 0).
  # '!' negates this to false (exit 1). Correct for "not found".
  # If found_key is 1 (found), [ "$found_key" -eq 0 ] is false (exit 1).
  # '!' negates this to true (exit 0). Correct for "found".
  ! [ "$found_key" -eq 0 ]
  return # Return the exit status of the previous command
}

get_playlist()
{
  # $1 - URL
  # If the playlist is the YouTube Watch Later list, then cookies
  # are required to retrieve the playlist.

  playlist_opts="--skip-download --ignore-config --flat-playlist --print %(url)s"
  [ -z "${1##*youtube*}" -a "$(get_query_param "$1" "list")" = "WL" ] && \
    {
      [ -n "${cookies:+x}" ] || \
        {
          echo "[get_playlist] Error: cookies required for $1" >&2
          return 1
        }
      playlist_opts="$playlist_opts --cookies $cookies"
    }

  "$yt_command" $playlist_opts "$1"

  return
}

trap 'clean_up' EXIT
clean_up()
{
  echo "[$name] Cleaning up."
  while [ -d "$fifo_path" ] && ! rmdir "$fifo_path" 2>/dev/null
  do
    echo "[clean_up] Failed to remove $fifo_path" >&2
    echo "[clean_up] Retrying." >&2
    sleep 1
  done
  echo "[$name] Done."
}

setup_terminal

mkdir "$fifo_path"

while read -r url
do
  # Check for playlist. If the URL is for a playlist then retrieve it.
  if get_query_param -q "$url" "list"
  then
    playlist="$(get_playlist "$url")" && \
      launch_workers $playlist
  else
    launch_workers "$url" 
  fi
done

# Mark all URLs in $to_mark as watched. Each URL in the list is on a line.
[ -n "$to_mark" ] && \
  $yt_command --skip-download --ignore-config --cookies "$cookies" --mark-watched $to_mark &

# Wait on remaining jobs.
while [ -n "$pids" ]
do
  pids_to_wait_on="$(get_completed_pids $pids)" && \
    wait_on $pids_to_wait_on
  sleep 1
done

printf "\033[r$bottom"

# Wait for mark watched
wait
