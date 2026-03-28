from datetime import datetime, timezone
from typing import Any
from uuid import uuid4

from pydantic import BaseModel, Field


class ProcessingMetadata(BaseModel):
    extracted_at_utc: str
    enriched_at_utc: str
    document_intelligence_model: str
    openai_deployment: str


class ProcessedDocument(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid4()))
    partitionKey: str
    documentId: str
    sourceFileName: str
    docType: str
    documentIntelligence: dict[str, Any]
    gptEnrichment: dict[str, Any]
    processingMetadata: ProcessingMetadata


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()
