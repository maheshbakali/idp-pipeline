param location string
param name string
param environment string
param tags object = {}

param deploymentName string = 'gpt-4o'
param modelName string = 'gpt-4o'
param modelVersion string = '2024-08-06'

@description('Whether to create the model deployment in Azure OpenAI.')
param createDeployment bool = true

resource aoai 'Microsoft.CognitiveServices/accounts@2024-04-01' = {
  name: name
  location: location
  tags: union(tags, {
    env: environment
    app: 'project1-idp'
  })
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
  }
}

resource deployment 'Microsoft.CognitiveServices/accounts/deployments@2024-04-01' = if (createDeployment) {
  name: '${aoai.name}/${deploymentName}'
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
    scaleSettings: {
      scaleType: 'Standard'
    }
  }
}

output id string = aoai.id
output endpoint string = aoai.properties.endpoint
@secure()
output key1 string = listKeys(aoai.id, aoai.apiVersion).key1
output deploymentNameOut string = deploymentName

