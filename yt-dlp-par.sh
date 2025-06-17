#!/bin/sh

yt_command="/usr/bin/yt-dlp"

trap 'echo "Ctrl-C caught"; killall yt-dlp; exit 1' SIGINT

echo "<<PID $$ started>> [Main Process]"

while [ $# -gt 0 ]
do
    url="$1"
    opts="--no-progress"

    # Spawn a background process to download the URL.
    # Keep track of each PID in a list. Spaces will be the delimiter.
    $yt_command $opts "$url" &
    echo "<<PID $! started>>"
    [ -z "${pids+x}" ] && pids="$!" || pids="$pids $!"

    # Save only YouTube URLs into a list so they will be marked as played.
    # Before the first URL to be saved, the list is not initialiazed. Just
    # copy $url into to_mark. Subsequent URLs will be added to the list
    # following a newline.
    if [ -n "${cookies+x}" -a -z "${url##*youtube*}" ]
    then
        [ -z "${to_mark+x}" ] && to_mark="$url" || to_mark=$(printf "%s\n%s" "$to_mark" "$url")
    fi

    # Next argument will have the next link.
    shift
    sleep 1
done

# Mark all URLs in $to_mark as watched. Each URL in the list is on a line.
# Convert newlines to nulls and iterate through the list using xargs.
[ -n "$to_mark" ] && \
    echo -n "$to_mark" | tr '\n' '\0' | \
    xargs -0 $yt_command --simulate --cookies "$cookies" --mark-watched

# Don't forget to wait for any remaining downloads to complete.
echo "<<PID $$ cleaning up>> [Main Process]"
for pid in $pids
do
    if wait "$pid"; then
        echo "<<PID $pid exited normally>>"
    else
        echo "<<PID $pid exited with errors>>"
    fi
done
