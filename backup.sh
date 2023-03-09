#!/bin/bash

########################################################################
#                                                                      #
#   Script to automatically create rolling backups to cloud storage    #
#      Inspired and heavily modified from                              #
#      https://wiki.postgresql.org/wiki/Automated_Backup_on_Linux      #
#                                                                      #
#   Author: @chrisfrommann                                             #
#                                                                      #
########################################################################

set -euo pipefail

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
        # -d)
	    #     shift
	    #     if test $# -gt 0; then
		#         db_type="${1}"
	    #     else
		#         echo "No DB type specified"
		#         exit 1
	    #     fi
	    #     shift
	    #     ;;
        *)
            ${ECHO} "Unknown Option \"$1\"" 1>&2
            print_usage
            exit 2
            ;;
    esac
done

# Make sure we're running as the required backup user
if [ "$DB_BACKUP_USER" != "" -a "$(id -un)" != "$DB_BACKUP_USER" ]; then
	echo "This script must be run as $DB_BACKUP_USER. Exiting." 1>&2
	exit 1;
fi;

# Ensure the backup directory exists
mkdir -p $DB_BACKUP_DIR

# Ensure DB_TYPE is one of oracle or postgres
if [ "{$DB_TYPE}" != 'postgres' ] && [ "${DB_TYPE}" != 'oracle' ]; then
    echo "DB_TYPE must by 'postgres' or 'oracle'" 1>&2
	exit 1;
fi

###########################
#### START THE BACKUPS ####
###########################

function perform_backups() {
	suffix=$1
	full_db_backup_dir=$DB_BACKUP_DIR"`date +\%Y-\%m-\%d`$suffix/"

	echo "Making backup directory in $full_db_backup_dir"

	if ! mkdir -p $full_db_backup_dir; then
		echo "Cannot create backup directory in $full_db_backup_dir. Go and fix it!" 1>&2
		exit 1;
	fi;

	if [ "${DB_TYPE}" = "oracle" ]; then

		echo -e "\n\nPerforming full backups"
		echo -e "--------------------------------------------\n"

		# TODO
		
	elif [ "${DB_TYPE}" = "postgresql" ]; then
	
		#######################
		### GLOBALS BACKUPS ###
		#######################

		echo -e "\n\nPerforming globals backup"
		echo -e "--------------------------------------------\n"

		if [ $DB_ENABLE_GLOBALS_BACKUPS = "yes" ]
		then
				echo "Globals backup"

				set -o pipefail
				if ! pg_dumpall -g -h "$DB_HOSTNAME" -U "$DB_USERNAME" | gzip > $full_db_backup_dir"globals".sql.gz.in_progress; then
						echo "[!!ERROR!!] Failed to produce globals backup" 1>&2
				else
						mv $full_db_backup_dir"globals".sql.gz.in_progress $full_db_backup_dir"globals".sql.gz
				fi
				set +o pipefail
		else
			echo "None"
		fi
		
		
		###########################
		###### FULL BACKUPS #######
		###########################

		full_backup_query="select datname from pg_database where not datistemplate and datallowconn order by datname;"

		echo -e "\n\nPerforming full backups"
		echo -e "--------------------------------------------\n"

		for database in `psql -h "$DB_HOSTNAME" -U "$DB_USERNAME" -At -c "$full_backup_query" postgres`
		do
			if [ $DB_ENABLE_PLAIN_BACKUPS = "yes" ]
			then
				echo "Plain backup of $database"
		
				set -o pipefail
				if ! pg_dump -Fp -h "$DB_HOSTNAME" -U "$DB_USERNAME" "$database" | gzip > $full_db_backup_dir"$database".sql.gz.in_progress; then
					echo "[!!ERROR!!] Failed to produce plain backup database $database" 1>&2
				else
					mv $full_db_backup_dir"$database".sql.gz.in_progress $full_db_backup_dir"$database".sql.gz
				fi
				set +o pipefail
							
			fi

			if [ $DB_ENABLE_CUSTOM_BACKUPS = "yes" ]
			then
				echo "Custom backup of $database"
		
				if ! pg_dump -Fc -h "$DB_HOSTNAME" -U "$DB_USERNAME" "$database" -f $full_db_backup_dir"$database".custom.in_progress; then
					echo "[!!ERROR!!] Failed to produce custom backup database $database"
				else
					mv $full_db_backup_dir"$database".custom.in_progress $full_db_backup_dir"$database".custom
				fi
			fi

		done
	fi

	echo -e "\nAll database backups complete!"
}

# MONTHLY BACKUPS

day_of_month=`date +%d`

if [ $day_of_month -eq 1 ];
then
	# Delete all expired monthly directories
	find $DB_BACKUP_DIR -maxdepth 1 -name "*-monthly" -exec rm -rf '{}' ';'
	        	
	perform_backups "-monthly"
	
	exit 0;
fi

# WEEKLY BACKUPS

day_of_week=`date +%u` #1-7 (Monday-Sunday)
expired_days=`expr $((($DB_WEEKS_TO_KEEP * 7) + 1))`

if [ $day_of_week = $DB_DAY_OF_WEEK_TO_KEEP ];
then
	# Delete all expired weekly directories
	find $DB_BACKUP_DIR -maxdepth 1 -mtime +$expired_days -name "*-weekly" -exec rm -rf '{}' ';'
	        	
	perform_backups "-weekly"
	
	exit 0;
fi

# DAILY BACKUPS

# Delete daily backups 7 days old or more
find $DB_BACKUP_DIR -maxdepth 1 -mtime +$DB_DAYS_TO_KEEP -name "*-daily" -exec rm -rf '{}' ';'

perform_backups "-daily"