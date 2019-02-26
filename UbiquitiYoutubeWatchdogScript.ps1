<# 
   IP Camera Watchdog script
   Frans Laemen, 25 feb 2019, v2
    Version history: v1 22 feb 2019
                        detect reachable webcam
                        detect number of running streams
                        start stream if no stream running
                        email when a stream is started
                     v2 25 feb 2019
                        email when webcam becomes unreachable
                     v2.1 26 feb 2019
                        Refactor function call structure.
   For NPCT
#>

# DEBUG - writes stdout to file, to use then debugging Task Scheduler
#Start-Transcript -Path "C:\Users\a-flaemen\Documents\pslog.txt" -Append

# -- Camera configuration parameters
#    Format: name - ip - username - password
$global:cameraConfig = @(
    ,@("Webcam 1 name", "X.X.X.X", "ubnt", "ubnt")
    ,@("Webcam 2 name", "X.X.X.X", "ubnt", "ubnt")
    ,@("Webcam 3 name", "X.X.X.X", "ubnt", "ubnt")
)

# -- e-mail recipients for status mail on unreachable or recovered webcams
$global:emailRecipients = @("Name 1 <user@domain.nl>", "Name 2 <user@domain.com>")
$global:emailSmtpServer = 'smtp.server.hostname'
$global:emailFrom = "Webcam Youtube Watchdog <camera-watchdog@domain.com>" 

#global: The Unifi G3 Dome cam youtube streaming commands
$global:listConfigCommand = "echo listConfig | nc 127.0.0.1 1112 -w 1 -i 1"
$global:startStreamCommand = "echo pushStream uri=rtmp://a.rtmp.youtube.com/live2/ localstreamname=s0 targetStreamName=YOURSTREAMID forceTcp=true | nc 127.0.0.1 1112 -w 1 -i 1"

# The lcoation of PuTTY. Needs to be in short form (no spaces)
$global:plinkPath = "C:\PROGRA~1\PuTTY\plink.exe"   # C:\Program Files\PuTTY\plink.exe
# The ini file stores the status (auto generated). This is the script name with .ini extension
$global:IniFile = ( $PSCommandPath.Substring(0, $PSCommandPath.Length - 4) + ".ini" )


# --- Functions

#--  Get-IniFile function code source by David Brabant: 
#    https://stackoverflow.com/questions/43690336/powershell-to-read-single-value-from-simple-ini-file
function Get-IniFile {  
    param(  
        [parameter(Mandatory = $true)] [string] $filePath  
    )

    $anonymous = "NoSection"
    $ini = @{}  
    switch -regex -file $filePath {
        # Section  
        "^\[(.+)\]$" {
            $section = $matches[1]  
            $ini[$section] = @{}  
            $CommentCount = 0  
        }  
        # Comment  
        "^(;.*)$" {  
            if (!($section)) {  
                $section = $anonymous  
                $ini[$section] = @{}  
            }  
            $value = $matches[1]  
            $CommentCount = $CommentCount + 1  
            $name = "Comment" + $CommentCount  
            $ini[$section][$name] = $value  
        }   
        # key
        "(.+?)\s*=\s*(.*)" {  
            if (!($section)) {  
                $section = $anonymous  
                $ini[$section] = @{}  
            }  
            $name,$value = $matches[1..2]  
            $ini[$section][$name] = $value  
        }  
    }
    return $ini  
}  


Function Exec-SSH {
    param(  
        [parameter(Mandatory=$true, Position=0)] [string] $plinkPath,
        [parameter(Mandatory=$true, Position=1)] [string] $remoteHost,
        [parameter(Mandatory=$true, Position=2)] [string] $user,
        [parameter(Mandatory=$true, Position=3)] [string] $password,
        [parameter(Mandatory=$true, Position=4)] [string] $remoteCommand  
    )
    [OutputType([String])]

    $localCommand = "$plinkPath $remoteHost -l $user -pw $password `"$remoteCommand`""
    # DEBUG:  Write-Host " localCommand: $localCommand"
    [string]$rawResult = Invoke-Expression($localCommand)

    $rawResult = $rawResult -replace '\u0000', '' # remove leading NULL
    $rawResult = $rawResult -replace '\u0003', '' # remove leading TAB
    $rawResult = $rawResult.Trim()                # remove leading / trailing spaces
    $rawResult = $rawResult.Substring($rawResult.IndexOf('{'), $rawResult.Length - $rawResult.IndexOf('{'))
    return $rawResult
}


Function Get-StreamCount {
    param(  
        [parameter(Mandatory=$true, Position=0)] [string] $rawResult  
    )
    [OutputType([int])]

    $jsonResult = ConvertFrom-Json -InputObject $rawResult
    # Number of active streams in Push object
    [int]$count = $jsonResult.data.push.Count 
    Write-Host " Number of active streams: ($count)"
    return $count
}



# --- Do the monitoring
Function Run-IPCamWatchdog {
    param(  
        [parameter(Mandatory=$true, Position=0)] [string] $cameraName,
        [parameter(Mandatory=$true, Position=1)] [string] $cameraIP,
        [parameter(Mandatory=$true, Position=2)] [string] $cameraUser,
        [parameter(Mandatory=$true, Position=3)] [string] $cameraPassword
    )

    # 1. Test if the IP Camera can be connected
	$global:iniObj[$($cameraIP)]["lastchecked"] = Get-Date
    if (Test-Connection -computername $cameraIP -Quiet -Count 1) {
        # Succeeded
	    if ( $($global:iniObj[$($cameraIP)]["status"]) -ne “available” ) {
    		# This camera just became available again!
            Write-Host " $cameraName (ip:$cameraIP) became newly available on the network."
	    	$global:iniObj[$($cameraIP)]["status"] = “available”
		    $global:iniObj[$($cameraIP)]["lastchanged"] = Get-Date
        } else {
            Write-Host " $cameraName (ip:$cameraIP) is available on the network."
        }
    } else {
        # Failed! Check if this was already reported 
	    if ( $($global:iniObj[$($cameraIP)]["status"]) -ne “unavailable” ) {
    		# This camera just became unavailable
            Write-Host "  Connection to `"$cameraName`" (ip:$cameraIP) failed! `"$cameraName`" has become unavailable on the network. Sending notification email."
	    	$global:iniObj[$($cameraIP)]["status"] = “unavailable”
		    $global:iniObj[$($cameraIP)]["lastchanged"] = Get-Date

		    # Send an email on detecting a camera down. (email is only sent once on detection)
            Send-MailMessage -From "webcam-watchdog@paracentrumteuge.nl" -To $emailRecipients -Subject “Camera `"$cameraName`" became unavailable” -Body “Camera `"$cameraName`" (ip:$cameraIP) became unavailable on the network (down)!`n" -Priority High -SmtpServer $emailSmtpServer  
        } else {
            Write-Host " Connection to $cameraName (ip:$cameraIP) still unavailable."
        }
        Write-Host " Watchdog for $cameraName done."
        return
    }

    # 2. Get the number of active streams
    $rawResult = Exec-SSH $plinkPath $cameraIP $cameraUser $cameraPassword $listConfigCommand
    $streamCount = Get-StreamCount $rawResult

    # 3. If the number of active streams is zero, start the streams
    if ( $streamCount -lt 1 ) {
        # No stream running, start stream
        Write-Host " Stream for $cameraName not started. Startings stream..."
        $rawResult = Exec-SSH $plinkPath $cameraIP $cameraUser $cameraPassword $startStreamCommand

        # Send an email to inform the camera-stream is brought back up
        Write-Host "Sending email to $emailRecipients"
        Send-MailMessage -From "webcam-watchdog@paracentrumteuge.nl" -To $emailRecipients -Subject "Youtube stream started on `"$cameraName`"" -Body "Youtube stream started on camera `"$cameraName`" (ip:$cameraIP)`n`n$rawResult" -Priority High -SmtpServer $emailSmtpServer  
    } else {
        # There is a stream running, no further action required
        Write-Host " Stream for $cameraName is running."
    }
    Write-Host " Watchdog for $cameraName done."
 }

# — Read the previous status from the ini file, if present
Function Read-Init {
	param(  
		[parameter(Mandatory=$true, Position=0)] [string] $IniFilePath,
		[parameter(Mandatory=$true, Position=1)] $cameraConfig # Collection
	)
	[OutputType([string])]

	$iniObj = @{}
	try {
		$iniObj = Get-IniFile $IniFilePath
	} Catch [System.Management.Automation.ItemNotFoundException] {
		Write-Host "Path $($_.TargetObject) not found!" -ForegroundColor red
	} Catch {
		Write-Host "Unknown error reading $($_.TargetObject)!" -ForegroundColor red
	}
	# If no file was found or no content was present, build the Collection of DictionaryEntries from scratch 
	if (!($iniObj)) { 
		$iniObj = @{} 
	}
	foreach ($camera in $cameraConfig) {
		# Check if the ini has this entry
		if (!$($iniObj[$($camera[1])]))                	{ $iniObj[$($camera[1])]               		= @{}          	}
		if (!$($iniObj[$($camera[1])]["status"]))      	{ $iniObj[$($camera[1])]["status"]      	= "undefined"	}
		if (!$($iniObj[$($camera[1])]["lastchecked"])) 	{ $iniObj[$($camera[1])]["lastchecked"] 	= "undefined" 	}
		if (!$($iniObj[$($camera[1])]["lastchanged"])) 	{ $iniObj[$($camera[1])]["lastchanged"] 	= "undefined" 	}
	}
	return $iniObj
}

# — Write the new status of the configured cameras to the ini file (overwrite existing)
Function Write-Init {
	param(  
		[parameter(Mandatory=$true, Position=0)] [string] $IniFilePath,
		[parameter(Mandatory=$true, Position=1)] $cameraConfig # Collection
	)

	$iniOutTxt = “; NOTE: This is an automatically generated status file`n; generated by the Webcam Youtube Watchdog script`n; Any changes will be overwritten`n`n”
	foreach ($camera in $cameraConfig) {
		$iniOutTxt = ( $($iniOutTxt) + "[" + $($camera[1]) + "]`n” )
		$iniOutTxt = ( $($iniOutTxt) + "; " + $($camera[0]) + "`n” )
		$iniOutTxt = ( $($iniOutTxt) + "status=" + $($iniObj[$($camera[1])]["status"]) + "`n”)
		$iniOutTxt = ( $($iniOutTxt) + "lastchecked=" + $($iniObj[$($camera[1])]["lastchecked"]) + "`n”)
		$iniOutTxt = ( $($iniOutTxt) + "lastchanged=" + $($iniObj[$($camera[1])]["lastchanged"]) + "`n`n”)
	}
	# Write to file
	Set-Content -Path $IniFilePath -Value $iniOutTxt -Force
}




# — Read the previous status from the ini file 
$global:iniObj = Read-Init $global:iniFile $global:cameraConfig

# -- Run the watchdog for each configured camera
foreach ($camera in $cameraConfig) {
	Write-Host ( "Watchdog checking `"" + $camera[0] + "`"..." )
	# Check if the ini has this entry
	Run-IPCamWatchdog $camera[0] $camera[1] $camera[2] $camera[3]
}

# — Read the previous status from the ini file 
Write-Init $global:iniFile $global:cameraConfig



# DEBUG - writes stdout to file, to use then debugging Task Scheduler
#Stop-Transcripts