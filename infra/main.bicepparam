using './main.bicep'

param location = 'eastus'
param prefix = 'mb-idp'
param environment = 'dev'

param tags = {
  owner: 'mahesh'
  project: 'project1-idp'
}

// NOTE: set these to images you build + push (ACR/Docker Hub/GHCR).
param apiImage = 'myacr.azurecr.io/project1-api:1.0.0'
param pipelineImage = 'myacr.azurecr.io/project1-idp-pipeline:1.0.0'

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

