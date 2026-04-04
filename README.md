# Project: Intelligent Document Processing Pipeline

This project implements an end-to-end Intelligent Document Processing (IDP) pipeline:

1. Ingest document files (invoice, contract, receipt) via CLI, or upload PDF/images through the .NET API into Azure Blob Storage
2. Run extraction with Azure AI Document Intelligence and enrichment with Azure OpenAI (GPT-4 class deployment)
3. Persist final records in Azure Cosmos DB
4. Expose query/upload APIs via a .NET Minimal API, with a small browser UI under `/` for upload and polling
5. Optionally process uploads asynchronously using an **Azure Functions (Python)** app with a **blob trigger** on the `uploads` container

## 1) Architecture (High Level)

```text
[CLI file path]                    [Browser / SPA]
       |                                    |
       |                                    v
       |                         .NET API: POST /documents/upload
       |                         (PDF/PNG/JPEG, max 5 MB)
       |                                    |
       v                                    v
              Azure Blob Storage (container: uploads)
              Path: {docType}/{uploadId}/{fileName}
                           |
           +---------------+----------------+
           |                                |
           v                                v
  Azure Function (Python)              (manual / other)
  blob trigger -> pipeline_runner      consumers
           |
           v
  Document Intelligence + OpenAI (same as CLI)
           |
           v
  Cosmos DB  <---- GET /documents/by-upload/{uploadId}
           |        GET /documents/{id}
           v
  .NET API + static wwwroot UI
```

The CLI path (`python src/python_pipeline/main.py ...`) still runs the same Python processor locally or in the Container Apps Job without using Blob Storage.

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
    pipeline_runner.py
    prompts/enrichment_prompt.txt
    storage/cosmos_repository.py
  src/azure_function/
    function_app.py
    host.json
    requirements.txt
    local.settings.json.example
  dotnet-api/
    Project1.Api.csproj
    Program.cs
    appsettings.json
    appsettings.Development.json
```

## 4) Prerequisites

- Python 3.10+
- .NET 8 SDK
- Azure resources (full stack):
  - Azure AI Document Intelligence
  - Azure OpenAI deployment (GPT-4 family model via Foundry)
  - Azure Cosmos DB (NoSQL API)
  - Azure Storage Account (blob container `uploads` for API uploads + Functions host)
  - Azure Functions (Python 3.11, v4) for blob-triggered processing
- Optional local: [Azurite](https://learn.microsoft.com/azure/storage/common/storage-use-azurite) for Blob API + Functions storage emulator

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

1. Configure Cosmos in `appsettings.json` or user secrets (see `dotnet-api/appsettings.json.example`).
2. Set **Blob** settings so uploads can be written to the same storage account the Function app monitors:
   - `Blob:ConnectionString` — storage connection string (in Azure, use the upload/functions storage account from Bicep outputs; locally you can use Azurite `UseDevelopmentStorage=true` after creating an `uploads` container).
   - `Blob:ContainerName` — default `uploads`.
3. **CORS**: `Cors:AllowedOrigins` is an optional array. If empty or omitted, the API allows any origin (fine for dev only). For production, list your SPA origins explicitly.

```powershell
cd dotnet-api
dotnet restore
dotnet run
```

Open the dev URL from `dotnet-api/Properties/launchSettings.json` (for example `https://localhost:53726`) — the sample UI is served from `wwwroot/index.html` at `/`.

Endpoints:
- `GET /health`
- `POST /documents/upload` — multipart form: `docType` (`invoice` \| `receipt` \| `contract` \| `other`) and `file` (`.pdf`, `.png`, `.jpg`, `.jpeg`, max 5 MB). Returns `202` with `uploadId` and `pollUrl`. Rate-limited per client IP.
- `GET /documents/by-upload/{uploadId}` — poll until the Function pipeline has written the Cosmos document (returns `404` while processing).
- `GET /documents/{id}` — fetch a single processed document by Cosmos `id` (cross-partition query).
- `GET /documents?docType=invoice` — list by type (optional query parameter)

## 7) Data model (Cosmos)

Single document per processed file:

- `id` (GUID)
- `partitionKey` (e.g. `docType`)
- `sourceFileName`
- `docType`
- `documentIntelligence` (raw/normalized fields)
- `gptEnrichment` — JSON from Azure OpenAI; keys are defined in `prompts/enrichment_prompt.txt`:
  - `normalizedFields`, `summary`, `documentPurpose`
  - `entities`, `keyDates`, `actionItems`, `financialHighlights`, `referencedIdentifiers`
  - `riskSignals`, `tags`, `suggestedNextSteps`, `confidenceAssessment`
- `processingMetadata` (timestamps, model versions, confidence)
- `uploadId`, `blobPath` — set when the document was created from an API upload + blob-triggered run (for correlation and support)

## 7b) Azure Function (blob trigger)

1. Copy `src/azure_function/local.settings.json.example` to `local.settings.json` and set `AzureWebJobsStorage` plus the same AI/Cosmos variables as `.env` for the pipeline.
2. From `src/azure_function`, create a Python venv, `pip install -r requirements.txt`, and run `func start` (requires [Azure Functions Core Tools](https://learn.microsoft.com/azure/azure-functions/functions-run-local)).
3. The trigger watches container **`uploads`** (same as the API) with path pattern `uploads/{name}` where `name` is `{docType}/{uploadId}/{fileName}` — this must match what the API uploads.

**Deploy to Azure:** after `az deployment` creates the Function app, publish from a folder that contains both `function_app.py` / `host.json` and a **`python_pipeline`** copy next to it (the host resolves `pipeline_runner` from that folder). Example packaging:

```powershell
$stage = "$PWD\dist\functionapp"
New-Item -ItemType Directory -Path $stage -Force | Out-Null
Copy-Item -Recurse src\azure_function\* $stage
Copy-Item -Recurse src\python_pipeline (Join-Path $stage "python_pipeline")
cd $stage
func azure functionapp publish <your-function-app-name>
```

## 8) Production hardening ideas

- Prefer **user-delegated SAS** or **managed identity** for the API to write blobs instead of a full storage connection string in configuration.
- Add Application Insights connection strings to the Function app (Bicep currently leaves `applicationInsightsConnectionString` empty; set it when you wire AI components).
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
