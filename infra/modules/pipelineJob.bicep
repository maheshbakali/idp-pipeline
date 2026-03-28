param location string
param name string
param environment string
param tags object = {}

param containerAppsEnvironmentId string

param image string

param documentIntelligenceEndpoint string
@secure()
param documentIntelligenceKey string
param documentIntelligenceModelId string = 'prebuilt-document'

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

resource job 'Microsoft.App/jobs@2024-03-01' = {
  name: name
  location: location
  tags: union(tags, {
    env: environment
    app: 'project1-idp'
    component: 'pipeline'
  })
  properties: {
    environmentId: containerAppsEnvironmentId
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 1800
      replicaRetryLimit: 1
    }
    template: {
      containers: [
        {
          name: 'pipeline'
          image: image
          env: [
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
          ]
        }
      ]
    }
  }
}

output id string = job.id

