using System.Security.Cryptography;
using KLOP.Platform.Application;
using KLOP.Platform.Infrastructure;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;
using Xunit;

namespace KLOP.Platform.UnitTests;

public sealed class RegistrationEnhancementTests
{
    [Fact]
    public void RegistrationTypeCodesAcceptOnlyAgreedTypes()
    {
        Assert.True(RegistrationTypeCodes.IsSupported(" personal "));
        Assert.True(RegistrationTypeCodes.IsSupported("ORGANIZATION"));
        Assert.False(RegistrationTypeCodes.IsSupported("ADMIN"));
        Assert.False(RegistrationTypeCodes.IsSupported(null));
        Assert.Equal("ORGANIZATION", RegistrationTypeCodes.Normalize(" organization "));
    }

    [Fact]
    public void RowVersionCodecAcceptsExactlyEightDecodedBytes()
    {
        var expected = new byte[] { 0, 1, 2, 3, 4, 5, 6, 7 };
        var encoded = Convert.ToBase64String(expected);

        Assert.True(RowVersionCodec.TryDecode(encoded, out var actual));
        Assert.Equal(expected, actual);
        Assert.False(RowVersionCodec.TryDecode("not-base64", out _));
        Assert.False(RowVersionCodec.TryDecode(Convert.ToBase64String([1, 2, 3]), out _));
        Assert.False(RowVersionCodec.TryDecode(null, out _));
    }

    [Fact]
    public async Task LegalStorageReturnsOnlyPdfWithMatchingRecordedHash()
    {
        var root = Path.Combine(Path.GetTempPath(), $"klop-legal-{Guid.NewGuid():N}");
        var contentRoot = Path.Combine(Path.GetTempPath(), $"klop-app-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        Directory.CreateDirectory(contentRoot);
        var id = Guid.NewGuid();
        var document = "%PDF-1.7\nregistration terms\n"u8.ToArray();
        var file = Path.Combine(root, $"{id:N}.pdf");
        await File.WriteAllBytesAsync(file, document);
        var hash = SHA256.HashData(document);
        var storage = CreateStorage(root, contentRoot);

        try
        {
            await using var stream = await storage.OpenPdf(id.ToString("N"), document.Length,
                document.Length, hash, CancellationToken.None);
            using var actual = new MemoryStream();
            await stream.CopyToAsync(actual);
            Assert.Equal(document, actual.ToArray());

            await Assert.ThrowsAsync<LegalDocumentStorageUnavailableException>(() =>
                storage.OpenPdf(id.ToString("N"), document.Length, document.Length,
                    new byte[32], CancellationToken.None));
            await Assert.ThrowsAsync<LegalDocumentStorageUnavailableException>(() =>
                storage.OpenPdf("..\\untrusted", document.Length, document.Length,
                    hash, CancellationToken.None));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
            Directory.Delete(contentRoot, recursive: true);
        }
    }

    private static FileSystemLegalDocumentStorage CreateStorage(string root, string contentRoot)
    {
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(
            new Dictionary<string, string?> { ["LegalDocuments:StorageRoot"] = root }).Build();
        return new FileSystemLegalDocumentStorage(configuration, new TestHostEnvironment(contentRoot));
    }

    private sealed class TestHostEnvironment(string contentRoot) : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = "UnitTest";
        public string ApplicationName { get; set; } = "KLOP.Platform.UnitTests";
        public string ContentRootPath { get; set; } = contentRoot;
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    }
}
