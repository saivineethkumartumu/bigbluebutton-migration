# Updating PostgreSQL 9.5 to 13
Older versions of Greenlight used PostgreSQL 9.5 in its `docker-compose.yml` while newer versions use version 13.
PostgreSQL databases are not backwards compatible and must therefore be upgraded. Such updates are not done automatically
but must be invoked manually. The usual ways are a SQL dump with `pg_dump` followed by loading the data into the new database,
or the `pg_upgrade` command which upgrades the binary datbase.

## `pg_upgrade`
Unfortunately, `pg_upgrade` seems not only to need the `data` directory but also the old `bin` directory containing the old
executables.

See also:
* <https://github.com/tianon/docker-postgres-upgrade>

## `pg_dump`
Easiest is probably to just dump the SQL from the old PostgreSQL instance and load it again into the new PostgreSQL instance.

See also:
* <https://betterprogramming.pub/how-to-upgrade-your-postgresql-version-using-docker-d1e81dbbbdf9>
* <https://www.cloudytuts.com/tutorials/docker/how-to-upgrade-postgresql-in-docker-and-kubernetes/>

### Manual
1. Dump SQL data: `docker exec -it greenlight_db_1 /usr/bin/pg_dumpall -U postgres > postgres_9.5.sql`
2. Stop Greenlight: `docker-compose down`
3. Move `db` to `db_backup_9.5`: `mv db db_backup_9.5`
4. Change the image version in `docker-compose.yml`.
5. Start only the PostgreSQL container: `docker-compose up -d db`
6. Load the SQL data `docker exec -i greenlight_db_1 psql -U postgres < postgres_9.5.sql`
7. Start Greenlight: `docker-compose up -d`

### Long command line
All in one:
```
echo "== For now, we're only ensuring services are started, SQL dumped et cetera." && \
cd /root/greenlight/ && \
docker-compose up -d && \
docker exec -it greenlight_db_1 /usr/bin/pg_dumpall -U postgres > postgres_9.5.sql && \
docker-compose down && \
echo "== Destructive stuff starts now. If anything fails beyonf this point, you might want to restore your backup." && \
mv db db_backup_9.5 && \
sed --follow-symlinks -i -e "s/    image: postgres:.*/    image: postgres:13-alpine/g" /root/greenlight/docker-compose.yml && \
docker-compose up -d db && \
sleep 5 && \
docker exec -i greenlight_db_1 psql -U postgres < postgres_9.5.sql && \
docker-compose up -d && \
echo "Stuff is starting. Greenlight usually takes some time to do its migrations..."
```

### A script
There's also `upgrade-postgresql.sh` script with slightly nicer logging.
