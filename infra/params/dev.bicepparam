using '../main.bicep'

param location = 'eastus'
param prefix = 'mb-idp'
param environment = 'dev'

param tags = {
  owner: 'mahesh'
  project: 'project1-idp'
  env: 'dev'
}

// Images are overridden by pipelines at deploy time.
param apiImage = 'override-at-deploy'
param pipelineImage = 'override-at-deploy'

param cosmosDatabaseName = 'idp'
param cosmosContainerName = 'documents'
param cosmosPartitionKeyPath = '/partitionKey'
param cosmosFreeTier = true
param cosmosConsistencyLevel = 'Session'

param documentIntelligenceModelId = 'prebuilt-document'

param azureOpenAIApiVersion = '2024-06-01'
param azureOpenAIDeploymentName = 'gpt-4o'
param azureOpenAIModelName = 'gpt-4o'
param azureOpenAIModelVersion = '2024-08-06'
param createAzureOpenAIDeployment = true

