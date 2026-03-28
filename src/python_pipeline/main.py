import argparse
from ast import arg
import json

from config import get_settings
from processor import DocumentProcessor


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
    
    processor = DocumentProcessor(settings)
    processed = processor.process_file(args.file, args.doc_type)
    print(json.dumps(processed.model_dump(), indent=2, ensure_ascii=True))
    #print(args)
    #print(settings)


if __name__ == "__main__":
    main()
