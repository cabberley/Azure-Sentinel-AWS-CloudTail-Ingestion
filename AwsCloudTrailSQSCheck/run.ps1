<#  
    Title:          Azure Sentinel Log Ingestion - Process AWS SQS Queue Messages specificly for CLoudTrail
    Language:       PowerShell
    Version:        1.0.0
    Author(s):      Microsoft - Chris Abberley
    Last Modified:  2020-08-26
    Comment:        Inital Build


    DESCRIPTION
    This function checks the AWS SQS queue for CloudTrail Specific messages for logs to be processed.
    Then puts a message on the log processing queue.
      
    NOTES
    Please read and understand the documents for the entire collection and ingestion process, there are numerous dependancies on Azure Function Settings, Powershell modules and Storage tables, queues & Blobs 

    AWS Credentials: The simplist way to configure is to generate locally a .AWS directory using AWS CLI or AWS PowerShell commandlets, then upload it to your Azure Function Shared File System into the root of the folder.

    CHANGE HISTORY
    1.0.0
    Inital release of code
#>

# Input bindings are passed in via param block.
# Input bindings are passed in via param block.
param([string] $QueueItem, $TriggerMetadata)
# Get the current universal time in the default string format.
$startUTCtime = (Get-Date).ToUniversalTime()
$QueueItems = $QueueItem.split(';')
$AWSSQSQueueName = $QueueItems[0]
$AWSRegion = $QueueItems[1]
$AWSprofileSQS = $QueueItems[2]
$AwsProfileS3 = $QueueItems[3]

#param([string] $QueueItem, $TriggerMetadata)
$Telemetry = @{}
$telemetry += @{'Starttime' = $startUTCtime }
$Telemetry += @{"Event" = "TimerTrigger"}
$Telemetry += @{'AzureFunction' = 'AWSSQSCloudQueueTrigger' }
$Telemetry += @{'FunctionVersion' = '1.0.0' }
#####Environment Variables
$AzureWebJobsStorage = $env:AzureWebJobsStorage     # This is a standard Azure Function Setting 
$AzureQueueName = $env:AzureCloudTrailQueueName     # This is the name of the Azure Storage Queue that will be used to tell the ingestion function what to do
$SQSCloudTrailQueue = $env:SQSCloudTrailQueueName 
$TelemetryId = $env:TelemetryWorkspace              # This is the Telemetry Log Analytics Workspace fort logging this function
$TelemetryKey = $env:TelemetryWorkspaceKey


#####script local variables
$AWSQueueCount = 10
$EndAWSSQSMessages = $false
$counterMessages = 0
$TelemetryTable = 'AwsCloudTrailQueueLogs'          # name of the custom table in the telemetry Log Ananlytics workspace to put the function logs

#Import Modules Required
Import-Module AWS.Tools.common                      # Make sure you use Requirements file of the Azure FUnction to get the PowershellGallery Modules requried 
Import-Module AWS.Tools.SQS

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
$TelemetryVars += 'AwsQueueName: ' + $AWSSQSQueueName 
$telemetryVars += 'AWSQueueMaxRetrieve: ' + $AWSQueueCount
$TelemetryVars += 'AwsRegion: ' + $AWSRegion 
$TelemetryVars += 'AwsProfileName' + $AWSProfileName 
$Telemetry += @{'PowerShellModulesLoaded' = $m }
$Telemetry += @{'ScriptVariables' = $telemetryVars }
Remove-Variable -name m
remove-variable -Name telemetryVars
Remove-variable -Name AZStorageName

#connect to storage
$AzureStorage = New-AzStorageContext -ConnectionString $AzureWebJobsStorage

#we need to connect to the Azure Storage Queue to remove the message
$AzureQueue1 = Get-AzStorageQueue -Name $SQSCloudTrailQueue -Context $AzureStorage
$Null = $AzureQueue1.CloudQueue.DeleteMessageAsync($TriggerMetadata.Id, $TriggerMetadata.popReceipt)

#Connect and setup Azure Message Queue for inserting files to be processed
$AzureQueue = Get-AzStorageQueue -Name $AzureQueueName -Context $AzureStorage

#####Authenticate and generate AWS Credentials
$AWSCredentials = Get-AWSCredential -ProfileName $AWSprofileSQS

$Telemetry.Event = 'QueueProcessed' 

#Connect to AWS SQS Queue
$TelemetrySQS = @()
DO {
    $AWSSQSMessages = Receive-SQSMessage -QueueUrl $AWSSQSQueueName -MessageCount $AWSQueueCount -MessageAttributeName All -Credential $AWSCredentials -Region $AWSRegion 
    if ($AWSSQSMessages.count -eq 0) { $EndAWSSQSMessages = $true }
    $counterMessages += $AWSSQSMessages.count
    
    foreach ($AWSSQSMessage in $AWSSQSMessages) {
        if ($AWSSQSMessage) {
            $AWSSQSReceiptHandle = $AWSSQSMessage.ReceiptHandle
            if ((((ConvertFrom-Json -InputObject $AWSSQSMessage.Body)).Records[0].eventName) -clike 'ObjectCreated*') {
                $AWSs3ObjectSize = ((ConvertFrom-Json -InputObject $AWSSQSMessage.Body)).Records[0].s3.object.size
                $AWSs3BucketName = ((ConvertFrom-Json -InputObject $AWSSQSMessage.Body)).Records[0].s3.bucket.name
                $AWSs3ObjectName = ((ConvertFrom-Json -InputObject $AWSSQSMessage.Body)).Records[0].s3.object.key
                if ($AWSs3ObjectSize -gt 0 -and ($AWSs3ObjectName.indexof('Digest')) -eq -1) {
                    $TelemetrySQS += 'AWSMessageID: ' + $AWSSQSMessage.MessageId + ' s3Bucket: ' + $AWSs3BucketName + ' AWSObjectName: ' + $AWSs3ObjectName 
                    $AzureQmessage = $AWSs3BucketName + ';' + $AWSs3ObjectName  + ';' + $AWSRegion  + ';' + $AwsProfileS3
                    $AzureQmessage = [Microsoft.Azure.Storage.Queue.CloudQueueMessage]::new($AzureQmessage)
                    $null = $AzureQueue.CloudQueue.AddMessageAsync($AzureQMessage, $null, 0, $null, $null)
                }
                elseif (($AWSs3ObjectName.indexof('Digest')) -eq -1) {
                    $TelemetrySQS += 'AWSMessageID: ' + $AWSSQSMessage.MessageId + ' Rejected: Was a Digest File'
                }
                Else{
                    $TelemetrySQS += 'AWSMessageID: ' + $AWSSQSMessage.MessageId + ' Rejected: File was Zero byte file'
                }
           }
           else{
                $TelemetrySQS += 'AWSMessageID: ' + $AWSSQSMessage.MessageId + ' Rejected: Was not an ObjectedCreated Event'
           }
        }
        $null = Remove-SQSMessage -QueueUrl $AWSSQSQueueName -ReceiptHandle $awsSQSReceiptHandle -Force -Credential $AWSCredentials -Region $AWSRegion  #USE SQS Creds
    }
    #check on time running, Azure Function default timeout is 5 minutes, if we are getting close exit function cleanly now and get more records next execution
    $currentUTCtime = (Get-Date).ToUniversalTime()
    $Diff = NEW-TIMESPAN -Start $startUTCtime -End $currentUTCtime
    If ($Diff.TotalSeconds -gt 270) { $EndAWSSQSMessages = $true}
}until ($EndAWSSQSMessages)
$Telemetry += @{"MessageDetails" = $TelemetrySQS}
$Telemetry += @{"AwsMessagesProcessed" = $counterMessages}
$CompleteDate = (Get-Date).ToUniversalTime()
$CompleteDate = $CompleteDate.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
$Telemetry += @{"TimeCompleted" = $CompleteDate }

# Code below is to post telemetry Logs, it is not required by Function

#function to create HTTP Header signature required to authenticate post
Function New-BuildSignature {
    param(
        $customerId, 
        $sharedKey, 
        $date, 
        $contentLength, 
        $method, 
        $contentType, 
        $resource )
    
    $xHeaders = "x-ms-date:" + $date
    $stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + $xHeaders + "`n" + $resource
    $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes = [Convert]::FromBase64String($sharedKey)
    $sha256 = New-Object System.Security.Cryptography.HMACSHA256
    $sha256.Key = $keyBytes
    $calculatedHash = $sha256.ComputeHash($bytesToHash)
    $encodedHash = [Convert]::ToBase64String($calculatedHash)
    $authorization = 'SharedKey {0}:{1}' -f $customerId, $encodedHash
    return $authorization
}
        
# Function to create and post the request
Function Invoke-LogAnalyticsData {
    Param( 
        $CustomerId, 
        $SharedKey, 
        $Body, 
        $LogTable, 
        $TimeStampField,
        $resourceId)

    $method = "POST"
    $contentType = "application/json"
    $resource = "/api/logs"
    $rfc1123date = [DateTime]::UtcNow.ToString("r")
    $contentLength = $Body.Length
    $signature = New-BuildSignature `
        -customerId $CustomerId `
        -sharedKey $SharedKey `
        -date $rfc1123date `
        -contentLength $contentLength `
        -method $method `
        -contentType $contentType `
        -resource $resource
    $uri = "https://" + $CustomerId + ".ods.opinsights.azure.com" + $resource + "?api-version=2016-04-01"
    $headers1 = @{
        "Authorization"        = $signature;
        "Log-Type"             = $LogTable;
        "x-ms-date"            = $rfc1123date;
        "x-ms-AzureResourceId" = $resourceId;
        "time-generated-field" = $TimeStampField;
    }  
    $status = $false
    do {
        $response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $headers1 -Body $Body
        If ($reponse.StatusCode -eq 429) {
            $rand = get-random -minimum 10 -Maximum 80
            start-sleep -seconds $rand 
        }
        else { $status = $true }
    }until($status) 
    Remove-variable -name body
    return $response.StatusCode
    
} 

$null = Invoke-LogAnalyticsData -CustomerId $TelemetryId -SharedKey $TelemetryKey -Body (ConvertTo-Json $Telemetry -Depth 10) -LogTable $TelemetryTable -TimeStampField '' -ResourceId ''
