#!/usr/bin/env bash

function getTimeStamp() {
	echo $(date "+%FT%H-%M-%S%z")
}

function logInfo() {
	echo "[INFO] $(getTimeStamp) - $1"
}

function logError() {
	echo "[ERROR] $(getTimeStamp) - $1"
}

function error() {
	logError "Backup failed. Error in line $1"
	echo "Backup failed. Error in line $1" \
	| mailx \
		-s 'Failed Backup Job' \
		-S from='FROM ADRESS' \
		-S smtp='<SMTP SERVER>' \
		-S smtp-auth=login \
		-S smtp-auth-user='<SMTP USER>' \
		-S smtp-auth-password='<SMTP PASSWORD>' \
		-S smtp-use-starttls \
		-S ssl-verify=strict \
		<TO ADRESS>
	exit 1
}

function getBackupDirectoryName() {
	timestamp=$(getTimeStamp)

	until [ ! -d $2/$timestamp ]
	do
		sleep 5
		timestamp=$(getTimeStamp)
	done

	echo $timestamp
}

function getLatestBackupDirectoryName() {
	echo $(ls -d */ | sort | tail -n 1)
}

function directoryIsNotEmpty() {
	echo $(ls -A)
}

function runRsync() {
	logInfo "rsync start --------------------------------------------------"
	rsync -va --delete --stats --exclude-from=/usr/local/bin/backup_excludes.txt $1 $2
	logInfo "rsync end --------------------------------------------------"
}

function hasChanged() {
	rsync -ain --delete --exclude-from=/usr/local/bin/backup_excludes.txt $1 $2
}

function performBackup() {
	logInfo "Backup source directory: $1"
	logInfo "Backup destination directory: $2"

	logInfo "Trying to mount destination disk."
	mount /mnt/RescueHero/

	logInfo "Entering backup destination directory."
	cd $2

	backupDirectoryName=$(getBackupDirectoryName $2)

	if [ ! "$(directoryIsNotEmpty)" ]
	then
		runRsync $1 $2/$backupDirectoryName
	else
		logInfo "Backup directory is not empty."
		latestBackupDirectoryName=$(getLatestBackupDirectoryName)

		logInfo "Checking for changes between $1 and $2/$latestBackupDirectoryName"

		if [ "$(hasChanged $1 $2/$latestBackupDirectoryName)" ]
		then
			logInfo "Source directory has changed."
			logInfo "Creating hard links of latest backup directory: $latestBackupDirectoryName"
			cp -al $latestBackupDirectoryName $backupDirectoryName
			runRsync $1 $2/$backupDirectoryName
		else
			logInfo "Nothing has changed. No need to perform backup"
		fi
	fi

	logInfo "Switching back to prior directory."
	cd -

	logInfo "Unmounting destination disk."
	umount /mnt/RescueHero/
}

#exec >> /var/log/backup/$(date "+%F").log 
exec 2>&1

trap 'error $LINENO' ERR

if [ $# -eq 2 ]
then
	if [ $EUID -eq 0 ]
	then
		logInfo "Backup started."
		performBackup $1 $2
		logInfo "Backup finished."
	else
		logError "Root privileges are required."
		error $LINENO
	fi
else
	logError "Invalid number of arguments. Usage: backup <source> <destination>"
	error $LINENO
fi

