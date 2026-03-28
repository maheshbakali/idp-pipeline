from dataclasses import dataclass
import os

from dotenv import load_dotenv


load_dotenv()


@dataclass(frozen=True)
class Settings:
    document_intelligence_endpoint: str = os.getenv("DOCUMENT_INTELLIGENCE_ENDPOINT", "")
    document_intelligence_key: str = os.getenv("DOCUMENT_INTELLIGENCE_KEY", "")
    document_intelligence_model: str = os.getenv(
        "DOCUMENT_INTELLIGENCE_MODEL", "prebuilt-document"
    )

    azure_openai_endpoint: str = os.getenv("AZURE_OPENAI_ENDPOINT", "")
    azure_openai_api_key: str = os.getenv("AZURE_OPENAI_API_KEY", "")
    azure_openai_deployment: str = os.getenv("AZURE_OPENAI_DEPLOYMENT", "gpt-4o")
    azure_openai_api_version: str = os.getenv("AZURE_OPENAI_API_VERSION", "2024-06-01")

    cosmos_endpoint: str = os.getenv("COSMOS_ENDPOINT", "")
    cosmos_key: str = os.getenv("COSMOS_KEY", "")
    cosmos_database: str = os.getenv("COSMOS_DATABASE", "idp")
    cosmos_container: str = os.getenv("COSMOS_CONTAINER", "documents")


def get_settings() -> Settings:
    return Settings()
