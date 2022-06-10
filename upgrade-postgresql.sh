#!/bin/bash
log() {
  echo "== $1"
}

DATETIME=$(date '+%Y-%m-%d_%H-%M-%S')

log "Changing into Greenlight directory..."
cd /_deployment/greenlight/

log "Ensuring PostgreSQL is started..."
docker-compose up -d db

log "Dumping database to SQL..."
docker exec -it greenlight_db_1 /usr/bin/pg_dumpall -U postgres > db_$DATETIME.sql

log "Shutting down Greenlight and PostgreSQL..."
docker-compose down

log "Creating backup of 'db' directory..."
cp -a db "db.backup_$DATETIME"

log ""
log "The potentially destructive part starts now. If anything fails beyond this point, you probably want to restore your backup."
log ""

log "Deleting PostgreSQL 'db' directory..."
rm -rf db

DESTINATION_VERSION="13-alpine"
log "Changing PostgreSQL image version to '$DESTINATION_VERSION'..."
sed --follow-symlinks -i -e "s/    image: postgres:.*/    image: postgres:${DESTINATION_VERSION}/g" /_deployment/greenlight/docker-compose.yml

log "Starting PostgreSQL..."
docker-compose up -d db

log "Waiting for PostgreSQL..."
sleep 10

log "Loading SQL..."
docker exec -i greenlight_db_1 psql -U postgres < db_$DATETIME.sql

log "Starting Greenlight..."
docker-compose up -d

log "Greenlight usually takes some time to do its migrations. You might see a 502 for a minute."