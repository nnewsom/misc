#!/bin/bash
TEST_PORT=8080
TEST_PROXY="http://127.0.0.1:$TEST_PORT"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/73.0.3325.181 Safari/537.36"

TMPDIR=`mktemp -d`
DEFAULT_DIR="$TMPDIR/Default"

mkdir -p $DEFAULT_DIR
cp -r "$HOME"/scripts/Default/* $DEFAULT_DIR/

/usr/bin/chromium-browser \
    --proxy-server="$TEST_PROXY" \
    --no-first-run \
    --user-data-dir="$TMPDIR" \
    --user-agent="$UA" \
    --dns-prefetch-disable \
    --ignore-certificate-errors \
    --disable-background-networking \
    --disable-xss-auditor \
    --disable-client-side-phishing-detection \
    --disable-background-networking \
    --safebrowsing-disable-auto-update \
    --disable-sync-preferences

find "$TMPDIR" -type f -exec shred -n3 -zu {} \;
rm -rf "$TMPDIR"
