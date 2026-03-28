from typing import Any

from azure.cosmos import CosmosClient, PartitionKey
from azure.cosmos.exceptions import CosmosResourceNotFoundError

from config import Settings


class CosmosRepository:
    def __init__(self, settings: Settings) -> None:
        self.client = CosmosClient(settings.cosmos_endpoint, settings.cosmos_key)
        self.database = self.client.create_database_if_not_exists(id=settings.cosmos_database)
        self.container = self.database.create_container_if_not_exists(
            id=settings.cosmos_container,
            partition_key=PartitionKey(path="/partitionKey"),
        )
        self.myvar = settings.cosmos_key

    def upsert(self, item: dict[str, Any]) -> dict[str, Any]:
        return self.container.upsert_item(body=item)

    def get_by_id(self, item_id: str, partition_key: str) -> dict[str, Any] | None:
        try:
            return self.container.read_item(item=item_id, partition_key=partition_key)
        except CosmosResourceNotFoundError:
            return None
