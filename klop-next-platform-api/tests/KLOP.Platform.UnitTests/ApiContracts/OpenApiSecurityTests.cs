using KLOP.Platform.Api;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc.Abstractions;
using Microsoft.AspNetCore.Mvc.ApiExplorer;
using Microsoft.AspNetCore.OpenApi;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.OpenApi;
using Xunit;

namespace KLOP.Platform.UnitTests;

public sealed class OpenApiSecurityTests
{
    [Fact]
    public async Task DocumentContainsHttpBearerScheme()
    {
        var document = new OpenApiDocument();
        var context = new OpenApiDocumentTransformerContext
        {
            DocumentName = "v1",
            DescriptionGroups = [],
            ApplicationServices = new ServiceCollection().BuildServiceProvider()
        };

        await new BearerSecurityDocumentTransformer().TransformAsync(document, context, CancellationToken.None);

        var scheme = Assert.IsType<OpenApiSecurityScheme>(document.Components!.SecuritySchemes!["Bearer"]);
        Assert.Equal(SecuritySchemeType.Http, scheme.Type);
        Assert.Equal("bearer", scheme.Scheme);
        Assert.Equal("JWT", scheme.BearerFormat);
    }

    [Theory]
    [InlineData(false, false, false)]
    [InlineData(true, false, true)]
    [InlineData(true, true, false)]
    public async Task SecurityRequirementFollowsAuthorizationMetadata(bool authorized, bool anonymous, bool expected)
    {
        var metadata = new List<object>();
        if (authorized) metadata.Add(new AuthorizeAttribute());
        if (anonymous) metadata.Add(new AllowAnonymousAttribute());
        var document = new OpenApiDocument();
        var operation = new OpenApiOperation();
        var context = new OpenApiOperationTransformerContext
        {
            DocumentName = "v1",
            Document = document,
            Description = new ApiDescription { ActionDescriptor = new ActionDescriptor { EndpointMetadata = metadata } },
            ApplicationServices = new ServiceCollection().BuildServiceProvider()
        };

        await new BearerSecurityOperationTransformer().TransformAsync(operation, context, CancellationToken.None);

        Assert.Equal(expected, operation.Security?.Count > 0);
        if (expected)
            Assert.Equal("Bearer", Assert.Single(Assert.Single(operation.Security!).Keys).Reference.Id);
    }
}
