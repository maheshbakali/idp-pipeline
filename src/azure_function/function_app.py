"""
Blob-triggered Azure Function: runs the IDP pipeline when a file lands in the uploads container.

Expected blob path (relative to container): {docType}/{uploadId}/{fileName}
Example: invoice/a1b2c3d4-e5f6-7890-abcd-ef1234567890/scan.pdf
"""

from __future__ import annotations

import json
import logging
import sys
import time
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
_UPLOADS_CONTAINER = "uploads"


def _blob_path_under_uploads_container(blob_name: str) -> tuple[str, str]:
    """
    Return (relative_path, full_path_for_logs) where relative_path is
    docType/uploadId/fileName inside the uploads container.

    The Functions runtime sometimes sets blob.name to either:
    - invoice/<uploadId>/file.pdf (path under the container), or
    - uploads/invoice/<uploadId>/file.pdf (container prefix duplicated with binding path).
    """
    raw = (blob_name or "").strip("/")
    rel = raw
    prefix = f"{_UPLOADS_CONTAINER}/"
    while rel.startswith(prefix):
        rel = rel[len(prefix) :]
    full = f"{_UPLOADS_CONTAINER}/{rel}" if rel else _UPLOADS_CONTAINER
    return rel, full


app = func.FunctionApp()

# region agent log
_DEBUG_LOG = _here.parent.parent / "debug-ec444b.log"


def _agent_log(hypothesis_id: str, location: str, message: str, data: dict) -> None:
    try:
        line = json.dumps(
            {
                "sessionId": "ec444b",
                "timestamp": int(time.time() * 1000),
                "hypothesisId": hypothesis_id,
                "location": location,
                "message": message,
                "data": data,
                "runId": "pre-fix",
            },
            default=str,
        )
        with open(_DEBUG_LOG, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass


# endregion


@app.function_name(name="ProcessBlobUpload")
@app.blob_trigger(
    arg_name="blob",
    path="uploads/{name}",
    connection="AzureWebJobsStorage",
)
def process_blob_upload(blob: func.InputStream) -> None:
    logger = logging.getLogger("ProcessBlobUpload")
    name = blob.name or ""
    rel_path, blob_path = _blob_path_under_uploads_container(name)
    # region agent log
    _agent_log(
        "H1",
        "function_app.py:process_blob_upload:entry",
        "blob_trigger_invoked",
        {
            "blob_name": name,
            "blob_path": blob_path,
            "rel_path": rel_path,
            "length_attr": getattr(blob, "length", None),
        },
    )
    # endregion
    parts = rel_path.strip("/").split("/")
    if len(parts) < 3:
        logger.error("Invalid blob path (expected docType/uploadId/fileName): %s", blob_path)
        # region agent log
        _agent_log(
            "H3",
            "function_app.py:process_blob_upload:path_parts",
            "invalid_path_too_few_parts",
            {"blob_path": blob_path, "part_count": len(parts), "parts": parts},
        )
        # endregion
        return

    doc_type, upload_id, source_name = parts[0], parts[1], "/".join(parts[2:])
    if doc_type not in ALLOWED_DOC_TYPES:
        logger.error("Unsupported docType %r in path %s", doc_type, blob_path)
        # region agent log
        _agent_log(
            "H3",
            "function_app.py:process_blob_upload:doc_type",
            "doc_type_rejected",
            {"blob_path": blob_path, "doc_type": doc_type},
        )
        # endregion
        return

    try:
        data = blob.read()
        if not data:
            logger.error("Empty blob: %s", blob_path)
            # region agent log
            _agent_log(
                "H4",
                "function_app.py:process_blob_upload:read",
                "empty_blob",
                {"blob_path": blob_path},
            )
            # endregion
            return
    except Exception:
        logger.exception("Failed to read blob %s", blob_path)
        raise

    # region agent log
    _agent_log(
        "H4",
        "function_app.py:process_blob_upload:before_pipeline",
        "blob_read_ok",
        {
            "blob_path": blob_path,
            "doc_type": doc_type,
            "upload_id": upload_id,
            "byte_len": len(data),
        },
    )
    # endregion
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
        # region agent log
        _agent_log(
            "H5",
            "function_app.py:process_blob_upload:success",
            "pipeline_completed",
            {"blob_path": blob_path, "upload_id": upload_id, "cosmos_id": str(processed.id)},
        )
        # endregion
    except Exception:
        logger.exception("Pipeline failed for blob %s", blob_path)
        # region agent log
        _agent_log(
            "H5",
            "function_app.py:process_blob_upload:pipeline_error",
            "pipeline_exception",
            {"blob_path": blob_path, "exc_type": type(sys.exc_info()[1]).__name__},
        )
        # endregion
        raise
