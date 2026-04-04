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

# DocumentProcessor orchestrates the processing of documents: it extracts content using Azure Document Intelligence, 
# enriches it with Azure OpenAI, and stores the results in Cosmos DB.
class DocumentProcessor:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.doc_client = create_document_intelligence_client(settings)
        self.openai_client = create_azure_openai_client(settings)
        self.repo = CosmosRepository(settings)
        self._prompt_template = (Path(__file__).parent / "prompts" / "enrichment_prompt.txt").read_text(
            encoding="utf-8"
        )

    def process_bytes(
        self,
        file_bytes: bytes,
        source_file_name: str,
        doc_type: str,
        *,
        upload_id: str | None = None,
        blob_path: str | None = None,
    ) -> ProcessedDocument:
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
            prompt_template=self._prompt_template,
        )

        item = ProcessedDocument(
            partitionKey=doc_type,
            documentId=doc_type,
            sourceFileName=source_file_name,
            docType=doc_type,
            documentIntelligence=extracted,
            gptEnrichment=enrichment,
            processingMetadata=ProcessingMetadata(
                extracted_at_utc=extracted_at,
                enriched_at_utc=enriched_at,
                document_intelligence_model=self.settings.document_intelligence_model,
                openai_deployment=self.settings.azure_openai_deployment,
            ),
            uploadId=upload_id,
            blobPath=blob_path,
        )

        self.repo.upsert(item.model_dump())
        return item

    def process_file(self, file_path: str, doc_type: str) -> ProcessedDocument:
        path = Path(file_path)
        if not path.exists() or not path.is_file():
            raise FileNotFoundError(f"Document not found: {file_path}")
        return self.process_bytes(path.read_bytes(), path.name, doc_type)
