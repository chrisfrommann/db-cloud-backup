#!/bin/bash

. "$(dirname "$0")/backup.sh"

DB_TODAY=2023-02-01
while [ "$DB_TODAY" != $(date +\%Y-\%m-\%d) ]; do 
    if [ "$(uname)" == "Darwin" ]; then
        # macOS/BSD uses a different date format
        DB_TODAY=$(date -j -v +1d -f "%Y-%m-%d" "$DB_TODAY" +%Y-%m-%d)
    else
        DB_TODAY=$(date -I -d "$DB_TODAY + 1 day")
    fi

    perform_backups

    create_weeklies
done