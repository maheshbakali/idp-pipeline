using Microsoft.Azure.Cosmos;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var cosmosConfig = builder.Configuration.GetSection("Cosmos");
var endpoint = cosmosConfig["Endpoint"] ?? "";
var key = cosmosConfig["Key"] ?? "";
var database = cosmosConfig["Database"] ?? "idp";
var container = cosmosConfig["Container"] ?? "documents";

builder.Services.AddSingleton(new CosmosClient(endpoint, key));

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.MapGet("/health", () => Results.Ok(new { status = "ok", service = "project1-api" }));

app.MapGet("/documents/{id}", async (string id, string documentId, CosmosClient cosmosClient) =>
{
    var c = cosmosClient.GetContainer(database, container);

    // partitionKey is set to docType by the Python pipeline
    // (documentId is currently also set to docType, but kept for backward compatibility)
    try
    {
        var item = await c.ReadItemAsync<dynamic>(id, new PartitionKey(documentId));
        return Results.Ok(item.Resource);
    }
    catch (CosmosException ex) when (ex.StatusCode == System.Net.HttpStatusCode.NotFound)
    {
        return Results.NotFound(new { message = "Document not found", id, documentId });
    }
});

app.MapGet("/documents", async (string? docType, CosmosClient cosmosClient) =>
{
    var c = cosmosClient.GetContainer(database, container);

    var query = string.IsNullOrWhiteSpace(docType)
        ? "SELECT * FROM c"
        : "SELECT * FROM c WHERE c.docType = @docType";

    var qd = new QueryDefinition(query);
    if (!string.IsNullOrWhiteSpace(docType))
    {
        qd.WithParameter("@docType", docType);
    }

    var iterator = c.GetItemQueryIterator<dynamic>(qd);
    var results = new List<dynamic>();

    while (iterator.HasMoreResults)
    {
        var page = await iterator.ReadNextAsync();
        results.AddRange(page.Resource);
    }

    return Results.Ok(results);
});

app.Run();
