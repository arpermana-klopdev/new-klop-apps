using System.Text;
using KLOP.Platform.Application;
using KLOP.Platform.Infrastructure;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;
using Xunit;

namespace KLOP.Platform.UnitTests;

public sealed class FileSystemLegalDocumentStorageTests
{
    [Fact]
    public async Task SaveAndOpenPdfValidatesTheStoredBytesAndHash()
    {
        var root = CreatePrivateRoot();
        try
        {
            var storage = CreateStorage(root);
            var bytes = Encoding.ASCII.GetBytes("%PDF-1.7\nTerms content");
            var stored = await storage.SavePdf(new MemoryStream(bytes), bytes.Length, 1024,
                CancellationToken.None);

            Assert.Equal(32, stored.StorageReference.Length);
            Assert.Equal(bytes.Length, stored.FileSizeBytes);
            Assert.Equal(32, stored.ContentHash.Length);

            await using var opened = await storage.OpenPdf(stored.StorageReference, stored.FileSizeBytes,
                1024, stored.ContentHash, CancellationToken.None);
            using var copy = new MemoryStream();
            await opened.CopyToAsync(copy);
            Assert.Equal(bytes, copy.ToArray());
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public async Task SaveRejectsContentWithoutPdfSignature()
    {
        var root = CreatePrivateRoot();
        try
        {
            var storage = CreateStorage(root);
            var bytes = Encoding.ASCII.GetBytes("not a PDF");

            await Assert.ThrowsAsync<LegalDocumentStorageValidationException>(() =>
                storage.SavePdf(new MemoryStream(bytes), bytes.Length, 1024, CancellationToken.None));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public async Task OpenRejectsStoredPdfWhenItsHashNoLongerMatches()
    {
        var root = CreatePrivateRoot();
        try
        {
            var storage = CreateStorage(root);
            var bytes = Encoding.ASCII.GetBytes("%PDF-1.7\nTerms content");
            var stored = await storage.SavePdf(new MemoryStream(bytes), bytes.Length, 1024,
                CancellationToken.None);
            var path = Path.Combine(root, $"{stored.StorageReference}.pdf");
            await File.WriteAllBytesAsync(path, Encoding.ASCII.GetBytes("%PDF-1.7\nOther content"));

            await Assert.ThrowsAsync<LegalDocumentStorageUnavailableException>(() =>
                storage.OpenPdf(stored.StorageReference, stored.FileSizeBytes, 1024, stored.ContentHash,
                    CancellationToken.None));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    private static FileSystemLegalDocumentStorage CreateStorage(string root)
    {
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["LegalDocuments:StorageRoot"] = root
            })
            .Build();
        return new FileSystemLegalDocumentStorage(configuration, new TestHostEnvironment(root));
    }

    private static string CreatePrivateRoot()
    {
        var root = Path.Combine(Path.GetTempPath(), $"klop-legal-documents-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        return root;
    }

    private sealed class TestHostEnvironment(string contentRoot) : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = "Testing";
        public string ApplicationName { get; set; } = "KLOP.Platform.UnitTests";
        public string ContentRootPath { get; set; } = contentRoot;
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    }
}
