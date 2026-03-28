FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

COPY ["dotnet-api/Project1.Api.csproj", "dotnet-api/"]
RUN dotnet restore "dotnet-api/Project1.Api.csproj"

COPY . .
RUN dotnet publish "dotnet-api/Project1.Api.csproj" -c Release -o /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
ENV ASPNETCORE_URLS=http://0.0.0.0:8080
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "Project1.Api.dll"]

