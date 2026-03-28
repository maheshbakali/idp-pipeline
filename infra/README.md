# Infrastructure (Bicep)

This folder provisions the Azure resources used by `project_idp_pipeline`.

## What gets deployed

- **Cosmos DB (SQL API)**: database + container for processed document JSON
- **Azure AI Document Intelligence**: extraction service (Form Recognizer kind)
- **Azure OpenAI**: enrichment service (optionally creates a model deployment)
- **Log Analytics**: Container Apps diagnostics
- **Azure Container Apps Environment**
- **Container App**: runs the .NET API (`dotnet-api`)
- **Container Apps Job**: runs the Python pipeline (`src/python_pipeline`)

## Files

- `main.bicep`: primary template
- `main.bicepparam`: example parameters (edit per environment)

## Deploy

```powershell
az group create -n <rg-name> -l <location>

az deployment group create `
  -g <rg-name> `
  -f infra/main.bicep `
  -p infra/main.bicepparam
```

## Images

The template expects you to provide two container images:

- `apiImage`: .NET API image built from `dotnet-api/Dockerfile`
- `pipelineImage`: Python pipeline image built from `src/python_pipeline/Dockerfile`

Example:

```powershell
docker build -t <registry>/project1-api:1.0.0 -f dotnet-api/Dockerfile .
docker push <registry>/project1-api:1.0.0

docker build -t <registry>/project1-idp-pipeline:1.0.0 -f src/python_pipeline/Dockerfile .
docker push <registry>/project1-idp-pipeline:1.0.0
```

## Notes / common pitfalls

- **Azure OpenAI access**: OpenAI model deployments can fail if your subscription/region does not have access to the chosen model. If it fails, deploy the OpenAI account and create the deployment manually, then set `AZURE_OPENAI_DEPLOYMENT` accordingly.
- **Cosmos partition key**: this project uses `partitionKey = docType` (e.g., `invoice`) and the container partition key path is `/partitionKey`.

