# Satellite Backup Script

This is a basic script to backup a Red Hat Satellite Server to a directory. It should speak for itself that this directory must have sufficent space to hold the backup, and be protected by an Enterprise Backup Tool.

The script is intended to be used where full backups are taken weekly and incremental backups are taken daily.

This has been tested on Red Hat Satellite Server 6.2 and 6.3

## Requirements
  - Packages gzip and mail installed
  - Server is configured to send mail
  - Satellite installed and configured with katello-backup (6.2) or satellite-backup (6.3) available
  - Backup Retention understood and plugged into the script's variables
  - Email address to send backup reports to plugged into the script's variables

## Usage
    satellite_backup.sh -t [full|incremental] [-d </backup_directory>]
    eg - schedule this to run weekly
    satellite_backup.sh -t full -d /app/satellite/backup
    eg - schedule this to run daily
    satellite_backup.sh -t incremental -d /app/satellite/backup
    
## Recovery

To recover from backup see the following article:

https://access.redhat.com/documentation/en-us/red_hat_satellite/6.2/html/server_administration_guide/sect-red_hat_satellite-server_administration_guide-backup_and_disaster_recovery-restoring_satellite_server_or_capsule_server_from_a_backup
