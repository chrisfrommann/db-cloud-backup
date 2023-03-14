#!/bin/bash
export SHELL=$(type -p bash)

function perform_full_oracle_backup() {

    # Create the appropriate directory in Oracle
    sqlplus "${DB_USERNAME}"/"${DB_PASSWORD}"@"${DB_HOSTNAME}" <<EOF
CREATE or REPLACE DIRECTORY cloud_dpump_dir as '${DB_STAGING_DIR}';
GRANT READ, WRITE ON DIRECTORY cloud_dpump_dir TO ${DB_USERNAME};
EOF

    # Export full database into proprietary Oracle format
    # See:
    # https://docs.oracle.com/database/121/SUTIL/GUID-1E134053-692A-4386-BB77-153CB4A6071A.htm#SUTIL887
    # https://stackoverflow.com/questions/16415120/exp-command-accepts-host-and-port-to-export-remote-db-tables
    expdp "${DB_USERNAME}"/"${DB_PASSWORD}"@"${DB_HOSTNAME}" FULL=YES DUMPFILE=cloud_dpump_dir:exp_full_%U.dmp \
    FILESIZE=4G PARALLEL="${PARALLEL_PROCESSES}" LOGFILE=cloud_dpump_dir:exp_full.log JOB_NAME=exp_full

    # Upload dmp files in parallel
    ls $DB_STAGING_DIR | grep -E '\.dmp$' | parallel -j "${PARALLEL_PROCESSES}" cp_to_cloud "$DB_STAGING_DIR" {}

    if [ ! -z "${DB_STAGING_DIR}" ]
    then
        rm -r ${DB_STAGING_DIR}/*
    fi
}

function perform_postgres_table_backup() {
    set -euo pipefail

    full_db_staging_dir=$1
    database=$2
    process=$3

    if [ "${DB_ENABLE_PLAIN_BACKUPS}" = "yes" ]
    then
        echo "Plain backup of $database (process ${process})"

        set -o pipefail
        if ! pg_dump -Fp -h "$DB_HOSTNAME" -U "$DB_USERNAME" "$database" | gzip > "$full_db_staging_dir""$database".sql.gz.in_progress; then
            echo "${RED}[!!ERROR!!] Failed to produce plain backup database ${database}${NO_COLOR}" 1>&2
        else
            mv "$full_db_staging_dir""$database".sql.gz.in_progress "$full_db_staging_dir""$database".sql.gz
            cp_to_cloud "$full_db_staging_dir" "${database}.sql.gz"
        fi
        set +o pipefail
                    
    fi

    if [ "$DB_ENABLE_CUSTOM_BACKUPS" = "yes" ]
    then
        echo "Custom backup of $database (process ${process})"

        if ! pg_dump -Fc -h "$DB_HOSTNAME" -U "$DB_USERNAME" "$database" -f "$full_db_staging_dir""$database".custom.in_progress; then
            echo "${RED}[!!ERROR!!] Failed to produce custom backup database ${database}${NO_COLOR}"
        else
            mv "$full_db_staging_dir""$database".custom.in_progress "$full_db_staging_dir""$database".custom
            cp_to_cloud "$full_db_staging_dir" "${database}.custom"
        fi
    fi
}

export -f perform_postgres_table_backup
export DB_ENABLE_PLAIN_BACKUPS
export DB_ENABLE_CUSTOM_BACKUPS
export DB_HOSTNAME
export DB_USERNAME

function perform_backups() {
	###########################
	#### START THE BACKUPS ####
	###########################

	if [ "${DB_TYPE}" = "oracle" ]; then

		echo -e "${GREEN}${BOLD}\n\nPerforming full backups"
		echo -e "--------------------------------------------\n${NORMAL}${NO_COLOR}"

		perform_full_oracle_backup

        if [ ! -z "${DB_STAGING_DIR}" ]
        then
            rm -r ${DB_STAGING_DIR}/*
        fi
		
	elif [ "${DB_TYPE}" = "postgres" ]; then

        suffix="${DB_TODAY}/"
        full_db_staging_dir="${DB_STAGING_DIR}${suffix}"

        echo "Making backup directory in $full_db_staging_dir"

        if ! mkdir -p "$full_db_staging_dir"; then
            echo "Cannot create backup directory in $full_db_staging_dir. Go and fix it!" 1>&2
            exit 1;
        fi;
	
		#######################
		### GLOBALS BACKUPS ###
		#######################

		echo -e "${GREEN}${BOLD}\n\nPerforming globals backup"
		echo -e "--------------------------------------------\n${NORMAL}${NO_COLOR}"

		if [ "$DB_ENABLE_GLOBALS_BACKUPS" = "yes" ]
		then
				echo "Globals backup"

				set -o pipefail
				if ! pg_dumpall -g -h "$DB_HOSTNAME" -U "$DB_USERNAME" | gzip > "$full_db_staging_dir""globals".sql.gz.in_progress; then
						echo "[!!ERROR!!] Failed to produce globals backup" 1>&2
				else
						mv "$full_db_staging_dir""globals".sql.gz.in_progress "$full_db_staging_dir""globals".sql.gz
						cp_to_cloud "$full_db_staging_dir" "globals.sql.gz"
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

        databases=$(psql -h "$DB_HOSTNAME" -U "$DB_USERNAME" -At -c "$full_backup_query" postgres)
        # Backup using GNU Parallel
        printf '%s\n' "$databases" | parallel -j "${PARALLEL_PROCESSES}" perform_postgres_table_backup "$full_db_staging_dir" {} {%}

        if [ ! -z "${full_db_staging_dir}" ]
        then
            rm -r ${full_db_staging_dir}/*
        fi
    fi

	echo -e "${GREEN}${BOLD}\n${CELEBRATE} All database backups complete!${NORMAL}${NO_COLOR}"
}