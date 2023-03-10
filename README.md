# Database cloud backups

This script creates a backup of a local database to a cloud backend. It assumes:
1. Your DB is not in the cloud (otherwise just use e.g. RDS with automatic backups)
2. Your destination bucket already exists and you have permissions to write to it

## Dependencies
Ensure you have the following installed
1. GNU parallel
2. S3 command line tools on the path
For Oracle:
1. SQL Plus
For PostgreSQL:

## Running
Copy `backup.conf.sample` to `backup.conf` and modify settings as appropriate

    ./backup.sh -c backup.conf