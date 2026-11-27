FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
ENV ASPNETCORE_HTTP_PORTS=8080
EXPOSE 8080
USER $APP_UID

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY Directory.Build.props ./
COPY src/KLOP.Platform.Domain/KLOP.Platform.Domain.csproj src/KLOP.Platform.Domain/
COPY src/KLOP.Platform.Application/KLOP.Platform.Application.csproj src/KLOP.Platform.Application/
COPY src/KLOP.Platform.Infrastructure/KLOP.Platform.Infrastructure.csproj src/KLOP.Platform.Infrastructure/
COPY src/KLOP.Platform.Api/KLOP.Platform.Api.csproj src/KLOP.Platform.Api/
RUN dotnet restore src/KLOP.Platform.Api/KLOP.Platform.Api.csproj
COPY src/ src/
RUN dotnet publish src/KLOP.Platform.Api/KLOP.Platform.Api.csproj \
    --configuration Release --no-restore --output /app/publish /p:UseAppHost=false

FROM runtime AS final
WORKDIR /app
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "KLOP.Platform.Api.dll"]
