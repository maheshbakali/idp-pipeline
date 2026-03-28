from pathlib import Path

from azure_clients import (
    create_azure_openai_client,
    create_document_intelligence_client,
    enrich_with_gpt,
    extract_with_document_intelligence,
)
from config import Settings
from models import ProcessedDocument, ProcessingMetadata, utc_now_iso
from storage.cosmos_repository import CosmosRepository


class DocumentProcessor:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.doc_client = create_document_intelligence_client(settings)
        self.openai_client = create_azure_openai_client(settings)
        self.repo = CosmosRepository(settings)

    def process_file(self, file_path: str, doc_type: str) -> ProcessedDocument:
        path = Path(file_path)
        if not path.exists() or not path.is_file():
            raise FileNotFoundError(f"Document not found: {file_path}")

        prompt_path = Path(__file__).parent / "prompts" / "enrichment_prompt.txt"
        prompt_template = prompt_path.read_text(encoding="utf-8")

        file_bytes = path.read_bytes()
        extracted_at = utc_now_iso()
        extracted = extract_with_document_intelligence(
            client=self.doc_client,
            model_id=self.settings.document_intelligence_model,
            file_bytes=file_bytes,
        )

        enriched_at = utc_now_iso()
        enrichment = enrich_with_gpt(
            client=self.openai_client,
            deployment=self.settings.azure_openai_deployment,
            doc_type=doc_type,
            extracted_payload=extracted,
            prompt_template=prompt_template,
        )

        item = ProcessedDocument(
            partitionKey=doc_type,
            documentId=doc_type,
            sourceFileName=path.name,
            docType=doc_type,
            documentIntelligence=extracted,
            gptEnrichment=enrichment,
            processingMetadata=ProcessingMetadata(
                extracted_at_utc=extracted_at,
                enriched_at_utc=enriched_at,
                document_intelligence_model=self.settings.document_intelligence_model,
                openai_deployment=self.settings.azure_openai_deployment,
            ),
        )

        self.repo.upsert(item.model_dump())
        return item
