# Project 1: Intelligent Document Processing Pipeline

This project implements an end-to-end Intelligent Document Processing (IDP) pipeline:

1. Ingest document files (invoice, contract, receipt)
2. Extract structure with Azure AI Document Intelligence
3. Enrich normalized output with Azure OpenAI GPT-4 (Azure AI Foundry deployment)
4. Persist final records in Azure Cosmos DB
5. Expose retrieval/query APIs via a .NET API layer

## 1) Architecture (High Level)

```text
[Document Input]
   |
   v
Python Orchestrator (main.py)
   |
   +--> Azure Document Intelligence (prebuilt-document / custom)
   |        |
   |        v
   |   Raw extracted fields + confidence
   |
   +--> Azure OpenAI GPT-4 (Foundry deployment)
   |        |
   |        v
   |   Enriched JSON (normalized, risk flags, summaries)
   |
   v
CosmosRepository
   |
   v
Azure Cosmos DB (documents container)
   |
   v
.NET Minimal API (read/query endpoints)
```

## 2) Why this design

- Python is used for AI-heavy orchestration and prompt workflows.
- Azure services remain stateless and composable; scaling is done at API/service edges.
- Cosmos DB stores both extracted and enriched payloads for traceability/auditing.
- .NET API provides enterprise-friendly integration points for downstream systems/UI.

## 3) Project structure

```text
project_idp_pipeline/
  .env.example
  requirements.txt
  README.md
  src/python_pipeline/
    config.py
    models.py
    azure_clients.py
    processor.py
    main.py
    prompts/enrichment_prompt.txt
    storage/cosmos_repository.py
  dotnet-api/
    Project1.Api.csproj
    Program.cs
    appsettings.json
    appsettings.Development.json
```

## 4) Prerequisites

- Python 3.10+
- .NET 8 SDK
- Azure resources:
  - Azure AI Document Intelligence
  - Azure OpenAI deployment (GPT-4 family model via Foundry)
  - Azure Cosmos DB (NoSQL API)

## 5) Setup (Python)

1. Create virtual environment and install deps:

```powershell
cd project_idp_pipeline
python -m venv .venv
.\.venv\Scripts\activate
pip install -r requirements.txt
```

2. Copy env template and fill values:

```powershell
copy .env.example .env
```

3. Run pipeline:

```powershell
python src/python_pipeline/main.py --file "C:\path\to\invoice.pdf" --doc-type invoice
```

## 6) Setup (.NET API)

```powershell
cd dotnet-api
dotnet restore
dotnet run
```

API base URL example: `http://localhost:5062`

Endpoints:
- `GET /health`
- `GET /documents/{id}`
- `GET /documents?docType=invoice`

## 7) Data model (Cosmos)

Single document per processed file:

- `id` (GUID)
- `partitionKey` (e.g. `docType`)
- `sourceFileName`
- `docType`
- `documentIntelligence` (raw/normalized fields)
- `gptEnrichment` (summary, entities, riskSignals, tags)
- `processingMetadata` (timestamps, model versions, confidence)

## 8) Production hardening ideas

- Replace local file ingestion with Blob Storage + Event Grid trigger.
- Add retry policies and dead-letter queue for failed docs.
- Use Managed Identity + Key Vault instead of plain env secrets.
- Add custom Document Intelligence model per document type for higher accuracy.
- Add unit/integration tests and OpenTelemetry tracing.

## 9) Infrastructure as Code (Bicep)

This repo includes Bicep templates to provision the Azure resources used by the pipeline:

- Azure Cosmos DB (SQL API) for document storage
- Azure AI Document Intelligence for extraction
- Azure OpenAI for enrichment
- Azure Container Apps environment + Log Analytics
- Azure Container App for the .NET API
- Azure Container Apps Job for the Python pipeline

Files:
- `infra/main.bicep`: main template
- `infra/main.bicepparam`: example parameters (edit values per environment)

### Build container images

.NET API image:

```powershell
docker build -t <registry>/project1-api:1.0.0 -f dotnet-api/Dockerfile .
docker push <registry>/project1-api:1.0.0
```

Python pipeline image:

```powershell
docker build -t <registry>/project1-idp-pipeline:1.0.0 -f src/python_pipeline/Dockerfile .
docker push <registry>/project1-idp-pipeline:1.0.0
```

### Deploy infrastructure

```powershell
az group create -n <rg-name> -l <location>
az deployment group create `
  -g <rg-name> `
  -f infra/main.bicep `
  -p infra/main.bicepparam
```

### Running the pipeline job

The deployed pipeline is an Azure Container Apps Job (manual trigger by default). You can start it and pass arguments.
Exact CLI shape may differ slightly by Azure CLI version; use:

```powershell
az containerapp job start -n <job-name> -g <rg-name>
```

## 10) CI/CD (Azure DevOps)

This repo includes YAML pipelines for Azure DevOps:

- **Build pipeline**: builds + pushes the .NET API image and Python pipeline image to ACR  
  File: `pipelines/azure-pipelines-build.yml`
- **Deploy pipeline** (manual): deploys infra to a selected environment using Bicep  
  File: `pipelines/azure-pipelines-deploy.yml`
- **Release pipeline** (multi-stage): Build → Dev → Test → Prod  
  File: `azure-pipelines.yml`

Reusable templates live in `pipelines/templates/`.

### Required Azure DevOps setup

- Create an **Azure Resource Manager service connection** and set its name in the YAML as `AZURE-SC-NAME`.
- Create / use an **Azure Container Registry** and set `acrName` (ACR resource name).
- Create Azure DevOps **Environments** named `dev`, `test`, `prod` (you can add approvals/checks for Test/Prod).


