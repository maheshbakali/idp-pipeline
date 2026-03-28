import json
from typing import Any

from azure.ai.documentintelligence import DocumentIntelligenceClient
from azure.core.credentials import AzureKeyCredential
from openai import AzureOpenAI

from config import Settings


def create_document_intelligence_client(settings: Settings) -> DocumentIntelligenceClient:
    return DocumentIntelligenceClient(
        endpoint=settings.document_intelligence_endpoint,
        credential=AzureKeyCredential(settings.document_intelligence_key),
    )


def create_azure_openai_client(settings: Settings) -> AzureOpenAI:
    endpoint = settings.azure_openai_endpoint.strip().rstrip("/")
    # Accept either resource root or full API base URL from .env.
    for suffix in ("/openai/v1", "/openai"):
        if endpoint.lower().endswith(suffix):
            endpoint = endpoint[: -len(suffix)]
            break

    return AzureOpenAI(
        api_key=settings.azure_openai_api_key,
        api_version=settings.azure_openai_api_version,
        azure_endpoint=endpoint,
    )


def extract_with_document_intelligence(
    client: DocumentIntelligenceClient,
    model_id: str,
    file_bytes: bytes,
) -> dict[str, Any]:
    poller = client.begin_analyze_document(model_id=model_id, body=file_bytes)
    result = poller.result()

    documents = []
    for doc in result.documents or []:
        fields: dict[str, Any] = {}
        for key, field in (doc.fields or {}).items():
            # SDK shape differs by version: older builds expose value_type, newer ones expose type.
            field_type = getattr(field, "value_type", None) or getattr(field, "type", None)
            fields[key] = {
                "content": field.content,
                "confidence": field.confidence,
                "type": str(field_type),
            }
        documents.append({"doc_type": doc.doc_type, "fields": fields})

    pages = []
    for page in result.pages or []:
        pages.append(
            {
                "page_number": page.page_number,
                "width": page.width,
                "height": page.height,
                "unit": page.unit,
            }
        )

    return {"documents": documents, "pages": pages, "content": result.content}


def enrich_with_gpt(
    client: AzureOpenAI,
    deployment: str,
    doc_type: str,
    extracted_payload: dict[str, Any],
    prompt_template: str,
) -> dict[str, Any]:
    user_prompt = prompt_template.format(
        doc_type=doc_type,
        extracted_json=json.dumps(extracted_payload, ensure_ascii=True),
    )

    response = client.chat.completions.create(
        model=deployment,
        temperature=0.1,
        response_format={"type": "json_object"},
        messages=[
            {"role": "system", "content": "You are a precise document enrichment assistant."},
            {"role": "user", "content": user_prompt},
        ],
    )

    message_content = response.choices[0].message.content
    return json.loads(message_content)
