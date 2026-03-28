param location string
param name string
param environment string
param tags object = {}

resource di 'Microsoft.CognitiveServices/accounts@2024-04-01' = {
  name: name
  location: location
  tags: union(tags, {
    env: environment
    app: 'project1-idp'
  })
  kind: 'FormRecognizer'
  sku: {
    name: 'S0'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
  }
}

output id string = di.id
output endpoint string = di.properties.endpoint
@secure()
output key1 string = listKeys(di.id, di.apiVersion).key1

