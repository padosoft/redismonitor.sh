#!/bin/bash
#
# Author: Lorenzo Padovani
# @padosoft
# https://github.com/lopadova
# https://github.com/padosoft
#

#
# Add a cron job
# ref.: http://stackoverflow.com/questions/878600/how-to-create-cronjob-using-bash
#
#write out current crontab into temp file
crontab -l > mycron

#echo new cron into cron file
echo "* * * * * bash /root/myscript/redismonitor.sh/redismonitor.sh > /var/log/redismonitor-$(date +\%Y-\%m-\%d_\%H-\%M-\%S).log 2>&1" >> mycron


#install new cron file
crontab mycron

#print result
echo "cronjobs added successfull!"

#remove tmp file
rm mycron
