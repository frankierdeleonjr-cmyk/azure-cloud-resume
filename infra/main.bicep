targetScope = 'resourceGroup'

// =====================================================
// Parameters
// =====================================================

@description('Primary Azure region for the cloud resume backend resources.')
param location string = 'centralus'

@description('Name of the existing Azure Static Web App hosting the portfolio frontend.')
param staticWebAppName string = 'swa-azure-cloud-resume-prod'

@description('Name of the storage account used by the Azure Function and visitor counter.')
param storageAccountName string = 'stcloudresumefrd2026'

@description('Name of the Azure Function App hosting the visitor counter API.')
param functionAppName string = 'func-azure-cloud-resume-frd2026'

@description('Name of the Function App runtime managed identity.')
param functionIdentityName string = 'id-func-cloud-resume-prod'

@description('Name of the GitHub Actions deployment managed identity.')
param githubDeployIdentityName string = 'id-github-deploy-cloud-resume-prod'

@description('Name of the existing Flex Consumption hosting plan used by the Function App.')
param functionPlanName string = 'ASP-rgazurecloudresumeprod-9b98'

@description('Existing deployment-package storage container used by the Function App.')
param deploymentContainerName string = 'app-package-funcazurecloudresumefrd2026-6701622'

@description('Resource ID of the existing Log Analytics workspace connected to Application Insights.')
param logAnalyticsWorkspaceResourceId string

@description('Name of the Application Insights component monitoring the Function API.')
param applicationInsightsName string = 'func-azure-cloud-resume-frd2026'

@description('Existing role assignment ID for Function deployment package blob access.')
param functionBlobRoleAssignmentName string = 'cb92d099-c836-4973-ba14-4a5446456cf9'

@description('Existing role assignment ID for Function visitor-count table access.')
param functionTableRoleAssignmentName string = '7c7cf504-a86e-46dd-ac2c-88908bae321d'

@description('Existing role assignment ID for GitHub Actions deployment access.')
param githubDeploymentRoleAssignmentName string = 'a7af1b31-2e17-4155-9a4e-57c248ecd7fc'

// =====================================================
// Variables
// =====================================================

var commonTags = {
  Project: 'AzureCloudResume'
  Environment: 'Production'
  Owner: 'FrankieDeLeon'
}

var storageTags = union(commonTags, {
  Purpose: 'VisitorCounter'
})

var functionTags = union(commonTags, {
  Purpose: 'VisitorCounterAPI'
})

var functionIdentityTags = union(commonTags, {
  Purpose: 'FunctionStorageAccess'
})

var githubIdentityTags = union(commonTags, {
  Purpose: 'GitHubActionsDeployment'
})

var storageBlobDataOwnerRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
)

var storageTableDataContributorRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
)

var websiteContributorRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'de139f84-1756-47ae-9be6-808fbbe84772'
)

// =====================================================
// Existing Frontend Resource
// =====================================================

// The Static Web App already exists and is connected to GitHub.
// It is referenced for CORS configuration without redeploying it.
resource staticWebApp 'Microsoft.Web/staticSites@2025-03-01' existing = {
  name: staticWebAppName
}

var staticWebAppOrigin = 'https://${staticWebApp.properties.defaultHostname}'

// =====================================================
// Storage
// =====================================================

// Secured storage account used for Function deployment storage
// and visitor-count table data.
resource storageAccount 'Microsoft.Storage/storageAccounts@2025-01-01' = {
  name: storageAccountName
  location: location
  tags: storageTags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

// Blob service used by the Function App deployment package.
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2025-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      allowPermanentDelete: false
      enabled: false
    }
  }
}

// Private container holding the deployed Azure Function application package.
resource functionDeploymentContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-01-01' = {
  parent: blobService
  name: deploymentContainerName
  properties: {
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}

// =====================================================
// Managed Identities
// =====================================================

// Runtime identity used by the Function App to access storage.
resource functionIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: functionIdentityName
  location: location
  tags: functionIdentityTags
}

// Deployment identity used by GitHub Actions through OIDC.
resource githubDeployIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: githubDeployIdentityName
  location: location
  tags: githubIdentityTags
}

// Allows only the repository main branch to authenticate
// as the GitHub deployment identity through OIDC.
resource githubMainFederatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: githubDeployIdentity
  name: 'github-main-api-deploy'
  properties: {
    issuer: 'https://token.actions.githubusercontent.com'
    subject: 'repo:frankierdeleonjr-cmyk/azure-cloud-resume:ref:refs/heads/main'
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
}

// =====================================================
// Monitoring
// =====================================================

// Workspace-based Application Insights component used to monitor the Function API.
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    IngestionMode: 'LogAnalytics'
    RetentionInDays: 90
    WorkspaceResourceId: logAnalyticsWorkspaceResourceId
  }
}

// =====================================================
// Azure Function Hosting and API
// =====================================================

// Serverless Flex Consumption hosting plan used by the Azure Function API.
resource functionPlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: functionPlanName
  location: location
  kind: 'functionapp'
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  properties: {
    reserved: true
  }
}

// Serverless backend API that reads and updates the live visitor counter.
resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  tags: functionTags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${functionIdentity.id}': {}
    }
  }
  properties: {
    serverFarmId: functionPlan.id
    httpsOnly: true
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storageAccount.properties.primaryEndpoints.blob}${deploymentContainerName}'
          authentication: {
            type: 'UserAssignedIdentity'
            userAssignedIdentityResourceId: functionIdentity.id
          }
        }
      }
      runtime: {
        name: 'node'
        version: '22'
      }
      scaleAndConcurrency: {
        alwaysReady: []
        maximumInstanceCount: 100
        instanceMemoryMB: 2048
      }
    }
  }
}

// Application settings used by the live visitor-counter API.
resource functionAppSettings 'Microsoft.Web/sites/config@2024-04-01' = {
  parent: functionApp
  name: 'appsettings'
  properties: {
    APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsights.properties.ConnectionString
    AZURE_CLIENT_ID: functionIdentity.properties.clientId
    AzureWebJobsStorage__accountName: storageAccount.name
    AzureWebJobsStorage__clientId: functionIdentity.properties.clientId
    AzureWebJobsStorage__credential: 'managedidentity'
    TABLE_STORAGE_ENDPOINT: storageAccount.properties.primaryEndpoints.table
  }
}

// Allows the public portfolio frontend to call only this API origin.
resource functionWebConfig 'Microsoft.Web/sites/config@2024-04-01' = {
  parent: functionApp
  name: 'web'
  properties: {
    cors: {
      allowedOrigins: [
        staticWebAppOrigin
      ]
      supportCredentials: false
    }
  }
}

// =====================================================
// Role-Based Access Control
// =====================================================

// Allows the Function App identity to use its secured deployment-package storage.
resource functionBlobStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: functionBlobRoleAssignmentName
  scope: storageAccount
  properties: {
    principalId: functionIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: storageBlobDataOwnerRoleDefinitionId
  }
}

// Allows the visitor-counter API to read and update Azure Table Storage data.
resource functionTableStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: functionTableRoleAssignmentName
  scope: storageAccount
  properties: {
    principalId: functionIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: storageTableDataContributorRoleDefinitionId
  }
}

// Allows GitHub Actions to deploy backend code only to the Function App.
resource githubFunctionDeploymentRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: githubDeploymentRoleAssignmentName
  scope: functionApp
  properties: {
    principalId: githubDeployIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: websiteContributorRoleDefinitionId
  }
}

// =====================================================
// Outputs
// =====================================================

output portfolioWebsiteUrl string = staticWebAppOrigin
output visitorApiUrl string = 'https://${functionApp.properties.defaultHostName}/api/visitors'
output storageAccountResourceId string = storageAccount.id
output functionAppResourceId string = functionApp.id
