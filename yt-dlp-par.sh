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

while read -r url
do
    opts="--no-progress"

    # Spawn a background process to download the URL.
    # Keep track of each PID in a list. Spaces will be the delimiter.
    $yt_command $opts "$url" &
    echo "[$name]: PID $! started for $url"
    [ -z "${pids+x}" ] && pids="$!" || pids="$pids $!"

    pids="$(wait_for_worker $pids)"

    # Save only YouTube URLs into a list so they will be marked as played.
    # Before the first URL to be saved, the list is not initialiazed. Just
    # copy $url into to_mark. Subsequent URLs will be added to the list
    # following a newline.
    if [ -n "${cookies+x}" -a -z "${url##*youtube*}" ]
    then
        [ -z "${to_mark+x}" ] && to_mark="$url" || to_mark=$(printf "%s\n%s" "$to_mark" "$url")
    fi
done

# Mark all URLs in $to_mark as watched. Each URL in the list is on a line.
# Convert newlines to nulls and iterate through the list using xargs.
[ -n "$to_mark" ] && $yt_command --simulate --cookies "$cookies" --mark-watched $to_mark

# Don't forget to wait for any remaining downloads to complete.
#echo "[$name]: PID $$ cleaning up"
#for pid in $pids
#do
#    if wait "$pid"; then
#        echo "[$name]: PID $pid exited normally"
#    else
#        echo "[$name]: PID $pid exited with errors"
#    fi
#done 

wait
