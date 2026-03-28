param location string
param name string
param environment string
param tags object = {}

param containerAppsEnvironmentId string

param image string
param targetPort int = 8080

param cosmosEndpoint string
@secure()
param cosmosKey string
param cosmosDatabase string
param cosmosContainer string

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: name
  location: location
  tags: union(tags, {
    env: environment
    app: 'project1-idp'
    component: 'api'
  })
  properties: {
    managedEnvironmentId: containerAppsEnvironmentId
    configuration: {
      ingress: {
        external: true
        targetPort: targetPort
        transport: 'auto'
      }
      registries: []
    }
    template: {
      containers: [
        {
          name: 'api'
          image: image
          env: [
            {
              name: 'Cosmos__Endpoint'
              value: cosmosEndpoint
            }
            {
              name: 'Cosmos__Key'
              value: cosmosKey
            }
            {
              name: 'Cosmos__Database'
              value: cosmosDatabase
            }
            {
              name: 'Cosmos__Container'
              value: cosmosContainer
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
      }
    }
  }
}

output fqdn string = app.properties.configuration.ingress.fqdn

