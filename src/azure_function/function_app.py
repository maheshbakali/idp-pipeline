"""
Blob-triggered Azure Function: runs the IDP pipeline when a file lands in the uploads container.

Expected blob path (relative to container): {docType}/{uploadId}/{fileName}
Example: invoice/a1b2c3d4-e5f6-7890-abcd-ef1234567890/scan.pdf
"""

from __future__ import annotations

import logging
import sys
from pathlib import Path

import azure.functions as func

_here = Path(__file__).resolve().parent
for _p in (_here / "python_pipeline", _here.parent / "python_pipeline"):
    if (_p / "pipeline_runner.py").is_file():
        if str(_p) not in sys.path:
            sys.path.insert(0, str(_p))
        break
else:
    raise ImportError("python_pipeline package not found next to or under the function app root")

from pipeline_runner import process_document_from_bytes  # noqa: E402

ALLOWED_DOC_TYPES = frozenset({"invoice", "receipt", "contract", "other"})

app = func.FunctionApp()


@app.function_name(name="ProcessBlobUpload")
@app.blob_trigger(
    arg_name="blob",
    path="uploads/{name}",
    connection="AzureWebJobsStorage",
)
def process_blob_upload(blob: func.InputStream) -> None:
    logger = logging.getLogger("ProcessBlobUpload")
    name = blob.name or ""
    blob_path = f"uploads/{name}"
    parts = name.strip("/").split("/")
    if len(parts) < 3:
        logger.error("Invalid blob path (expected docType/uploadId/fileName): %s", blob_path)
        return

    doc_type, upload_id, source_name = parts[0], parts[1], "/".join(parts[2:])
    if doc_type not in ALLOWED_DOC_TYPES:
        logger.error("Unsupported docType %r in path %s", doc_type, blob_path)
        return

    try:
        data = blob.read()
        if not data:
            logger.error("Empty blob: %s", blob_path)
            return
    except Exception:
        logger.exception("Failed to read blob %s", blob_path)
        raise

    try:
        processed = process_document_from_bytes(
            data,
            source_name,
            doc_type,
            upload_id=upload_id,
            blob_path=blob_path,
        )
        logger.info(
            "Processed uploadId=%s cosmosId=%s docType=%s",
            upload_id,
            processed.id,
            doc_type,
        )
    except Exception:
        logger.exception("Pipeline failed for blob %s", blob_path)
        raise
