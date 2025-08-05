#!/bin/sh
# vim: set tabstop=2 shiftwidth=2 expandtab:

set -eu

while [ $# -gt 0 ]
do
  case "$1" in
    --format-sort|--paths|--output)
      shift
      ;;
    -*)
      ;;
    *)
      if [ -z "${files:+x}" ]
      then
        files="$1"
      else
        files="$files $1"
      fi
  esac
  shift
done

[ -z "${files:+x}" ] && {
  echo "No files given on command line." >&2
  exit 1
}

for file in $files
do
  [ -f "$file" ] || {
    echo "$file: File not found." >&2
    continue
  }

  while read -r line
  do
    echo "$line"
    [ "${line#*: }" = "Downloading webpage" -o "${line#\[Merger\] }" != "$line" ] && { sleep 5; continue; }
    t=$(($(od -An -N4 -t u4 /dev/random)%3))
    case "$t" in
      1) sleep 0.100 ;;
      2) sleep 0.050 ;;
      3) sleep 0.025 ;;
    esac
  done < "$file"
done
