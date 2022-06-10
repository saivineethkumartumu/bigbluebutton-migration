#!/bin/bash

# Run this script on the new server.

# Things to do before running this script:
#
# The following files contain the PostgreSQL password:
# - /home/whatever/greenlight/docker-compose.yml
# - /home/whatever/greenlight/.env
# - the PostgreSQL database file!
# The PostgreSQL password was generated by bbb-install.sh on the source server
# and is also persisted in the PostgreSQL database files. As it is not easy to
# change the PostgreSQL password in the database file, it is easiest to change
# the other files to use the source PostgreSQL password.
#
# Do not change any other password or secrets!
#
# Older versions of Greenlight docker-compose.yml used PostgreSQL 9 while newer use 13.2.
# Unfortunately, the database files are not binary compatible.
# Easiest solution is to just use the version on your source server.
# But you can also use upgrade-postgresql.sh which simplifies the upgrade.


# Configuration

# On the final run, --delete should probably be used; for test runs it's probably safer without --delete
#RSYNC="rsync -a -x -AHX -S --numeric-ids -v -P --stats -h -y --delete-after"
RSYNC="rsync -a -x -AHX -S --numeric-ids -v -P --stats -h -y"

# Where the old BBB server is located; could also be an IP. Must be root.
SOURCE_SERVER="root@bbb4.avm-konferenz.de"

# Hostname of the new server; must be the FQDN and not some "localhost" thing
#DESTINATION_FQDN="bbb5.avm-konferenz.de"
DESTINATION_FQDN=$(hostname -f)

# Where greenlight was installed to by bbb-install.sh on the old server
SOURCE_GREENLIGHT_DIRECTORY="/home/marc/greenlight"

# Where greenlight was installed to by bbb-install.sh on this server
DESTINATION_GREENLIGHT_DIRECTORY="/_deployment/greenlight"

function log() {
    echo "$@" 1>&2;
}

function stop_services() {
    log "= Stopping services..."

    # Stop BBB
    bbb-conf --stop

    # Also stop Greenlight, as we are syncing the PostgreSQL database
    docker-compose -f $DESTINATION_GREENLIGHT_DIRECTORY/docker-compose.yml down
}

function rsync_all() {
    log "= Synchronizing data..."

    # Sync Greenlight PostgreSQL database
    $RSYNC $SOURCE_SERVER:$SOURCE_GREENLIGHT_DIRECTORY/db/ $DESTINATION_GREENLIGHT_DIRECTORY/db/

    # Sync recordings
    $RSYNC $SOURCE_SERVER:/var/bigbluebutton/ /var/bigbluebutton/

    # Sync whatever is in the freeswitch directory, if anything
    $RSYNC $SOURCE_SERVER:/var/freeswitch/meetings/ /var/freeswitch/meetings/

    # NOTE: that's only something on my system; just remove it.
    $RSYNC $SOURCE_SERVER:/docker-compose/ /docker-compose/ 
}

function fix_things() {
    log "= Fixing things after synchronization..."

    # Fix the hostname in the recordings
    bbb-conf --setip $DESTINATION_FQDN
}

function start_services() {
    log "= Starting services..."

    # Start up Greenlight
    docker-compose -f $DESTINATION_GREENLIGHT_DIRECTORY/docker-compose.yml up -d

    # Start up BBB
    bbb-conf --start
}

function run_checks() {
    log "= Running checks..."

    SLEEP_DURATION=30
    log "== I'm waiting for $SLEEP_DURATION seconds to give services some time to spin up..."
    sleep $SLEEP_DURATION

    # Run checks
    bbb-conf --check

    # Print status
    bbb-conf --status
}

function print_header() {
    log "= Please ensure you are root and have your ssh key loaded into the ssh-agent:"
    log "sudo -s"
    log "eval \"\$(ssh-agent -s)\""
    log "ssh-add ~$SUDO_USER/.ssh/id_ecdsa"

    log ""
    read -p "Press enter to continue."
}

function print_current_meetings() {
    log "= Getting current meeting count from bbb-exporter..."
    COUNT=$(curl -s http://localhost:9688 | grep -E "^bbb_meetings ")
    log "= Got current meeting count from bbb-exporter: $COUNT"
}

function set_destination_postgresql_password() {
    PASSWORD=$1
    log "= Setting PostgreSQL password '$PASSWORD'..."

    set_destination_dotenv "DB_PASSWORD" "$PASSWORD"

    log "= Setting PostgreSQL password '$PASSWORD' in docker-compose.yml..."
    sed --follow-symlinks -i -e "s/POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$PASSWORD/g" $DESTINATION_GREENLIGHT_DIRECTORY/docker-compose.yml
}

function get_source_postgresql_version() {
    log "= Getting PostgreSQL version from source docker-compose.yml..."

    SOURCE_POSTGRESQL_VERSION=$(ssh $SOURCE_SERVER "cat $SOURCE_GREENLIGHT_DIRECTORY/docker-compose.yml" | sed -n "s/^    image: postgres:\(.*\)$/\1/p")

    log "= Got PostgreSQL version from source docker-compose.yml: '$SOURCE_POSTGRESQL_VERSION'"
    echo $SOURCE_POSTGRESQL_VERSION
}

function set_destination_postgresql_version() {
    VERSION=$1
    log "= Setting PostgreSQL version '$VERSION' in docker-compose.yml..."

    sed --follow-symlinks -i -e "s/    image: postgres:.*/    image: postgres:$VERSION/g" $DESTINATION_GREENLIGHT_DIRECTORY/docker-compose.yml
}

function get_source_dotenv() {
    SOURCE_ENV_KEY="$1"
    log "= Getting $SOURCE_ENV_KEY from source .env..."

    SOURCE_ENV_VALUE=$(ssh $SOURCE_SERVER "cat $SOURCE_GREENLIGHT_DIRECTORY/.env" | sed -n "s/^$SOURCE_ENV_KEY=\(.*\)$/\1/p")

    log "= Got $SOURCE_ENV_KEY from source .env: '$SOURCE_ENV_VALUE'"
    echo $SOURCE_ENV_VALUE
}

function set_destination_dotenv() {
    DESTINATION_ENV_KEY="$1"
    DESTINATION_ENV_VALUE="$2"
    log "= Setting '$DESTINATION_ENV_KEY'='$DESTINATION_ENV_VALUE' in destination .env..."

    log "== Checking if '$DESTINATION_ENV_KEY' exists in destination .env"
    if grep -q "^$DESTINATION_ENV_KEY=.*" "$DESTINATION_GREENLIGHT_DIRECTORY/.env"; then
      log "== '$DESTINATION_ENV_KEY' exists in .env..."
    else
      log "== Key '$DESTINATION_ENV_KEY' does not exist in destination .env"
      log "== Adding empty '$DESTINATION_ENV_KEY' to .env..."
      echo "$DESTINATION_ENV_KEY=" >> "$DESTINATION_GREENLIGHT_DIRECTORY/.env"
    fi

    log "== Setting key '$DESTINATION_ENV_KEY'='$DESTINATION_ENV_VALUE' in destination .env..."
    sed --follow-symlinks -i -e "s/^$DESTINATION_ENV_KEY=.*/$DESTINATION_ENV_KEY=$DESTINATION_ENV_VALUE/g" $DESTINATION_GREENLIGHT_DIRECTORY/.env
}

print_header

print_current_meetings
read -p "Press enter to continue or CTRL-C to quit."

log "= Transferring Greenlight settings..."
POSTGRESQL_PASSWORD=$(get_source_dotenv "DB_PASSWORD")
set_destination_postgresql_password $POSTGRESQL_PASSWORD

POSTGRESQL_VERSION=$(get_source_postgresql_version)
set_destination_postgresql_version $POSTGRESQL_VERSION

declare -a DOTENV_KEYS=(
    "RECAPTCHA_SITE_KEY"
    "RECAPTCHA_SECRET_KEY"
    "SMTP_SERVER"
    "SMTP_PORT"
    "SMTP_DOMAIN"
    "SMTP_USERNAME"
    "SMTP_PASSWORD"
    "SMTP_AUTH"
    "SMTP_STARTTLS_AUTO"
    "SMTP_SENDER"
    "SMTP_TEST_RECIPIENT"
    )
for KEY in "${DOTENV_KEYS[@]}"
do
  log "= Transferring .env setting '$KEY'..."
  set_destination_dotenv "$KEY" $(get_source_dotenv "$KEY")
done

stop_services

log "= Starting pre-synchronization..."
rsync_all

log "= Starting final synchronization..."
log "== Please ensure BBB and Greenlight are stopped on the source server!"
read -p "Press enter to continue."
rsync_all

fix_things
start_services
run_checks
