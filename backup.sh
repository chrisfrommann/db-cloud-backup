#!/bin/bash

########################################################################
#                                                                      #
#   Script to automatically create rolling backups to cloud storage    #
#      Inspired by and heavily modified from                           #
#      https://wiki.postgresql.org/wiki/Automated_Backup_on_Linux      #
#                                                                      #
#   Author: @chrisfrommann                                             #
#                                                                      #
########################################################################

# See https://gist.github.com/mohanpedala/1e2ff5661761d3abd0385e8223e16425
set -euo pipefail

# You need to run shellcheck -x to follow links (see SC1090 and SC1091)
# shellcheck source=./_includes.sh
. "$(dirname "$0")/_includes.sh"
. "$(dirname "$0")/_cloud.sh"
. "$(dirname "$0")/_database.sh"

print_usage() {
    cat <<-EOF

    This script creates a backup of a local database to a cloud backend. It assumes:
        1) Your DB is not in the cloud (otherwise just use e.g. RDS with
           automatic backups)
        2) Your destination bucket already exists and you have permissions
           to write to it
    See README.md for more details


    usage: $(basename "$0") -c CONFIG_FILE

        where   CONFIG_FILE is a path to config file (e.g. backup.conf)
                    See backup.conf.sample

EOF
}

if [[ $# -lt 2 ]]; then
    print_usage
    exit 0
fi

while [[ $# -gt 0 ]]; do
    case "${1}" in
        -h|--help)
            print_usage
            exit 0
            ;;
        -c)
            if [ -r "$2" ]; then
                    source "$2"
                    shift 2
            else
                    ${ECHO} "Unreadable config file \"$2\"" 1>&2
                    exit 1
            fi
            ;;
        *)
            ${ECHO} "Unknown Option \"$1\"" 1>&2
            print_usage
            exit 2
            ;;
    esac
done

# Make sure we're running as the required backup user
if [ "$DB_BACKUP_USER" != "" -a "$(id -un)" != "$DB_BACKUP_USER" ]; then
	echo "${RED}This script must be run as $DB_BACKUP_USER. Exiting.${NO_COLOR}" 1>&2
	exit 1;
fi;

# Ensure the backup directory exists
mkdir -p "$DB_STAGING_DIR"

echo -e "${GEAR} Checking dependencies... "
deps=0
for name in aws parallel
do
  type $name &>/dev/null || { echo -en "\n${RED_X} $name needs to be installed.";deps=1; }
done
[[ $deps -ne 1 ]] && echo "${GREEN_GHECK} OK" || { echo -en "${RED}\nInstall the above and rerun this script${NO_COLOR}\n";exit 1; }

# Ensure DB_TYPE is one of oracle or postgres (and relevant dependencies are installed)
if [ "${DB_TYPE}" == 'postgres' ]; then
	if ! command pg_dump --version &> /dev/null; then
		echo -e "${RED}pg_dump must be installed to backup PostgreSQL${NO_COLOR}" 1>&2
		exit 1;
	fi
	echo "hello?"
elif [ "${DB_TYPE}" == 'oracle' ]; then
	if ! command expdb --version &> /dev/null; then
		echo -e "${RED}expdb must be installed to backup Oracle${NO_COLOR}" 1>&2
		exit 1;
	fi
else
    echo -e "${RED}DB_TYPE must by 'postgres' or 'oracle'${NO_COLOR}" 1>&2
	exit 1;
fi

if [[ ${DB_DAY_OF_WEEK_TO_KEEP} > ${DB_DAYS_TO_KEEP} ]]; then
	echo -e "${RED}DB_DAY_OF_WEEK_TO_KEEP > DB_DAYS_TO_KEEP, which means you'll have 
	already deleted the backup you want to retain${NO_COLOR}" 1>&2
	exit 1;
fi

# Make the date a variable so you can adjust it for test purposes
DB_TODAY=$(date +\%Y-\%m-\%d)

# Create today's backup and move it to the cloud
perform_backups

# Move today's backup to be a weekly backup if it's the 'weekly' version
create_weeklies

# Clean up old (daily) cloud backups
rm_stale_backups "${DB_CLOUD_BACKUP_PATH}" "daily" "$DB_DAYS_TO_KEEP"

# Clean up old (weekly) cloud backups
rm_stale_backups "${DB_CLOUD_BACKUP_PATH}" "weekly" $(($DB_WEEKS_TO_KEEP * 7 + 1))