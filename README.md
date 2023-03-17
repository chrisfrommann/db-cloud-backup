# Database cloud backups

This script creates a backup of a local database to a cloud backend. It assumes:
1. Your DB is not in the cloud (otherwise just use e.g. RDS with automatic backups)
2. Your destination bucket already exists and you have permissions to write to it
3. You are either running this script on the DB server or can SSH to that machine

## Dependencies
Ensure you have the following installed
1. GNU parallel
2. AWS command line tools and/or (to install on macOS `brew install awscli`)
3. Azure command line tools (to install on macOS: `brew install azure-cli`)

**For Oracle:**

Grab the [Instant Client Tools & SQLPlus packages](https://www.oracle.com/database/technologies/instant-client/downloads.html) from Oracle, which includes `expdp` and `sqlplus`

_On macOS:_

    brew tap InstantClientTap/instantclient
    brew install instantclient-tools
    brew install instantclient-sqlplus

And update your path to include the `expdp` and `sqlplus` binaries
(run `brew info instantclient-tools` and `brew install instantclient-sqlplus` to see where they lives)

**For PostgreSQL:**

Install PostgreSQL client libraries

_On macOS:_

    brew install libpq

See [here](https://stackoverflow.com/questions/44654216/correct-way-to-install-psql-without-full-postgres-on-macos) for updating your path.

## Setup & running
1. Copy `backup.conf.sample` to `backup.conf` and modify settings as appropriate
2. Then run
    ```
    ./backup.sh -c backup.conf
    ```


## Linting
Run `make lint`

To automatically patch, run e.g. `shellcheck -f diff backup.sh | patch`