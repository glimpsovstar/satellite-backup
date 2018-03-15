#!/bin/bash
#set -xv
#####################################################################################
#
# Script Name:
#  satellite_backup.sh
#
# Purpose:
#       Performs a backup of Red Hat Satellite Server to a local or remote mounted
#       directory. This script is to be used in an environment where weekly full
#       and daily incremental backups are taken. Rentention is goverened by the 
#       RETENTION variable at the top of the script.
#
# Dependencies:
#       Red Hat Satellite 6.2 or above - katello-backup must be available.
#	Packages mail, gzip must be installed and the server must be able to send mail.
#
# Disclaimer:
#	This script is NOT SUPPORTED by Red Hat Global Support Service.
#
# Modification History:
#  v1.0 - 27/10/2015 - Initial Version - Talor Holloway (Red Hat Consulting)
#
# Called by:
#  root crontab
#
#####################################################################################

RETENTION=31 # how long to keep backups for
ALERTS=someone@example.com
REPORTS=someone@example.com
TAG=$(date '+%Y%m%d-%H%M')
LOCKFILE=/tmp/.$(basename $0).lck
LOGDIR=/var/log/satellite_backup
LOG=${LOGDIR}/satellite_backup.log
WEEKDAY=$(date +%u)
SCRIPTNAME=${0##*/}
MSGS=true
ERRS=true
RV=0

#####################################################################################
###################  Functions
#####################################################################################

msg()
{
        $MSGS && echo "$*....."
}

msg70()
{
# like msg but doesn't print a new line instead just stops at 70th column {
        $MSGS && printf "%-70s" "$*......"
}

err()
{
        $ERRS && echo "$*....." >&2
}

ok()
{
        $MSGS && echo ok
}

failed()
{
        $MSGS && echo failed
}

usage()
{
        MESSAGE=$*
        echo
        echo "$MESSAGE"
        echo
        echo "$0 -t [full|incremental] [-d </backup_directory>]"
        echo
        exit 1
}

generate_lock()
{
        if [ -f ${LOCKFILE} ]
        then
                Pid=$(cat $LOCKFILE)
                if ps -fp $Pid > /dev/null 2>&1
                then
                        MSG="$SCRIPTNAME [ Pid: $Pid ] already running on ${SID} please investigate"
                        cat $LOG | mail -s "$MSG" $ALERTS
                        exit
                else
                        rm -rf $LOCKFILE
                        echo $$ > ${LOCKFILE}
                fi
        else
                echo $$ > ${LOCKFILE}
        fi
}

atexit()
# exit routine
{
        if [ $RV -gt 0 ]
        then
                MSG="An error occurred whilst performing a ${TYPE} Satellite Backup on $(hostname -s)"
                cat $LOG | mail -s "$MSG" $ALERTS
        else
                MSG="An ${TYPE} Satellite backup on $(hostname -s) completed successfully"
                cat $LOG |mail -s "$MSG" $REPORTS
        fi

        # Make sure the lock file is removed
        if [ -f $LOCKFILE ]
        then
                rm -f $LOCKFILE
        fi

        # recycle log files
        if [ -f $LOG ]
        then
                cp -p $LOG $LOG.$TAG
                gzip -f $LOG.$TAG
        fi

        msg "The return value is $RV"
        msg Exiting

        exit $RV
}

run_backupdir_validation()
{
	if [ -d $BACKUP_DIRECTORY ] && [ -w $BACKUP_DIRECTORY ]
	then
		msg70 Backup Directory $BACKUP_DIRECTORY is mounted and writeable
		ok
	else
		msg Backup Directory $BACKUP_DIRECTORY either does not exist or is not writable
		RV=10
	fi

	if [ ! -d ${BACKUP_DIRECTORY}/incr ]
	then
		mkdir -p ${BACKUP_DIRECTORY}/incr
	fi

	if [ ! -d ${BACKUP_DIRECTORY}/full ]
	then
		mkdir -p ${BACKUP_DIRECTORY}/full
	fi
}

run_full()
{
        echo "================================================================"
        echo "$TYPE backup of Satellite started at $(date)"
        echo "================================================================"

	katello-backup ${BACKUP_DIRECTORY}/full --assumeyes
        rv=$?
        if [ $rv -eq 0 ]
        then
                ok
        else
                failed
                err "Return value is $rv"
		RV=11
		exit
        fi

        echo "================================================================"
        echo "$TYPE backup of Satellite ended at $(date)"
        echo "================================================================"
}

run_incremental()
{
        echo "================================================================"
        echo "$TYPE backup of Satellite started at $(date)"
        echo "================================================================"

	if [ $(find ${BACKUP_DIRECTORY}/full |grep -c katello-backup) -gt 0 ]
	then
                LASTFULL=$(find ${BACKUP_DIRECTORY}/full -type d |sort -rn |head -1)
                katello-backup ${BACKUP_DIRECTORY}/incr --incremental ${LASTFULL} --assumeyes 
	        rv=$?
 		if [ $rv -eq 0 ]
	 	then
	                ok
 	        else
 	                failed
 	                err "Return value is $rv"
 		        RV=12
			exit
  	        fi

                echo "================================================================"
                echo "$TYPE backup of Satellite ended at $(date)"
                echo "================================================================"
        else
		echo "No Full Backup Found"
		echo "Switching to Full backup"
		TYPE=Full
		run_full
	fi
}

run_expiration()
{

        echo "================================================================"
        echo "Satellite Backup Expiration started at $(date)"
        echo "================================================================"

	msg Removing Daily Incremental Backups - ${RETENTION} days
	for incr_dir in $(/usr/bin/find ${BACKUP_DIRECTORY}/incr -type d -mtime +${RETENTION} -name "*katello-backup*")
	do
		msg70 Removing $incr_dir
		rm -rf $incr_dir
                rv=$?
                if [ $rv -eq 0 ]
                then
                        ok
                else
                        failed
                        err "Return value is $rv"
			RV=13
			exit
                fi
	done

	msg Removing Weekly Full Backups - ${RETENTION} days plus 7 to cater for a weeks worth of incrementals tied to the full
	for full_dir in $(/usr/bin/find ${BACKUP_DIRECTORY}/full -type d -mtime +$(( $RETENTION + 7)) -name "*katello-backup*")
	do
		msg70 Removing $full_dir
		rm -rf $full_dir
                rv=$?
                if [ $rv -eq 0 ]
                then
                        ok
                else
                        failed
                        err "Return value is $rv"
			RV=14
			exit
                fi
	done

        echo "================================================================"
        echo "$Satellite Backup Expiration ended at $(date)"
        echo "================================================================"
}

#####################################################################################
###################  Main (Main MAIN Main)
#####################################################################################

# Process options have been passed to the script
while getopts ":t:d:" opt
do
        case $opt in
                t)      TYPE=${OPTARG} ;;
                d)      BACKUP_DIRECTORY=${OPTARG} ;;
                *)      usage "ERROR: Unknown Option"; exit ;;
        esac
done

[ -z "$TYPE" ] && usage "ERROR: Specify the backup type"
[ -z "$BACKUP_DIRECTORY" ] && usage "ERROR: Specify the backup directory"

# Check we are running as root
if [ $(whoami) != root ]
then
        echo "This script must run as the root user"
        RV=2
        exit
fi

# Generate the lock file
generate_lock

# make sure log directory exists
if [ ! -d $LOGDIR ]
then
	mkdir -p $LOGDIR
fi

# redirect stdout and stderr to the log file
exec >$LOG 2>&1

# Call function at the end if the script exists cleanly.
trap atexit 0

msg "Validating the Backup directory"
run_backupdir_validation

case $TYPE in
        FULL|Full|full)
                msg "Running a Full Satellite Backup"
                run_full
        ;;
        INCREMENTAL|Incremental|incremental|INC|Inc|inc|INCR|Incr|incr)
                msg "Running an Incremental Satellite Backup"
                run_incremental
        ;;
        *)
                usage "ERROR Unknown Backup Type"
		RV=666
		exit
        ;;
esac

msg "Kicking off Expiration of old backups"
run_expiration

# If script ends with RV=0 then atexit() is called due to trap.
