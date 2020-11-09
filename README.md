# AWS CloudTail Ingestion configuration steps
 
1. Create a directory on the Azure Function File Share D:\home\data\Cloudtrailworking

2. Create a directory on the Azure Function File Share D:\home\\.aws and create file called 'credentials' and add AWS Credentials
	```
	[myprofile1]
	aws_access_key_id = <<AWS Access Key>>
	aws_secret_access_key = <<AWS Secret AccessKey>>
	
	[myprofile2]
	aws_access_key_id = <<AWS Access Key>>
	aws_secret_access_key = <<AWS Secret AccessKey>>
	```
	Note: Steps 1 & 2 can be created by using Azure Storage explorer/Kudu to the root of the Azure function file share
	Note: If you are using AWS Assumed Roles you will also need to create a 'config' file in the .aws directory as well.

3. Go to Storage Table 'cloudtrailconfigs' and add the following columns/properties using Azure Storage explorer
   Field Names MUST keep Capitalisation exactly as below:
   ```
   sqsQueueName
   AwsRegion
   AwsProfileSQS
   AwsProfileS3
   ```
	
	| PartitionKey | RowKey  |                             sqsQueueName                                   | AwsRegion | AwsProfileSQS | AwsProfileS3 |
    |--------------|---------|----------------------------------------------------------------------------|-----------|---------------|--------------|
	| Partition1   | Config1 | https://sqs.ap-southeast-1.amazonaws.com/999999999999/cloudtrail-001-queue | us-east-2 | myprofile1    | myprofile1   |
	| Partition1   | Config2 | https://sqs.ap-southeast-1.amazonaws.com/999999999999/cloudtrail-001-queue | us-east-2 | myprofile2    | myprofile2   |
	| Partition1   | Config3 | https://sqs.ap-southeast-1.amazonaws.com/999999999999/cloudtrail-001-queue | us-east-2 | myprofile3    | myprofile3   |

## Deploy Function App
<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fandedevsecops%2FAzure-Sentinel%2Faz-func-validation%2FDataConnectors%2FValidateDeployment%2Fazuredeploy_aws_s3_ingestion.json" target="_blank">
    <img src="https://aka.ms/deploytoazurebutton"/>
</a>
