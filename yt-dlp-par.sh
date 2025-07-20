#!/bin/sh

set -eu
name=$(basename "$0")
yt_command="$(command -v yt-dlp)"
max_jobs="4"
opts="--newline"
fifo_path="$(mktemp -u "/tmp/${name}_XXXXXX")"
pids=""
to_mark=""

trap 'echo "Ctrl-C caught"; for pid in $pids; do kill "$pid"; done; exit 1' INT

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

# Fifo name is calculated from SHA-1 of the URL in $1 and encoded as base32.
get_fifo_name()
{
    echo -n "$1" | sed -r 's/https?:\/\///' | sha1sum | xxd -p -r | base32
}

launch_workers()
{
    # Spawn a background process to download each URL.
    # Keep track of each PID in a list. Spaces will be the delimiter.
    for arg
    do
        fifo="$fifo_path/$(get_fifo_name "$arg")"
        (
            trap "rm -f $fifo" EXIT
            mkfifo "$fifo" || \
                {
                    echo "Failed to create FIFO for $arg" >&2
                    exit 1
                }
            while read -r line;
            do
                echo "[$arg] $line"
            done < "$fifo" &
            "$yt_command" $opts "$arg" > "$fifo" 2>&1
        ) &

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
        if [ -n "${cookies+x}" -a -z "${arg##*youtube*}" ]
        then
            if [ -z "$to_mark" ]
            then
                to_mark="$arg"
            else
                to_mark="$to_mark
$arg"
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
            break       # Terminate the loop early using 'break'
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
    # If the playlist is the YouTube Watch Later list, then cookies must
    # are required to retrieve the playlist.

    playlist_opts="--simulate --flat-playlist --print %(url)s"
    [ -z "${1##*youtube*}" -a "$(get_query_param "$1" "list")" = "WL" ] && \
        playlist_opts="$playlist_opts --cookies $cookies"

    "$yt_command" $playlist_opts "$1"

    return
}

mkdir "$fifo_path"

while read -r url
do
    # Check for playlist. If the URL is for a playlist then retrieve it.
    if get_query_param -q "$url" "list"
    then
        launch_workers $(get_playlist "$url")
    else
        launch_workers "$url"
    fi
done

# Mark all URLs in $to_mark as watched. Each URL in the list is on a line.
if [ -n "$to_mark" ]
then
    $yt_command --simulate --cookies "$cookies" --mark-watched $to_mark &
    if [ -z "$pids" ]; then pids="$!"; else pids="$pids $!"; fi
fi

# Wait on remaining jobs.
while [ -n "$pids" ]
do
    pids_to_wait_on="$(get_completed_pids $pids)" && \
        wait_on $pids_to_wait_on
    sleep 1
done

rmdir "$fifo_path"
echo done.
