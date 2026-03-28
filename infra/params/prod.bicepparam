using '../main.bicep'

param location = 'eastus'
param prefix = 'mb-idp'
param environment = 'prod'

param tags = {
  owner: 'mahesh'
  project: 'project1-idp'
  env: 'prod'
}

// Images are overridden by pipelines at deploy time.
param apiImage = 'override-at-deploy'
param pipelineImage = 'override-at-deploy'

param cosmosDatabaseName = 'idp'
param cosmosContainerName = 'documents'
param cosmosPartitionKeyPath = '/partitionKey'
param cosmosFreeTier = false
param cosmosConsistencyLevel = 'Session'

param documentIntelligenceModelId = 'prebuilt-document'

param azureOpenAIApiVersion = '2024-06-01'
param azureOpenAIDeploymentName = 'gpt-4o'
param azureOpenAIModelName = 'gpt-4o'
param azureOpenAIModelVersion = '2024-08-06'
// Often created manually in prod if access policies require it.
param createAzureOpenAIDeployment = true

