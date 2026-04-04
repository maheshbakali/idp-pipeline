using System.Threading.RateLimiting;
using Azure.Storage.Blobs;
using Project1.Api;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Cosmos;
using Microsoft.OpenApi.Models;

var builder = WebApplication.CreateBuilder(args);

builder.WebHost.ConfigureKestrel(options =>
{
    options.Limits.MaxRequestBodySize = UploadValidation.MaxBytes + 512 * 1024;
});

builder.Services.Configure<FormOptions>(options =>
{
    options.MultipartBodyLengthLimit = UploadValidation.MaxBytes + 256 * 1024;
});

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo { Title = "IDP API", Version = "v1" });
});

var cosmosSection = builder.Configuration.GetSection("Cosmos");
var cosmosEndpoint = cosmosSection["Endpoint"] ?? "";
var cosmosKey = cosmosSection["Key"] ?? "";
var cosmosDatabase = cosmosSection["Database"] ?? "idp";
var cosmosContainerName = cosmosSection["Container"] ?? "documents";

builder.Services.AddSingleton(_ => new CosmosClient(cosmosEndpoint, cosmosKey));

var blobConnection = builder.Configuration["Blob:ConnectionString"];
var blobContainerName = builder.Configuration["Blob:ContainerName"] ?? "uploads";
if (!string.IsNullOrWhiteSpace(blobConnection))
{
    builder.Services.AddSingleton(_ => new BlobServiceClient(blobConnection));
}

var corsOrigins = builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? Array.Empty<string>();
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        if (corsOrigins.Length == 0)
        {
            policy.AllowAnyOrigin().AllowAnyMethod().AllowAnyHeader();
        }
        else
        {
            policy.WithOrigins(corsOrigins).AllowAnyMethod().AllowAnyHeader();
        }
    });
});

builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.AddPolicy("upload", context =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            factory: _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 30,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0,
                AutoReplenishment = true,
            }));
});

var app = builder.Build();

app.UseCors();
app.UseRateLimiter();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseDefaultFiles();
app.UseStaticFiles();

app.MapGet("/health", () => Results.Ok(new { status = "ok", service = "project1-api" }));

/// Cross-partition lookup by Cosmos item id (recommended for clients).
app.MapGet("/documents/{id}", async (string id, CosmosClient cosmosClient) =>
{
    var container = cosmosClient.GetContainer(cosmosDatabase, cosmosContainerName);
    var query = new QueryDefinition("SELECT * FROM c WHERE c.id = @id").WithParameter("@id", id);
    using var iterator = container.GetItemQueryIterator<dynamic>(query);

    while (iterator.HasMoreResults)
    {
        var page = await iterator.ReadNextAsync();
        foreach (var doc in page)
            return Results.Ok(doc);
    }

    return Results.NotFound(new { message = "Document not found", id });
});

/// Poll this after upload until processing completes (200) or continue polling on 404.
app.MapGet("/documents/by-upload/{uploadId}", async (string uploadId, CosmosClient cosmosClient) =>
{
    var container = cosmosClient.GetContainer(cosmosDatabase, cosmosContainerName);
    var query = new QueryDefinition("SELECT * FROM c WHERE c.uploadId = @u").WithParameter("@u", uploadId);
    using var iterator = container.GetItemQueryIterator<dynamic>(query);

    while (iterator.HasMoreResults)
    {
        var page = await iterator.ReadNextAsync();
        foreach (var doc in page)
            return Results.Ok(doc);
    }

    return Results.NotFound(new
    {
        message = "Not ready yet or unknown uploadId. The blob trigger may still be processing.",
        uploadId,
    });
});

app.MapGet("/documents", async (string? docType, CosmosClient cosmosClient) =>
{
    var container = cosmosClient.GetContainer(cosmosDatabase, cosmosContainerName);

    var query = string.IsNullOrWhiteSpace(docType)
        ? "SELECT * FROM c"
        : "SELECT * FROM c WHERE c.docType = @docType";

    var qd = new QueryDefinition(query);
    if (!string.IsNullOrWhiteSpace(docType))
        qd.WithParameter("@docType", docType);

    var iterator = container.GetItemQueryIterator<dynamic>(qd);
    var results = new List<dynamic>();

    while (iterator.HasMoreResults)
    {
        var page = await iterator.ReadNextAsync();
        results.AddRange(page.Resource);
    }

    return Results.Ok(results);
});

app.MapPost("/documents/upload", async Task<IResult> (
        HttpRequest request,
        [FromServices] IServiceProvider sp,
        CancellationToken cancellationToken) =>
    {
        var blobClient = sp.GetService(typeof(BlobServiceClient)) as BlobServiceClient;
        if (blobClient is null)
            return Results.Problem(
                detail: "Blob storage is not configured. Set Blob:ConnectionString.",
                statusCode: StatusCodes.Status503ServiceUnavailable);

        if (!request.HasFormContentType)
            return Results.BadRequest(new { message = "Expected multipart/form-data with fields docType and file." });

        var form = await request.ReadFormAsync(cancellationToken);
        var docType = form["docType"].ToString();
        if (!UploadValidation.AllowedDocTypes.Contains(docType))
        {
            return Results.BadRequest(new
            {
                message = "Invalid docType.",
                allowed = UploadValidation.AllowedDocTypes,
            });
        }

        var file = form.Files.GetFile("file");
        if (file is null || file.Length == 0)
            return Results.BadRequest(new { message = "Missing non-empty file field 'file'." });

        if (file.Length > UploadValidation.MaxBytes)
        {
            return Results.BadRequest(new
            {
                message = $"File exceeds maximum size of {UploadValidation.MaxBytes} bytes.",
                maxBytes = UploadValidation.MaxBytes,
            });
        }

        var safeName = UploadValidation.SanitizeFileName(file.FileName);
        var ext = Path.GetExtension(safeName);
        if (!UploadValidation.AllowedExtensions.Contains(ext))
        {
            return Results.BadRequest(new
            {
                message = "Only PDF and image uploads are allowed.",
                allowedExtensions = UploadValidation.AllowedExtensions,
            });
        }

        await using var buffer = new MemoryStream(capacity: (int)Math.Min(file.Length, UploadValidation.MaxBytes));
        await file.CopyToAsync(buffer, cancellationToken);
        if (buffer.Length > UploadValidation.MaxBytes)
        {
            return Results.BadRequest(new
            {
                message = $"File exceeds maximum size of {UploadValidation.MaxBytes} bytes.",
                maxBytes = UploadValidation.MaxBytes,
            });
        }

        var headerLen = (int)Math.Min(12, buffer.Length);
        var headerBuf = new byte[headerLen];
        buffer.Position = 0;
        _ = await buffer.ReadAsync(headerBuf.AsMemory(0, headerLen), cancellationToken);
        buffer.Position = 0;
        if (!UploadValidation.IsAllowedContent(headerBuf.AsSpan(0, headerLen), ext))
            return Results.BadRequest(new { message = "File content does not match an allowed PDF or image type." });

        var uploadId = Guid.NewGuid().ToString("D");
        var blobPath = $"{docType}/{uploadId}/{safeName}";
        var container = blobClient.GetBlobContainerClient(blobContainerName);
        await container.CreateIfNotExistsAsync(cancellationToken: cancellationToken);

        var blob = container.GetBlobClient(blobPath);
        await blob.UploadAsync(buffer, overwrite: true, cancellationToken);

        var fullBlobPath = $"{blobContainerName}/{blobPath}";
        return Results.Accepted(
            uri: null,
            value: new
            {
                uploadId,
                blobPath = fullBlobPath,
                docType,
                pollUrl = $"/documents/by-upload/{uploadId}",
                message = "Upload accepted. Poll pollUrl until the document appears (Azure Function processing).",
            });
    })
    .DisableAntiforgery()
    .RequireRateLimiting("upload");

app.Run();
