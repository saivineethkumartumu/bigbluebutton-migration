#!/bin/bash

# run this script on the new server

# things to do before running this script:
#
# /home/whatever/greenlight/docker-compose.yml and /home/whatever/greenlight/.env contain a postgres password.
# It is generated on BBB installation and persisted in the postgres database files. Easiest way is changing
# /home/whatever/greenlight/docker-compose.yml and /home/whatever/greenlight/.env to contain the old password.
#
#



echo "=== Please ensure BBB and Greenlight are stopped on the source server!"
read -p "Press enter to continue"


# on the final run, --delete should probably be used; for test runs it's probably safer without --delete
RSYNC="rsync -a -x -AHX -S --numeric-ids --delete-after -v -P --stats -h -y "
#RSYNC="rsync -a -x -AHX -S --numeric-ids -v -P --stats -h -y"

# where the old BBB server is located
SRC="root@138.201.252.177"
# where greenlight was installed to by bbb-install.sh on this server
GREENLIGHT="/home/marc/greenlight"
# where greenlight was installed to by bbb-install.sh on the old server
SRC_GREENLIGHT="/home/marc/greenlight"
# hostname of the new server
DST_HOSTNAME="bbb2.avm-konferenz.de"

# stop BBB
bbb-conf --stop
# also stop Greenlight, as we are syncing the postgres database
docker-compose -f $GREENLIGHT/docker-compose.yml down

# sync greenlight postgres database
$RSYNC $SRC:$SRC_GREENLIGHT/db/ $GREENLIGHT/db/
# sync recordings
$RSYNC $SRC:/var/bigbluebutton/ /var/bigbluebutton/
# sync wahtever is in the freeswitch directory, if anything
$RSYNC $SRC:/var/freeswitch/meetings/ /var/freeswitch/meetings/
# NOTE: that's only something on my system; just remove it.
$RSYNC $SRC:/docker-compose/ /docker-compose/ 

# fix the hostname in the recordings
bbb-conf --setip $DST_HOSTNAME

# start up greenlight
docker-compose -f $GREENLIGHT/docker-compose.yml up -d
# start up BBB
bbb-conf --start

# run checks
echo "=== I'm waiting for some seconds to give services some time to spin up..."
sleep 30
bbb-conf --check
# print status
bbb-conf --status
