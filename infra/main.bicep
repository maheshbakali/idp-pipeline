targetScope = 'resourceGroup'

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Resource name prefix (e.g., mb-idp, proj1-idp).')
param prefix string

@description('Environment name (dev/test/prod). Used for naming + tags.')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string = 'dev'

@description('Optional tags applied to all resources.')
param tags object = {}

@description('Container image for the .NET API (fully qualified, e.g. myacr.azurecr.io/project1-api:1.0.0).')
param apiImage string

@description('Container image for the Python pipeline job (fully qualified, e.g. myacr.azurecr.io/idp-pipeline:1.0.0).')
param pipelineImage string

@description('Cosmos DB database name.')
param cosmosDatabaseName string = 'idp'

@description('Cosmos DB container name.')
param cosmosContainerName string = 'documents'

@description('Cosmos DB partition key path.')
param cosmosPartitionKeyPath string = '/partitionKey'

@description('Enable Cosmos DB free tier where available.')
param cosmosFreeTier bool = true

@description('Cosmos DB consistency level.')
@allowed([
  'Strong'
  'BoundedStaleness'
  'Session'
  'ConsistentPrefix'
  'Eventual'
])
param cosmosConsistencyLevel string = 'Session'

@description('Azure OpenAI API version used by the Python pipeline.')
param azureOpenAIApiVersion string = '2024-06-01'

@description('Azure OpenAI deployment name expected by the Python pipeline (AZURE_OPENAI_DEPLOYMENT).')
param azureOpenAIDeploymentName string = 'gpt-4o'

@description('Azure OpenAI model name for the deployment (varies by region/availability).')
param azureOpenAIModelName string = 'gpt-4o'

@description('Azure OpenAI model version for the deployment. Optional; set to match your region quota/model catalog.')
param azureOpenAIModelVersion string = '2024-08-06'

@description('Document Intelligence model ID used by the pipeline (e.g. prebuilt-document).')
param documentIntelligenceModelId string = 'prebuilt-document'

@description('Log Analytics retention in days.')
@minValue(30)
@maxValue(730)
param logAnalyticsRetentionDays int = 30

@description('Whether to create the Azure OpenAI model deployment via IaC. If false, create it manually and just set AZURE_OPENAI_DEPLOYMENT.')
param createAzureOpenAIDeployment bool = true

var nameSuffix = '${environment}'
var baseName = toLower(replace('${prefix}-${nameSuffix}', '--', '-'))

var logWsName = '${baseName}-law'
var caeName = '${baseName}-cae'
var cosmosName = toLower(replace('${baseName}-cosmos', '-', ''))
var diName = '${baseName}-di'
var aoaiName = '${baseName}-aoai'
var apiAppName = '${baseName}-api'
var pipelineJobName = '${baseName}-pipeline'

// Storage for uploads + Functions host (same account as AzureWebJobsStorage on the function app).
var uploadStorageAccountName = take(
  replace(toLower('blob${baseName}${uniqueString(resourceGroup().id, baseName)}'), '-', ''),
  24
)
var functionAppName = take(replace('${baseName}-fn-${take(uniqueString(resourceGroup().id, 'func'), 8)}', '_', '-'), 60)

module law './modules/logAnalytics.bicep' = {
  name: 'law-${uniqueString(resourceGroup().id, baseName)}'
  params: {
    location: location
    name: logWsName
    environment: environment
    tags: tags
    retentionInDays: logAnalyticsRetentionDays
  }
}

module cae './modules/containerAppsEnv.bicep' = {
  name: 'cae-${uniqueString(resourceGroup().id, baseName)}'
  params: {
    location: location
    name: caeName
    environment: environment
    tags: tags
    logAnalyticsCustomerId: law.outputs.customerId
    logAnalyticsSharedKey: law.outputs.sharedKey
  }
}

module cosmos './modules/cosmos.bicep' = {
  name: 'cosmos-${uniqueString(resourceGroup().id, baseName)}'
  params: {
    location: location
    accountName: cosmosName
    environment: environment
    tags: tags
    databaseName: cosmosDatabaseName
    containerName: cosmosContainerName
    partitionKeyPath: cosmosPartitionKeyPath
    freeTier: cosmosFreeTier
    consistencyLevel: cosmosConsistencyLevel
  }
}

module di './modules/documentIntelligence.bicep' = {
  name: 'di-${uniqueString(resourceGroup().id, baseName)}'
  params: {
    location: location
    name: diName
    environment: environment
    tags: tags
  }
}

module aoai './modules/openai.bicep' = {
  name: 'aoai-${uniqueString(resourceGroup().id, baseName)}'
  params: {
    location: location
    name: aoaiName
    environment: environment
    tags: tags
    deploymentName: azureOpenAIDeploymentName
    modelName: azureOpenAIModelName
    modelVersion: azureOpenAIModelVersion
    createDeployment: createAzureOpenAIDeployment
  }
}

module uploadStorage './modules/documentsStorage.bicep' = {
  name: 'upload-stg-${uniqueString(resourceGroup().id, baseName)}'
  params: {
    location: location
    accountName: uploadStorageAccountName
    envName: environment
    tags: tags
    uploadContainerName: 'uploads'
  }
}

module idpFunction './modules/functionApp.bicep' = {
  name: 'func-${uniqueString(resourceGroup().id, baseName)}'
  params: {
    location: location
    name: functionAppName
    environment: environment
    tags: tags
    storageConnectionString: uploadStorage.outputs.connectionString
    documentIntelligenceEndpoint: di.outputs.endpoint
    documentIntelligenceKey: di.outputs.key1
    documentIntelligenceModelId: documentIntelligenceModelId
    azureOpenAIEndpoint: aoai.outputs.endpoint
    azureOpenAIKey: aoai.outputs.key1
    azureOpenAIDeploymentName: aoai.outputs.deploymentNameOut
    azureOpenAIApiVersion: azureOpenAIApiVersion
    cosmosEndpoint: cosmos.outputs.endpoint
    cosmosKey: cosmos.outputs.primaryKey
    cosmosDatabase: cosmos.outputs.database
    cosmosContainer: cosmos.outputs.containerNameOut
    applicationInsightsConnectionString: ''
  }
}

module api './modules/apiContainerApp.bicep' = {
  name: 'api-${uniqueString(resourceGroup().id, baseName)}'
  params: {
    location: location
    name: apiAppName
    environment: environment
    tags: tags
    containerAppsEnvironmentId: cae.outputs.id
    image: apiImage
    cosmosEndpoint: cosmos.outputs.endpoint
    cosmosKey: cosmos.outputs.primaryKey
    cosmosDatabase: cosmos.outputs.database
    cosmosContainer: cosmos.outputs.containerNameOut
    blobConnectionString: uploadStorage.outputs.connectionString
    blobContainerName: uploadStorage.outputs.uploadContainerNameOut
  }
}

module pipeline './modules/pipelineJob.bicep' = {
  name: 'pipeline-${uniqueString(resourceGroup().id, baseName)}'
  params: {
    location: location
    name: pipelineJobName
    environment: environment
    tags: tags
    containerAppsEnvironmentId: cae.outputs.id
    image: pipelineImage
    documentIntelligenceEndpoint: di.outputs.endpoint
    documentIntelligenceKey: di.outputs.key1
    documentIntelligenceModelId: documentIntelligenceModelId
    azureOpenAIEndpoint: aoai.outputs.endpoint
    azureOpenAIKey: aoai.outputs.key1
    azureOpenAIDeploymentName: aoai.outputs.deploymentNameOut
    azureOpenAIApiVersion: azureOpenAIApiVersion
    cosmosEndpoint: cosmos.outputs.endpoint
    cosmosKey: cosmos.outputs.primaryKey
    cosmosDatabase: cosmos.outputs.database
    cosmosContainer: cosmos.outputs.containerNameOut
  }
}

output cosmosEndpoint string = cosmos.outputs.endpoint
output cosmosDatabase string = cosmos.outputs.database
output cosmosContainer string = cosmos.outputs.containerNameOut
output documentIntelligenceEndpoint string = di.outputs.endpoint
output azureOpenAIEndpoint string = aoai.outputs.endpoint
output apiFqdn string = api.outputs.fqdn
output uploadStorageAccountName string = uploadStorage.outputs.accountNameOut
output functionAppNameOut string = idpFunction.outputs.functionAppName
output functionAppDefaultHostName string = idpFunction.outputs.defaultHostName

