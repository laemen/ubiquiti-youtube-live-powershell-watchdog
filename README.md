# ubiquiti-youtube-live-powershell-watchdog
Powershell watchdog script for monitoring the Youtube Live stream from Ubiquiti Unifi cameras

This script uses ssh to remote login to the webcam, check if a Youtube live stream is running, and 
if not it starts one and sends an email with the outcome.
If the camera is unavailable it sends a notification email as well.

This script uses PuTTY (actually the plink.exe file from PuTTY). Download PuTTY from https://www.putty.org/
This script is tested on Windows Server 2016.
Run this script using Task Scheduler.

1. Set the camera info ($global:cameraConfig)
   name           whatever text string to identify the camera
   IP address     accessible IP address of the camera
   ssh user id    default ubnt
   ssh password   default ubnt

2. Set the email recipients ($global:emailRecipients

3. Set the smtp server ($global:emailSmtpServer

4. Configure the mail-from ($global:emailFrom)
   Whatever your mailserver acceps
   
5. Define the Unifi cam youtube list streaming command ($global:listConfigCommand)
    echo listConfig | nc 127.0.0.1 1112 -w 1 -i 1"
    
6. Define the Unifi cam youtube start stream command ($global:startStreamCommand)
    echo pushStream uri=rtmp://a.rtmp.youtube.com/live2/ localstreamname=s0 targetStreamName=YOURSTREAMID forceTcp=true | nc 127.0.0.1 1112 -w 1 -i 1"
    NOTE: use your stream ID rather than YOURSTREAMID

7. Define the location of PuTTY (global:plinkPath)
   Use short notation (no spaces), i.e. "C:\PROGRA~1\PuTTY\plink.exe"

The scrips uses an ini file to store previous availability, to prevent email to be send every time the watchdog runs. 
This ini file default has the same name as the script with a different extension.


#### Task Scheduler ####
Schedule the Watchdog as a Task in Task Scheduler
My settings in Windows Server 2016: 

##### Tab: General #####
  Name: Webcam Youtube Watchdog  
  Description: [...]  
  Select: Run whether the user is logged in or not  
  Uncheck: Do not store password. This task will only have access to local computer resources.  
  Configure for: Windows Server 2016  
##### Tab: Triggers (1 trigger) ##### 
  Begin the task: On a schedule  
  Settings: Daily, Start 23-2-2019 (in the past), 00:00:41 (slightly after midnight). Recur every: 1 days  
  Select: Repeat task every: 5 minutes for a duration of Indefinitely  
  Select: Stop task if it runs longer than: 30 minutes   
  Select: Enabled  
##### Tab: Actions (1 action) ##### 
  Action: Start a program  
  Program/script: Powershell.exe (no path required)  
  Add arguments: -ExecutionPolicy Bypass <PATHTOSCRIPT>   
  Start-in (optional): (should not be required, no relative paths in script)  
##### Tab: Conditions ##### 
  Script only started on AC power, stopped on battery power  
##### Tab: Settings ##### 
  Select: Allow task to be run on demand  
  Select: Run task as soon as possible after a scheduled start is missed   
  Select: if the task fails, restart every 1 minute. Attempt to restart up to: 3 times  
  Select: stop the task if it runs longer than: 1 hour (task should not run for more than 1 minute, regular 20 seconds)  
  Select: If the running task does not end when requested, force it to stop  
  If the task is already running, then the following rule applies: Do not start a new instance  
