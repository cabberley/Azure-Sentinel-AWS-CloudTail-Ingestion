<#  
    Title:          Azure Sentinel Log Ingestion - Process AWS cloudtrail Direct Queue Messages
    Language:       PowerShell
    Version:        1.0.0
    Author(s):      Microsoft - Chris Abberley
    Last Modified:  2020-08-26
    Comment:        Inital Build


    DESCRIPTION
    This function monitors an Azure Storage queue for messages with an s3 Bucket name and Key then retrieves the file and preps it for Ingestion processing.
      
    NOTES
    Please read and understand the documents for the entire collection and ingestion process, there are numerous dependancies on Azure Function Settings, Powershell modules and Storage tables, queues & Blobs 

    CHANGE HISTORY
    1.0.0
    Inital release of code
#>

# Input bindings are passed in via param block.
param([string] $QueueItem, $TriggerMetadata)
# Get the current universal time in the default string format.
$currentUTCtime = (Get-Date).ToUniversalTime()
$QueueItems = $QueueItem.split(';')
$s3Bucket = $QueueItems[0]
$key = $QueueItems[1]
$Region = $QueueItems[2]
$AwsProfile = $QueueItems[3]

$Telemetry = @{}
$Telemetry += @{'Event' = 'QueueTrigger' }
$Telemetry += @{'AzureFunction' = 'AwsCloudTrailS3' }
$Telemetry += @{'FunctionVersion' = '4.0.0' }
$Telemetry += @{'TriggerMetaData' = $TriggerMetadata }

#Message format structure to pull apart
$Telemetry += @{'StartTime' = $currentUTCtime }

#Import Modules Required
Import-Module AWS.Tools.common
Import-Module AWS.Tools.S3


#####Environment Variables
$AzureWebJobsStorage = $env:AzureWebJobsStorage  
$AzureQueueName = $env:AzureCloudTrailQueueName
$TelemetryId = $env:TelemetryWorkspace
$TelemetryKey = $env:TelemetryWorkspaceKey
$WorkspaceId = $env:WorkspaceID
$Workspacekey = $env:WorkspaceKey


#PoC Override Environment settings for testing
#$WorkspaceId = '<workspaceID>'  #$env:WorkspaceId
#$Workspacekey = '<workspaceKey>'   #$env:WorkspaceKey
#$TelemetryId = '<workspaceID>'  #$env:WorkspaceId
#$TelemetryKey = '<workspaceKey>'   #$env:WorkspaceKey
#$awsprofile = '<Awsprofilename>'

#####script local variables
$LocalWorkDir = 'D:\home\data\Cloudtrailworking'  #Azure Function Shared home Directory across any instances spun up.
$TelemetryTable = 'AwsCloudTrailLogIngestion'
$LATableName = 'AwsCloudTrail' #

$ResourceID = ''  #Azure ResourceGroup property if you require row level security
#The $eventobjectlist is the Json Parameter field names that form the core of the Json message that we want in the ALL Table in Log Ananlytics
$eventobjectlist = @('eventTime', 'eventVersion', 'userIdentity', 'eventSource', 'eventName', 'awsRegion', 'sourceIPAddress', 'userAgent', 'errorCode', 'errorMessage', 'requestID', 'eventID', 'eventType', 'apiVersion', 'managementEvent', 'readOnly', 'resources', 'recipientAccountId', 'serviceEventDetails', 'sharedEventID', 'vpcEndpointId', 'eventCategory', 'additionalEventData')


#Add PowerShell Modules to Telemetry Records
$TelemetryPsModules = Get-Module
$m = @()
Foreach ($mod in $TelemetryPsModules) {
    $version = $mod.Version.ToString()
    $m += "PsModuleName: $mod.Name, PsModuleVersion: $version"
}
$AZStorageName = ((($AzureWebJobsStorage -Split (';'))[1]) -Split ('='))[1]
$telemetryVars = @()
$telemetryVars += 'AzureWebJobsStorage: ' + $AZStorageName
$telemetryVars += 'AzureQueueName: ' + $AzureQueueName
$telemetryVars += 'LogFileWorkingDirectory: ' + $LocalWorkDir
$telemetryVars += 'AwsRegion: ' + $AWSRegion
$Telemetry += @{'PowerShellModulesLoaded' = $m }
$Telemetry += @{'ScriptVariables' = $telemetryVars }
$Telemetry += @{'FileCopyFolder' = $LocalWorkDir }
$null = Remove-Variable -name m
$null = Remove-Variable -name telemetryVars
$null = Remove-Variable -Name TelemetryPsModules
$null = Remove-Variable -Name AZStorageName

Function Expand-GZipFile {
    Param(
        $infile,
        $outfile       
    )

    $inputfile = New-Object System.IO.FileStream $inFile, ([IO.FileMode]::Open), ([IO.FileAccess]::Read), ([IO.FileShare]::Read)
    $output = New-Object System.IO.FileStream $outFile, ([IO.FileMode]::Create), ([IO.FileAccess]::Write), ([IO.FileShare]::None)
    $gzipStream = New-Object System.IO.Compression.GzipStream $inputfile, ([IO.Compression.CompressionMode]::Decompress)

    $buffer = New-Object byte[](1024)
    while ($true) {
        $read = $gzipstream.Read($buffer, 0, 1024)
        if ($read -le 0) { break }
        $output.Write($buffer, 0, $read)
    }

    $gzipStream.Close()
    $output.Close()
    $inputfile.Close()
}

IF ($Null -ne $s3Bucket -and $Null -ne $key -and $null -ne $AwsProfile -and $null -ne $Region) {
    $AWSCredentialsS3 = Get-AWSCredential -ProfileName $AWSProfile
    $Telemetry += @{'AwsCredentialsS3' = $AWSProfile }
    $Telemetry += @{'AwsRegion: ' = $Region }
    $Telemetry += @{'s3Bucket' = $s3Bucket }
    $Telemetry += @{'s3KeyPath' = $key }
    $s3KeyPath = $key -Replace ('%3A', ':')
    $fileNameSplit = $s3KeyPath.split('/')
    $fileSplits = $fileNameSplit.Length - 1
    $fileName = $filenameSplit[$fileSplits].replace(':', '_')
    $result = Copy-S3Object -BucketName $s3Bucket -Key $key -LocalFile "$LocalWorkDir\$filename" -Credential $AWSCredentialsS3 -Region ap-southeast-1 -ErrorAction SilentlyContinue #use s3 creds to collect
    #check if file is compressed and decompress based on file extension
    if ($result.Extension -eq '.gz' ) {
        $null = 
        $infile = "$LocalWorkDir\$fileName"
        $outfile = "$LocalWorkDir\" + $fileName -replace ($result.Extension, '') #"d:\empty\"
        Expand-GZipFile $infile $outfile
        $null = Remove-Item -Path "$LocalWorkDir\$filename" -Force -Recurse -ErrorAction Ignore
        $filename = $filename -replace ($result.Extension, '')
        $Telemetry += @{'DecompressFile' = 'True File Extn: ' + $result.Extension }
        $Telemetry += @{'DecompressFileName' = $filename }
    }
    else {
        $Telemetry += @{'DecompressFile' = 'False' }
    }
    $logEvents = Get-Content -Raw -LiteralPath ("$LocalWorkDir\$filename" ) 
    $logEvents = $LogEvents.Substring(0, ($LogEvents.length) - 1)
    $LogEvents = $LogEvents -Replace ('{"Records":', '')
    $loglength = $logEvents.Length
    $Telemetry += @{'HttpBodySize' = $LogLength }
    $logevents = Convertfrom-json $LogEvents -AsHashTable
    $groupevents = @{}
    $coreEvents = @()
    $eventSources = @()
    Foreach ($log in $logevents) {
        $Logdetails = @{}
        $Logdetails1 = @{}
        $b = ((($log.eventSource).split('.'))[0]) -replace ('-', '')
        IF ($b -eq 'ec2') {
            foreach ($col in $eventobjectlist) {
                $logdetails1 += @{$col = $log.$col }
            }
            $ec2Header = $b + '_Header'
            IF ($null -eq $groupevents[$ec2Header]) {
                Add-Member -inputobject $groupevents -Name $b -MemberType NoteProperty -value @() -Force
                $groupevents[$ec2Header] = @()
                $eventSources += $ec2Header
            }
            $groupevents[$ec2Header] += $Logdetails1
            $Ec2Request = $b + '_Request'
            IF ($null -eq $groupevents[$Ec2Request]) {
                Add-Member -inputobject $groupevents -Name $Ec2Request -MemberType NoteProperty -value @() -Force
                $groupevents[$Ec2Request] = @()
                $eventSources += $Ec2Request
            }
            $ec2Events = @{} 
            $ec2Events += @{'eventID' = $log.eventID }
            $ec2Events += @{'awsRegion' = $log.awsRegion }
            $ec2Events += @{'requestID' = $log.requestID }
            $ec2Events += @{'eventTime' = $log.eventTime }
            $ec2Events += @{'requestParameters' = $log.requestParameters }
            $groupevents[$Ec2Request] += $ec2Events
            $Ec2Response = $b + '_Response'
            IF ($null -eq $groupevents[$Ec2Response]) {
                Add-Member -inputobject $groupevents -Name $Ec2Response -MemberType NoteProperty -value @() -Force
                $groupevents[$Ec2Response] = @()
                $eventSources += $Ec2Response
            }
            $ec2Events = @{} 
            $ec2Events += @{'eventID' = $log.eventID }
            $ec2Events += @{'awsRegion' = $log.awsRegion }
            $ec2Events += @{'requestID' = $log.requestID }
            $ec2Events += @{'eventTime' = $log.eventTime }
            $ec2Events += @{'responseElements' = $log.responseElements }
            $groupevents[$Ec2Response] += $ec2Events
        }
        Else {
            IF ($null -eq $groupevents[$b]) {
                Add-Member -inputobject $groupevents -Name $b -MemberType NoteProperty -value @() -Force
                $groupevents[$b] = @()
                $eventSources += $b
            }
            $groupevents[$b] += $log
        }
        foreach ($col in $eventobjectlist) {
            $logdetails += @{$col = $log.$col }
        }
        $coreEvents += $Logdetails
    
    }

    $coreJson = convertto-json $coreevents -depth 5 -Compress
    $Telemetrymulti = @()
    $Table = "$LATablename" + "_All"
    IF (($corejson.Length) -gt 28MB) {
        $telemetrymulti = @()
        #$events = Convertfrom-json $corejson
        $bits = [math]::Round(($corejson.length) / 20MB) + 1
        $TotalRecords = $coreEvents.Count
        $RecSetSize = [math]::Round($TotalRecords / $bits) + 1
        $start = 0
        For ($x = 0; $x -lt $bits; $X++) {
            IF ( ($start + $recsetsize) -gt $TotalRecords) {
                $finish = $totalRecords
            }
            ELSE {
                $finish = $start + $RecSetSize
            }
            $body = Convertto-Json ($coreEvents[$start..$finish]) -Depth 5 -Compress
            $result = Invoke-LogAnalyticsData -CustomerId $WorkspaceId -SharedKey $WorkspaceKey -Body $body -LogTable $Table -TimeStampField 'eventTime' -ResourceId $ResourceID
            $Telemetrymulti += 'Table: ' + $Table + 'HttpResult: ' + $Result + ' recordsposted: ' + $start + ' to ' + $finish + ' HttpBodySize ' + $body.length
            $start = $Finish + 1
        }
        $null = Remove-variable -name body        

    }
    Else {
        #$logEvents = Convertto-Json $events -depth 20 -compress
        $result = Invoke-LogAnalyticsData -CustomerId $WorkspaceId -SharedKey $WorkspaceKey -Body $coreJson -LogTable $Table -TimeStampField 'eventTime' -ResourceId $ResourceID
        $Telemetrymulti += 'Table: ' + $Table + 'HttpResult: ' + $Result + ' recordsposted: ' + $coreevents.count + ' HttpBodySize ' + $corejson.length
    }
    $Telemetry += @{'HttpResultCore' = $telemetrymulti }
    $Telemetry += @{'HttpCoreTotalRecords' = $TotalRecords }
    
    $null = remove-variable -name coreEvents
    $null = remove-variable -name coreJson
    $telemetrymulti = @()
    $RecCount = 0
    foreach ($d in $eventSources) { 
        #$events = $groupevents[$d]
        $eventsJson = ConvertTo-Json $groupevents[$d] -depth 5 -Compress
        $Table = $LATablename + '_' + $d
        $TotalRecords = $groupevents[$d].Count
        $recCount += $TotalRecords
        IF (($eventsjson.Length) -gt 28MB) {
            #$events = Convertfrom-json $corejson
            $bits = [math]::Round(($eventsjson.length) / 20MB) + 1
            $TotalRecords = $groupevents[$d].Count
            $RecSetSize = [math]::Round($TotalRecords / $bits) + 1
            $start = 0
            For ($x = 0; $x -lt $bits; $X++) {
                IF ( ($start + $recsetsize) -gt $TotalRecords) {
                    $finish = $totalRecords
                }
                ELSE {
                    $finish = $start + $RecSetSize
                }
                $body = Convertto-Json ($groupevents[$d][$start..$finish]) -Depth 5 -Compress
                $result = Invoke-LogAnalyticsData -CustomerId $WorkspaceId -SharedKey $WorkspaceKey -Body $body -LogTable $Table -TimeStampField 'eventTime' -ResourceId $ResourceID
                $Telemetrymulti += 'Table: ' + $Table + ' HttpResult: ' + $Result + ' recordsposted: ' + $start + ' to ' + $finish + ' HttpBodySize ' + $body.length
                $start = $Finish + 1
            }
            $null = Remove-variable -name body        
        }
        Else {
            #$logEvents = Convertto-Json $events -depth 20 -compress
            $result = Invoke-LogAnalyticsData -CustomerId $WorkspaceId -SharedKey $WorkspaceKey -Body $eventsJson -LogTable $Table -TimeStampField 'eventTime' -ResourceId $ResourceID
            $Telemetrymulti += 'Table: ' + $Table + ' HttpResult: ' + $Result + ' recordsposted: ' + $TotalRecords + ' HttpBodySize ' + $eventsJson.length
        }
    }
    $Telemetry += @{'HttpResultEvents' = $telemetrymulti }
    $Telemetry += @{'HttpEventsCount' = $RecCount }
    
    $null = Remove-Variable -Name groupevents
    $null = Remove-Variable -Name LogEvents
    $null = Remove-Item -Path "$LocalWorkDir\$filename" -Force -Recurse -ErrorAction Ignore
    
    #we need to connect to the Azure Storage Queue to remove the message if we successfully process the LogFile
    $AzureStorage = New-AzStorageContext -ConnectionString $AzureWebJobsStorage
    $AzureQueue = Get-AzStorageQueue -Name $AzureQueueName -Context $AzureStorage
    $Null = $AzureQueue.CloudQueue.DeleteMessageAsync($TriggerMetadata.Id, $TriggerMetadata.popReceipt)
    #post our telemetry log to the Telemetry Log Ananlytics workspace
    $null = Invoke-LogAnalyticsData -CustomerId $TelemetryId -SharedKey $TelemetryKey -Body (ConvertTo-Json $Telemetry -Depth 5) -LogTable $TelemetryTable -TimeStampField '' -ResourceId '' 
    [System.GC]::collect() #cleanup memory 
}
[System.GC]::GetTotalMemory($true) | out-null #Force full garbage collection - Powershell does not clean itself up properly in some situations 
#end of Script