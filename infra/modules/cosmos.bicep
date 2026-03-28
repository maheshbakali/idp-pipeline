param location string
param accountName string
param environment string
param tags object = {}

param databaseName string = 'idp'
param containerName string = 'documents'
param partitionKeyPath string = '/partitionKey'
param freeTier bool = true
param consistencyLevel string = 'Session'

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: accountName
  location: location
  tags: union(tags, {
    env: environment
    app: 'project1-idp'
  })
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    enableFreeTier: freeTier
    consistencyPolicy: {
      defaultConsistencyLevel: consistencyLevel
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
  }
}

resource db 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  name: '${cosmos.name}/${databaseName}'
  properties: {
    resource: {
      id: databaseName
    }
  }
}

resource container 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  name: '${cosmos.name}/${databaseName}/${containerName}'
  properties: {
    resource: {
      id: containerName
      partitionKey: {
        paths: [
          partitionKeyPath
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
        includedPaths: [
          {
            path: '/*'
          }
        ]
        excludedPaths: [
          {
            path: '/"_etag"/?'
          }
        ]
      }
    }
  }
  dependsOn: [
    db
  ]
}

output accountId string = cosmos.id
output endpoint string = cosmos.properties.documentEndpoint
@secure()
output primaryKey string = listKeys(cosmos.id, cosmos.apiVersion).primaryMasterKey
output database string = databaseName
output containerNameOut string = containerName

