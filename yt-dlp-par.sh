#!/bin/sh

name=$(basename "$0")
#yt_command="/usr/bin/yt-dlp"
yt_command="$(which yt-dlp)"
max_jobs="4"

trap 'echo "Ctrl-C caught"; killall yt-dlp; exit 1' SIGINT

wait_for_worker()
{
    # Sit in the while loop when there are $max_jobs PIDs running. Keep
    # polling the PIDs list and wait on each PID that terminates. Use kill -0
    # to check if a PID has terminated. After waiting on a PID, remove it from
    # the PIDs list.
    while [ "$#" -ge "$max_jobs" ]
    do
        # Poll each PID
        for pid in "$@"
        do
            # Check if PID has terminated
            if ! kill -0 "$pid" 2>/dev/null
            then 
                # Wait on the PID that terminated
                wait "$pid"

                # Remove PID from the PIDs list by iterating through the old
                # list and skipping over the one that terminated.
                new_pids=""
                for p in "$@"
                do
                    if [ "$p" != "$pid" ]
                    then
                        if [ -z "$new_pids" ]
                        then
                            new_pids="$p"
                        else
                            new_pids="$new_pids $p"
                        fi
                    fi
                done
                set -- $new_pids
            fi
        done
        sleep 1
    done

    # Print current PIDs list.
    echo "$@"
    return 0
}

launch_workers()
{
    # Spawn a background process to download each URL.
    # Keep track of each PID in a list. Spaces will be the delimiter.
    for u in "$@"
    do
        $yt_command $opts "$u" &
        [ -z "${pids+x}" ] && pids="$!" || pids="$pids $!"

        # Save only YouTube URLs into a list so they will be marked as played.
        # Before the first URL to be saved, the list is not initialiazed. Just
        # copy $url into to_mark. Subsequent URLs will be added to the list
        # following a newline.
        if [ -n "${cookies+x}" -a -z "${u##*youtube*}" ]
        then
            [ -z "${to_mark+x}" ] && to_mark="$u" || to_mark=$(printf "%s\n%s" "$to_mark" "$u")
        fi

        pids="$(wait_for_worker $pids)"
    done
    return 0
}

get_query_param()
{
    if [ "$1" = "-q" ]
    then
        quiet=1
        shift
    fi

    # $1 - URL
    # $2 - key

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
        # Decode + to space
        key="${key//+/ }"
        value="${value//+/ }"

        # Decode %20 to space
        key="${key//%20/ }"
        value="${value//%20/ }"

        if [ "$key" = "$2" ]
        then
            [ "$quiet" = "1" ] || echo "$value"
            found_key=1 # Set flag to indicate success
            break       # Terminate the loop early using 'break'
        fi
    done

    # Restore original IFS before function exit
    IFS="$IFS_backup"

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

    old_opts="$opts"
    opts="--simulate --flat-playlist --print %(url)s"
    [ -z "${1##*youtube*}" -a "$(get_query_param "$1" "list")" = "WL" ] && \
        opts="$opts --cookies $cookies"

    $yt_command $opts "$1"
    ret="$?"

    opts="$old_opts"
    return "$ret"
}

while read -r url
do
    opts="--no-progress"

    # Check for playlist. If the URL is for a playlist then retrieve it.
    if get_query_param -q "$url" "list"
    then
        launch_workers $(get_playlist "$url")
    else
        launch_workers "$url"
    fi
done

# Mark all URLs in $to_mark as watched. Each URL in the list is on a line.
# Convert newlines to nulls and iterate through the list using xargs.
[ -n "$to_mark" ] && $yt_command --simulate --cookies "$cookies" --mark-watched $to_mark

wait
