param location string
param name string
param environment string
param tags object = {}

@secure()
param storageConnectionString string

param documentIntelligenceEndpoint string
@secure()
param documentIntelligenceKey string
param documentIntelligenceModelId string = 'prebuilt-layout'

param azureOpenAIEndpoint string
@secure()
param azureOpenAIKey string
param azureOpenAIDeploymentName string = 'gpt-4o'
param azureOpenAIApiVersion string = '2024-06-01'

param cosmosEndpoint string
@secure()
param cosmosKey string
param cosmosDatabase string
param cosmosContainer string

@secure()
param applicationInsightsConnectionString string = ''

resource hostingPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${name}-plan'
  location: location
  tags: union(tags, {
    env: environment
    app: 'project1-idp'
    component: 'function-host'
  })
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: true
  }
}

var appSettings = concat([
  {
    name: 'AzureWebJobsStorage'
    value: storageConnectionString
  }
  {
    name: 'FUNCTIONS_EXTENSION_VERSION'
    value: '~4'
  }
  {
    name: 'FUNCTIONS_WORKER_RUNTIME'
    value: 'python'
  }
  {
    name: 'DOCUMENT_INTELLIGENCE_ENDPOINT'
    value: documentIntelligenceEndpoint
  }
  {
    name: 'DOCUMENT_INTELLIGENCE_KEY'
    value: documentIntelligenceKey
  }
  {
    name: 'DOCUMENT_INTELLIGENCE_MODEL'
    value: documentIntelligenceModelId
  }
  {
    name: 'AZURE_OPENAI_ENDPOINT'
    value: azureOpenAIEndpoint
  }
  {
    name: 'AZURE_OPENAI_API_KEY'
    value: azureOpenAIKey
  }
  {
    name: 'AZURE_OPENAI_DEPLOYMENT'
    value: azureOpenAIDeploymentName
  }
  {
    name: 'AZURE_OPENAI_API_VERSION'
    value: azureOpenAIApiVersion
  }
  {
    name: 'COSMOS_ENDPOINT'
    value: cosmosEndpoint
  }
  {
    name: 'COSMOS_KEY'
    value: cosmosKey
  }
  {
    name: 'COSMOS_DATABASE'
    value: cosmosDatabase
  }
  {
    name: 'COSMOS_CONTAINER'
    value: cosmosContainer
  }
], empty(applicationInsightsConnectionString) ? [] : [
  {
    name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
    value: applicationInsightsConnectionString
  }
])

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: name
  location: location
  tags: union(tags, {
    env: environment
    app: 'project1-idp'
    component: 'blob-processor'
  })
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: hostingPlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'PYTHON|3.11'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      appSettings: appSettings
    }
    clientAffinityEnabled: false
  }
}

output functionAppName string = functionApp.name
output principalId string = functionApp.identity.principalId
output defaultHostName string = functionApp.properties.defaultHostName
