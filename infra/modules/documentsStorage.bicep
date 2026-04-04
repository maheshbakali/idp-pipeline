param location string
@minLength(3)
@maxLength(24)
param accountName string
param envName string
param tags object = {}
param uploadContainerName string = 'uploads'

// Dedicated storage for user uploads + Azure Functions host (blob trigger on the same account).
resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: accountName
  location: location
  tags: union(tags, {
    env: envName
    app: 'project1-idp'
    component: 'uploads-functions'
  })
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    encryption: {
      services: {
        blob: {
          enabled: true
        }
        file: {
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storage
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource uploadsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: uploadContainerName
  properties: {
    publicAccess: 'None'
  }
}

var primaryKey = storage.listKeys().keys[0].value
var storageConnectionString = 'DefaultEndpointsProtocol=https;AccountName=${storage.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${primaryKey}'

output accountNameOut string = storage.name
@secure()
output connectionString string = storageConnectionString
output uploadContainerNameOut string = uploadContainerName
