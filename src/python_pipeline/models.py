from datetime import datetime, timezone
from typing import Any
from uuid import uuid4

from pydantic import BaseModel, Field

# Models for the processed document and metadata to be stored in Cosmos DB.
class ProcessingMetadata(BaseModel):
    extracted_at_utc: str
    enriched_at_utc: str
    document_intelligence_model: str
    openai_deployment: str

# The main document model that will be stored in Cosmos DB.
class ProcessedDocument(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid4()))
    partitionKey: str
    documentId: str
    sourceFileName: str
    docType: str
    documentIntelligence: dict[str, Any]
    gptEnrichment: dict[str, Any]
    processingMetadata: ProcessingMetadata
    uploadId: str | None = None
    blobPath: str | None = None


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()
