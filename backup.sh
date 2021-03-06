#!/bin/bash

##### Configuration #####

DATE1=`date +%Y-%m-%d_%H_%M`
STARTTIME1=`date +%s`
BASEDIRPHYSICAL=/backups/db/physical/
BACKUPDIRPHYSICAL=/backups/db/physical/$DATE1
#Please note that moving a physical backup into the MySQL dir on the same partition is almost instant.
#Keeping it on another partition could take some time to copy over to the MySQL dir.
LOGGER=/backups/db/physical/dbbackup.log
MAIL=mail@jonathanlevin.co.uk
HOST=127.0.0.1
USER=root
PASSWORD=OMG_PONIES

MYDUMPER=Yes
MYSQLERRORLOG=/var/lib/mysql/error.log

touch $LOGGER
if [ "$1" == "full" ]; then
	tail -f $LOGGER &
fi

/usr/bin/innobackupex --host $HOST --user $USER --password $PASSWORD --slave-info --no-timestamp $BACKUPDIRPHYSICAL 2>> $LOGGER

if [[ $(egrep --quiet 'Error|FATAL' $LOGGER) ]]; then
	egrep --quiet 'Error|FATAL' $LOGGER | mutt -a $LOGGER -s "TestDB XtraBackup FAILED" $MAIL
	rm -rf $BACKUPDIRPHYSICAL
	rm -f $LOGGER
else

	if [ -d $BACKUPDIRPHYSICAL ]; then
       		/usr/bin/innobackupex --apply-log $BACKUPDIRPHYSICAL 2>> $LOGGER
    		if [ $? -gt 0 ]; then
          	      echo "Error: Problem detected with xtrabackup applying log." >> $LOGGER
       		fi

        	chown mysql:mysql -R $BACKUPDIRPHYSICAL
        	cp /etc/my.cnf $BACKUPDIRPHYSICAL/my.cnf.bak
        	echo "Directory and Storage size:" >> $LOGGER
        	du -h 2012-02-14_09_10/ | tail -1 >> $LOGGER

		if [ "$1" == "full" ]; then
       			 ps -ef | grep tail | grep dbbackup.log | awk '{print $2}' | xargs kill -9 
		fi
       		
		mv $LOGGER $BACKUPDIRPHYSICAL
	fi
	
	echo "Removing old physical backups"
	#removing old backups - 2 days old
	find $BASEDIRPHYSICAL -type d -ctime +1 -exec rm -rf '{}' \; 2>/dev/null
	find $BASEDIRPHYSICAL -empty -type d -ctime +1 -exec rmdir '{}' \; 2>/dev/null

fi

if [ $MYDUMPER == "Yes" ]; then


DATE2=`date +%Y-%m-%d_%H_%M`
BASEDIRLOGICAL=/backups/db/logical/
BACKUPDIRLOGICAL=/backups/db/logical/$DATE2
LOGGER=/backups/db/logical/dbdump.log
STARTTIME2=`date +%s`

touch $LOGGER
if [ "$1" == "full" ]; then
        tail -f $LOGGER &
fi

mydumper -o $BACKUPDIRLOGICAL -r 500000 -e -c -l 2000 -v 3 -h 127.0.0.1 -h $HOST -u $USER -p $PASSWORD 2>> $LOGGER
if [[ $(egrep --quiet 'Error|CRITICAL' $LOGGER) ]]; then
        grep --quiet 'Error|CRITICAL' $LOGGER | mutt -a $LOGGER -s "TestDB MyDumper FAILED" $MAIL
	rmdir --ignore-fail-on-non-empty $BACKUPDIRLOGICAL
        rm -f $LOGGER
else
        if [ "$1" == "full" ]; then
	        ps -ef | grep tail | grep dbdump.log | awk '{print $2}' | xargs kill -9
        fi
	mv $LOGGER $BACKUPDIRLOGICAL

	echo "Removing old logical backups"
        #removing old backups - 7 days old
	find /backups/db/logical/ -type d -ctime +6 -exec rm -rf '{}' \; >/dev/null
	find /backups/db/logical/ -empty -type d -ctime +6 -exec rmdir '{}' \; >/dev/null
fi

fi

LOGGER=/tmp/backupreport.txt

if [ -d $BACKUPDIRPHYSICAL ]; then
        echo "XtraBackup Saved to: " $BACKUPDIRPHYSICAL > $LOGGER
        du -h $BACKUPDIRPHYSICAL | tail -1 | awk '{ print "Backup storage size: ",$1}' >> $LOGGER
        df -h $BACKUPDIRPHYSICAL | tail -1 | awk '{ print "Available space on partition: " $4, ", Available Percent: "$5}' >> $LOGGER
        echo `expr $STARTTIME2 - $STARTTIME1` | awk '{print "Time taken:", strftime("%H:%M:%S", $1+21600)}' >> $LOGGER
        echo >> $LOGGER
fi
if [ -d $BACKUPDIRLOGICAL ] && [ $MYDUMPER == "Yes" ]; then
        echo "MyDumper Saved to: " $BACKUPDIRLOGICAL >> $LOGGER
        du -h $BACKUPDIRLOGICAL | tail -1 | awk '{ print "Backup storage size: ",$1}' >> $LOGGER
        df -h $BACKUPDIRLOGICAL | tail -1 | awk '{ print "Available space on partition: " $4, ", Available Percent: "$5}' >> $LOGGER
	ENDTIME=`date +%s`
        echo `expr $ENDTIME - $STARTTIME2` | awk '{print "Time taken:", strftime("%H:%M:%S", $1+21600)}' >> $LOGGER
        echo >> $LOGGER
fi

if [ -d $BACKUPDIRPHYSICAL ] || [ -d $BACKUPDIRLOGICAL ] && [ $MYDUMPER == "Yes" ]; then
	pt-slave-find --host $HOST --user $USER --password $PASSWORD | grep status >> $LOGGER
	echo >> $LOGGER
	ENDTIME=`date +%s`
        echo `expr $ENDTIME - $STARTTIME1` | awk '{print "Total Time taken:", strftime("%H:%M:%S", $1+21600)}' >> $LOGGER
	echo >> $LOGGER
	if [ -f $MYSQLERRORLOG ]; then	
		cat $MYSQLERRORLOG >> $LOGGER
		cp -f $MYSQLERRORLOG $MYSQLERRORLOG.old
		echo > $MYSQLERRORLOG	
	fi
	cat $LOGGER | mail -s"Backup Report" $MAIL 
fi
rm -f $LOGGER


echo "completed."
