#!/bin/bash

# regenerate cscope for c projects from current directory
IFS=$'\n'
SRC_PATH="`pwd`"

rm -v cscope.*
find -L "$SRC_PATH" -type f \
    -iname "*.cc" \
    -o -iname "*.c" \
    -o -iname "*.cxx" \
    -o -iname "*.cpp" \
    -o -iname "*.h" \
    2>/dev/null | sed 's/^/"/;s/$"/' > cscope.files

cscope -b -q -k
