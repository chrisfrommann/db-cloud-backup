#!/bin/bash

function cp_to_cloud() {
	local_dir=$1
	file_name=$2

	suffix="daily/${DB_TODAY}/"

	set -o pipefail
	aws s3 cp "${local_dir}${file_name}" "${DB_CLOUD_BACKUP_PATH}${suffix}${file_name}"
	set +o pipefail
}

export -f cp_to_cloud
export DB_CLOUD_BACKUP_PATH
export DB_TODAY

function create_weeklies() {
	# Get the current day of week
	if [ "$(uname)" == "Darwin" ]; then
		# macOS/BSD uses a different date format
		day_of_week=$(date -j -f "%Y-%m-%d" ${DB_TODAY} +"%u")
	else
		day_of_week=$(date -d "${DB_TODAY}" +%u)
	fi
	

	suffix="${DB_TODAY}/"
	src="${DB_CLOUD_BACKUP_PATH}daily/${suffix}"
	dest="${DB_CLOUD_BACKUP_PATH}weekly/${suffix}"

	if [ $day_of_week = $DB_DAY_OF_WEEK_TO_KEEP ];
	then
		echo -e "${GREEN}${BOLD}\n\nCreating weekly backup"
		echo -e "--------------------------------------------\n${NORMAL}${NO_COLOR}"

		# Move today's daily backup to the weekly directory
		# TODO: consider copying instead of moving
		set -o pipefail
		aws s3 mv "${src}" "${dest}" --recursive
		set +o pipefail
	fi
}

function rm_stale_backups() {
	cloud_prefix="${1}${2}/"
	type=$2
	days_to_keep=$3

	echo -e "${GREEN}${BOLD}\n\nRemoving stale ${type} backups"
	echo -e "--------------------------------------------\n${NORMAL}${NO_COLOR}"

	# Get the cutoff date X days ago
	if [ "$(uname)" == "Darwin" ]; then
		# macOS/BSD uses a different date format
		cutoff_date=$(date -j -v-${days_to_keep}d +"%Y-%m-%d")
	else
		cutoff_date=$(date --date="${days_to_keep} days ago" +"%Y-%m-%d")
	fi

	# List all directories (hence grep "PRE") in the S3 bucket with the specified prefix
	directories=$(aws s3 ls "${cloud_prefix}" | grep "PRE" | awk -F " " '{print $2}')

	# Loop through each "directory" (really, prefix) and check if its prefix is older than the cutoff date
	for directory in ${directories}
	do
		directory_date=$(echo ${directory} | cut -d '/' -f 1)
		if [[ ${directory_date} < ${cutoff_date} ]]; then
			# Delete the directory and its contents
			echo "Deleting directory/prefix: ${directory}"
			set -o pipefail
			aws s3 rm "${cloud_prefix}${directory}" --recursive
			set +o pipefail
		fi
	done
}