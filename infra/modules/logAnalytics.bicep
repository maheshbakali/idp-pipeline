param location string
param name string
param environment string
param tags object = {}
param retentionInDays int = 30

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: name
  location: location
  tags: union(tags, {
    env: environment
    app: 'project1-idp'
  })
  properties: {
    retentionInDays: retentionInDays
    sku: {
      name: 'PerGB2018'
    }
  }
}

output id string = workspace.id
output customerId string = workspace.properties.customerId
output sharedKey string = listKeys(workspace.id, workspace.apiVersion).primarySharedKey

