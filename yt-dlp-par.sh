#!/bin/sh

trap 'echo "Ctrl-C caught"; killall yt-dlp; exit 1' SIGINT
yt_command=$(command -v /usr/bin/yt-dlp)

#cookies="$HOME/.cache/cookies.txt"
max_workers=5
workers=0

main_pid=$(cut -d' ' -f4 < /proc/self/stat)
echo "<<PID $main_pid started>> [Main Process]"
while [ $# -gt 0 ]
do
    url="$1"
    opts="--no-progress"

    # Save only YouTube URLs into a list so they will be marked as played.
    # Before the first URL to be saved, the list is not initialiazed. Just
    # copy $url into to_mark. Subsequent URLs will be added to the list
    # following a newline.
    if [ -v "cookies" -a -z "${url##*youtube*}" ]
    then
        [ -z "${to_mark+x}" ] && to_mark="$url" || to_mark=$(printf "%s\n%s" "$to_mark" "$url")
    fi

    # Spawn a background process to download the URL. Increment workers
    # variable. If $workers is greater than $max_workers, wait for one of the
    # child processes to finish and then decrement workers.
    (pid=$(cut -d' ' -f4 < /proc/self/stat) && echo "<<PID $pid started>>" && \
        $yt_command $opts "$url" && echo "<<PID $pid completed>>") &
    shift
    workers=$((workers + 1))
    if [ $workers -gt $max_workers ]
    then
        wait -n
        workers=$((workers - 1))
    fi
    sleep 1
done

# Mark all URLs in $to_mark as watched. Each URL in the list is on a line.
# Convert newlines to nulls and iterate through the list using xargs.
[ -n "$to_mark" ] && \
    echo -n "$to_mark" | tr '\n' '\0' | \
    xargs -0 $yt_command --simulate --cookies "$cookies" --mark-watched

# Don't forget to wait for any remaining downloads to complete.
echo "<<PID $main_pid completed>> [Main Process]"
wait
