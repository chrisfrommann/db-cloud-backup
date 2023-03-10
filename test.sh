#!/bin/bash

. "$(dirname "$0")/backup.sh"

today=2023-02-01
while [ "$today" != `date +\%Y-\%m-\%d` ]; do 
    if [ "$(uname)" == "Darwin" ]; then
        # macOS/BSD uses a different date format
        today=$(date -j -v +1d -f "%Y-%m-%d" $today +%Y-%m-%d)
    else
        today=$(date -I -d "$today + 1 day")
    fi

    perform_backups

    create_weeklies
done