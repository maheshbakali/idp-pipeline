"""Shared entry points for CLI, Azure Functions, and tests."""

from config import Settings, get_settings
from models import ProcessedDocument
from processor import DocumentProcessor


def process_document_from_file(file_path: str, doc_type: str, settings: Settings | None = None) -> ProcessedDocument:
    settings = settings or get_settings()
    return DocumentProcessor(settings).process_file(file_path, doc_type)


def process_document_from_bytes(
    file_bytes: bytes,
    source_file_name: str,
    doc_type: str,
    *,
    upload_id: str | None = None,
    blob_path: str | None = None,
    settings: Settings | None = None,
) -> ProcessedDocument:
    settings = settings or get_settings()
    return DocumentProcessor(settings).process_bytes(
        file_bytes,
        source_file_name,
        doc_type,
        upload_id=upload_id,
        blob_path=blob_path,
    )
