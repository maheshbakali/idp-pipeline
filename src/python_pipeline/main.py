import argparse
import json

from config import get_settings
from pipeline_runner import process_document_from_file

# CLI entry point: parses arguments and runs the pipeline; prints enriched JSON to stdout.
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Process a document with Azure Document Intelligence + GPT enrichment."
    )
    parser.add_argument("--file", required=True, help="Path to input file")
    parser.add_argument(
        "--doc-type",
        required=True,
        choices=["invoice", "contract", "receipt", "other"],
        help="Logical document type",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    settings = get_settings()
    processed = process_document_from_file(args.file, args.doc_type, settings=settings)
    print(json.dumps(processed.model_dump(), indent=2, ensure_ascii=True))


if __name__ == "__main__":
    main()
