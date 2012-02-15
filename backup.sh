#!/bin/bash

DATE1=`date +%Y-%m-%d_%H_%M`
STARTTIME1=`date +%s`
BASEDIR1=/backups/db/physical/
BACKUPDIR1=/backups/db/physical/$DATE1
LOGGER=/backups/db/physical/dbbackup.log
MAIL=mail@jonathanlevin.co.uk

touch $LOGGER
if [ "$1" == "full" ]; then
	tail -f $LOGGER &
fi

/usr/bin/innobackupex --slave-info --no-timestamp $BACKUPDIR1 2>> $LOGGER

if [[ $(grep --quiet 'Error' $LOGGER) ]]; then
        grep --quiet 'Error' $LOGGER | mutt -a $LOGGER -s "TestDB XtraBackup FAILED" $MAIL
	rm -rf $BACKUPDIR1
	rm -f $LOGGER
else

	if [ -d $BACKUPDIR1 ]; then
       		/usr/bin/innobackupex --apply-log $BACKUPDIR1 2>> $LOGGER
    		if [ $? -gt 0 ]; then
          	      echo "Error: Problem detected with xtrabackup applying log." >> $LOGGER
       		fi

        	chown mysql:mysql -R $BACKUPDIR1
        	cp /etc/my.cnf $BACKUPDIR1/my.cnf.bak
        	echo "Directory and Storage size:" >> $LOGGER
        	du -h 2012-02-14_09_10/ | tail -1 >> $LOGGER

		if [ "$1" == "full" ]; then
       			 pkill -f 'tail -f $LOGGER'
		fi
       		
		mv $LOGGER $BACKUPDIR1
	fi
	
	echo "Removing old physical backups"
	#removing old backups - 2 days old
	find $BASEDIR1 -type d -ctime +1 -exec rm -rf '{}' \; >/dev/null
	find $BASEDIR1 -empty -type d -ctime +1 -exec rmdir '{}' \; >/dev/null

fi


DATE2=`date +%Y-%m-%d_%H_%M`
BASEDIR2=/backups/db/logical/
BACKUPDIR2=/backups/db/logical/$DATE2
LOGGER=/backups/db/logical/dbdump.log
STARTTIME2=`date +%s`

touch $LOGGER
if [ "$1" == "full" ]; then
        tail -f $LOGGER &
fi

mydumper -o $BACKUPDIR2 -r 500000 -e -c -l 2000 -v 3 2>> $LOGGER
if [[ $(grep --quiet 'Error' $LOGGER) ]]; then
        grep --quiet 'Error' $LOGGER | mutt -a $LOGGER -s "TestDB MyDumper FAILED" $MAIL
	rmdir --ignore-fail-on-non-empty $BACKUPDIR2
        rm -f $LOGGER
else
        if [ "$1" == "full" ]; then
	        pkill -f 'tail -f $LOGGER'
        fi
	mv $LOGGER $BACKUPDIR2

	echo "Removing old logical backups"
        #removing old backups - 7 days old
	find /backups/db/logical/ -type d -ctime +6 -exec rm -rf '{}' \; >/dev/null
	find /backups/db/logical/ -empty -type d -ctime +6 -exec rmdir '{}' \; >/dev/null
fi


LOGGER=/tmp/backupreport.txt

if [ -d $BACKUPDIR1 ]; then
        echo "XtraBackup Saved to: " $BACKUPDIR1 > $LOGGER
        du -h $BACKUPDIR1 | tail -1 | awk '{ print "Backup storage size: ",$1}' >> $LOGGER
        df -h $BACKUPDIR1 | tail -1 | awk '{ print "Available space on partition: " $4, ", Available Percent: "$5}' >> $LOGGER
        echo `expr $STARTTIME2 - $STARTTIME1` | awk '{print "Time taken:", strftime("%H:%M:%S", $1+21600)}' >> $LOGGER
        echo >> $LOGGER
fi
if [ -d $BACKUPDIR2 ]; then
        echo "MyDumper Saved to: " $BACKUPDIR2 >> $LOGGER
        du -h $BACKUPDIR2 | tail -1 | awk '{ print "Backup storage size: ",$1}' >> $LOGGER
        df -h $BACKUPDIR2 | tail -1 | awk '{ print "Available space on partition: " $4, ", Available Percent: "$5}' >> $LOGGER
	ENDTIME=`date +%s`
        echo `expr $ENDTIME - $STARTTIME2` | awk '{print "Time taken:", strftime("%H:%M:%S", $1+21600)}' >> $LOGGER
        echo >> $LOGGER
fi

if [ -d $BACKUPDIR1 ] || [ -d $BACKUPDIR2 ]; then
	pt-slave-find --host localhost | grep status >> $LOGGER
	echo >> $LOGGER
	ENDTIME=`date +%s`
        echo `expr $ENDTIME - $STARTTIME1` | awk '{print "Total Time taken:", strftime("%H:%M:%S", $1+21600)}' >> $LOGGER
	cat $LOGGER | mail -s"Backup Report" $MAIL 
fi
rm -f $LOGGER


echo "completed."
