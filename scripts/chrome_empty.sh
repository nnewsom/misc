#!/bin/bash
UA="Mozilla/5.0 (Windows NT 6.1; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/73.0.3683.75 Safari/537.36"
TMPDIR=`mktemp -d`
DEFAULTDIR="$TMPDIR/Default"
BROWSER="/usr/bin/chromium-browser"

mkdir -p "$DEFAULTDIR"
cp -rv "$HOME"/scripts/Default/* "$DEFAULTDIR"/

"$BROWSER" --no-first-run --user-data-dir="$TMPDIR" --user-agent="$UA"

find "$TMPDIR" -type f -exec shred -n3 -zu {} \;
rm -rf "$TMPDIR"
