param location string
param name string
param environment string
param tags object = {}

param logAnalyticsCustomerId string
@secure()
param logAnalyticsSharedKey string

resource env 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: name
  location: location
  tags: union(tags, {
    env: environment
    app: 'project1-idp'
  })
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsCustomerId
        sharedKey: logAnalyticsSharedKey
      }
    }
  }
}

output id string = env.id

