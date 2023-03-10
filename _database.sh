#!/bin/bash

function perform_backups() {
	###########################
	#### START THE BACKUPS ####
	###########################

	suffix="${today}/"
	full_db_staging_dir="${DB_STAGING_DIR}${suffix}"

	echo "Making backup directory in $full_db_staging_dir"

	if ! mkdir -p $full_db_staging_dir; then
		echo "Cannot create backup directory in $full_db_staging_dir. Go and fix it!" 1>&2
		exit 1;
	fi;

	if [ "${DB_TYPE}" = "oracle" ]; then

		echo -e "${GREEN}${BOLD}\n\nPerforming full backups"
		echo -e "--------------------------------------------\n${NORMAL}${NO_COLOR}"

		# TODO
		
	elif [ "${DB_TYPE}" = "postgres" ]; then
	
		#######################
		### GLOBALS BACKUPS ###
		#######################

		echo -e "${GREEN}${BOLD}\n\nPerforming globals backup"
		echo -e "--------------------------------------------\n${NORMAL}${NO_COLOR}"

		if [ $DB_ENABLE_GLOBALS_BACKUPS = "yes" ]
		then
				echo "Globals backup"

				set -o pipefail
				if ! pg_dumpall -g -h "$DB_HOSTNAME" -U "$DB_USERNAME" | gzip > $full_db_staging_dir"globals".sql.gz.in_progress; then
						echo "[!!ERROR!!] Failed to produce globals backup" 1>&2
				else
						mv $full_db_staging_dir"globals".sql.gz.in_progress $full_db_staging_dir"globals".sql.gz
						cp_to_cloud $full_db_staging_dir "globals.sql.gz"
				fi
				set +o pipefail
		else
			echo "None"
		fi
		
		
		###########################
		###### FULL BACKUPS #######
		###########################

		full_backup_query="select datname from pg_database where not datistemplate and datallowconn order by datname;"

		echo -e "${GREEN}${BOLD}\n\nPerforming full backups"
		echo -e "--------------------------------------------\n${NORMAL}${NO_COLOR}"

		for database in `psql -h "$DB_HOSTNAME" -U "$DB_USERNAME" -At -c "$full_backup_query" postgres`
		do
			if [ $DB_ENABLE_PLAIN_BACKUPS = "yes" ]
			then
				echo "Plain backup of $database"
		
				set -o pipefail
				if ! pg_dump -Fp -h "$DB_HOSTNAME" -U "$DB_USERNAME" "$database" | gzip > $full_db_staging_dir"$database".sql.gz.in_progress; then
					echo "${RED}[!!ERROR!!] Failed to produce plain backup database ${database}${NO_COLOR}" 1>&2
				else
					mv $full_db_staging_dir"$database".sql.gz.in_progress $full_db_staging_dir"$database".sql.gz
					cp_to_cloud $full_db_staging_dir "${database}.sql.gz"
				fi
				set +o pipefail
							
			fi

			if [ $DB_ENABLE_CUSTOM_BACKUPS = "yes" ]
			then
				echo "Custom backup of $database"
		
				if ! pg_dump -Fc -h "$DB_HOSTNAME" -U "$DB_USERNAME" "$database" -f $full_db_staging_dir"$database".custom.in_progress; then
					echo "${RED}[!!ERROR!!] Failed to produce custom backup database ${database}${NO_COLOR}"
				else
					mv $full_db_staging_dir"$database".custom.in_progress $full_db_staging_dir"$database".custom
					cp_to_cloud $full_db_staging_dir "${database}.custom"
				fi
			fi

		done
	fi

	echo -e "${GREEN}${BOLD}\nAll database backups complete! ${CELEBRATE}${NORMAL}${NO_COLOR}"
}