# Azure Sentinel AWS CloudTail Ingestion
 
Azure Function Application settings required
1. AzureCloudTrailQueueName  - Name of the queue on your local Azure Function Storage Account default name - 'awscloudqueue'
2. SQSCloudTrailQueueName - Name of the Azure Storage queue with the list of SQS queues to check default name - 'sqsqueues'
3. TelemetryWorkspace - Log Ananlytics workspace for storing telemetry\logs of the azure function
4. TelemetryWorkspaceKey
5. WorkspaceID - Azure Sentinel Log Analytics workspace details
6. WorkspaceKey
7. SQSConfig = Name of the AzureStorage Table to read the SQS configs from, default name 'cloudtrailconfigs'
8. 

Create a directory on the Azure Function Azure File Share 'D:\home\data\Cloudtrailworking'

Create a Storage Table Called 'cloudtrailconfigs'
Sample table. Field Names MUST keep Capitalisation exactly as below:
PartitionKey,RowKey,sqsQueueName,AwsRegion,AwsProfileSQS,AwsProfileS3
Partition1,Config1,https://sqs.ap-southeast-1.amazonaws.com/999999999999/cloudtrail-001-queue,ap-southeast-1,myprofile1,myprofile1
Partition1,Config2,https://sqs.ap-southeast-1.amazonaws.com/999999999999/cloudtrail-002-queue,us-west-1,myprofile1,myprofile4
Partition1,Config2,https://sqs.ap-southeast-1.amazonaws.com/999999000000/cloudtrail-001-queue,us-west-1,myprofile2,myprofile2

Create 2 storage queues on the loca Storage Account
1. 'sqsqueues'
2. 'awscloudqueue'
