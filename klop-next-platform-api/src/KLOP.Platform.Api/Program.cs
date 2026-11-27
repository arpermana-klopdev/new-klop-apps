using KLOP.Platform.Api.Bootstrap;
using KLOP.Platform.Api.Endpoints;
using KLOP.Platform.Application;
using Microsoft.Extensions.DependencyInjection;

var builder = WebApplication.CreateBuilder(args);
await builder.AddPlatformServicesAsync();

var app = builder.Build();
app.UsePlatformRequestPipeline(builder.Environment);
app.MapPlatformEndpoints(app.Services.GetRequiredService<IPlatformRuntimeSettings>());
app.Run();

public partial class Program { }
