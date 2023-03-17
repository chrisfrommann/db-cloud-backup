#!/bin/bash

function cp_to_cloud() {
	local_dir=$1
	file_name=$2

	suffix="daily/${DB_TODAY}/"

	set -o pipefail
	if [ "${DB_CLOUD_BACKUP_BACKEND}" == "azure" ]; then
		az storage blob directory upload -c "${DB_AZURE_CONTAINER}" --account-name "${DB_AZURE_ACCOUNT}" \
	-s "${local_dir}${file_name}" -d "${DB_CLOUD_BACKUP_PATH}${suffix}" --only-show-errors
	else
		aws s3 cp "${local_dir}${file_name}" "${DB_CLOUD_BACKUP_PATH}${suffix}${file_name}"
	fi
	set +o pipefail
}

export -f cp_to_cloud
export DB_CLOUD_BACKUP_BACKEND
export DB_CLOUD_BACKUP_PATH
export DB_AZURE_CONTAINER
export DB_AZURE_ACCOUNT
export DB_TODAY

function create_weeklies() {
	# Get the current day of week
	if [ "$(uname)" == "Darwin" ]; then
		# macOS/BSD uses a different date format
		day_of_week=$(date -j -f "%Y-%m-%d" "${DB_TODAY}" +"%u")
	else
		day_of_week=$(date -d "${DB_TODAY}" +%u)
	fi
	

	suffix="${DB_TODAY}/"
	src="${DB_CLOUD_BACKUP_PATH}daily/${suffix}"
	dest="${DB_CLOUD_BACKUP_PATH}weekly/${suffix}"

	if [ "$day_of_week" = "$DB_DAY_OF_WEEK_TO_KEEP" ];
	then
		echo -e "${GREEN}${BOLD}\n\nCreating weekly backup"
		echo -e "--------------------------------------------\n${NORMAL}${NO_COLOR}"

		# Move today's daily backup to the weekly directory
		# TODO: consider copying instead of moving
		set -o pipefail
		if [ "${DB_CLOUD_BACKUP_BACKEND}" == "azure" ]; then
			files=$(az storage blob list --account-name "${DB_AZURE_ACCOUNT}" \
				--container-name "${DB_AZURE_CONTAINER}" --prefix "${src}" \
                --delimiter "/" --query "[].name" -o tsv)
			for f in ${files}
			do
				az storage blob copy start --account-name "${DB_AZURE_ACCOUNT}" \
				--destination-blob "${dest}" \
				--destination-container "${DB_AZURE_CONTAINER}" \
				--source-container "${DB_AZURE_CONTAINER}" \
				--source-account-name "${DB_AZURE_ACCOUNT}" \
				--source-blob ${f} \
				--only-show-errors
			done
		else
			aws s3 mv "${src}" "${dest}" --recursive
		fi
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
		cutoff_date=$(date -j -v-"${days_to_keep}"d +"%Y-%m-%d")
	else
		cutoff_date=$(date --date="${days_to_keep} days ago" +"%Y-%m-%d")
	fi

	# List all directories (hence grep "PRE") in the S3 bucket with the specified prefix
	if [ "${DB_CLOUD_BACKUP_BACKEND}" == "azure" ]; then
		directories=$(az storage blob list --account-name ${DB_AZURE_ACCOUNT} --container-name ${DB_AZURE_CONTAINER} \
		--prefix "${cloud_prefix}" --delimiter "/" --query "[?ends_with(name, '/')] | [].name" -o tsv)
	else
		directories=$(aws s3 ls "${cloud_prefix}" | grep "PRE" | awk -F " " '{print $2}')
	fi

	# Loop through each "directory" (really, prefix) and check if its prefix is older than the cutoff date
	for directory in ${directories}
	do
		directory_date=$(echo "$(basename $directory)" | cut -d '/' -f 1)
		if [[ ${directory_date} < ${cutoff_date} ]]; then
			# Delete the directory and its contents
			echo "Deleting directory/prefix: ${directory}"
			set -o pipefail
			if [ "${DB_CLOUD_BACKUP_BACKEND}" == "azure" ]; then
				az storage blob delete-batch --account-name ${DB_AZURE_ACCOUNT} \
				--source ${DB_AZURE_CONTAINER} --pattern '${cloud_prefix}${directory_date}/*' --dryrun --delete-snapshots include \
				--only-show-errors
			else
				aws s3 rm "${cloud_prefix}${directory}" --recursive
			fi
			set +o pipefail
		fi
	done
}