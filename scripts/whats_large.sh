#!/bin/bash
HEADER_LINES=2
DEFAULT_LINES=10
COUNT=$(($DEFAULT_LINES+$HEADER_LINES))
if [ $# -ne 0 ]
    then
        COUNT=$(($1+$HEADER_LINES))
fi
du -ca --max-depth=1 | sort -nr | head -n "$COUNT" | tail -n+2 | awk -F' ' '{ printf("%12d %s\n",$1,$2) }'
