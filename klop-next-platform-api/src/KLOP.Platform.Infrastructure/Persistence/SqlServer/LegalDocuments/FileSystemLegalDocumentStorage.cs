using System.Security.Cryptography;
using KLOP.Platform.Application;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;

namespace KLOP.Platform.Infrastructure;

public sealed class FileSystemLegalDocumentStorage(IConfiguration configuration, IHostEnvironment environment)
    : ILegalDocumentStorage
{
    public async Task<StoredLegalDocument> SavePdf(
        Stream source, long expectedSizeBytes, long maximumSizeBytes, CancellationToken cancellationToken)
    {
        if (!source.CanRead || expectedSizeBytes <= 0 || expectedSizeBytes > maximumSizeBytes ||
            maximumSizeBytes <= 0)
            throw new LegalDocumentStorageValidationException(
                "LEGAL_FILE_INVALID", "The PDF size is outside the allowed limit.");

        var root = GetPrivateStorageRoot();
        var storageId = Guid.NewGuid();
        var temporaryPath = ResolveStoragePath(root, $".{storageId:N}.tmp");
        var finalPath = ResolveStoragePath(root, $"{storageId:N}.pdf");
        var fileStored = false;
        var prefix = new byte[5];
        var prefixLength = 0;
        long totalBytes = 0;

        try
        {
            using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
            await using (var output = new FileStream(temporaryPath, FileMode.CreateNew, FileAccess.Write,
                FileShare.None, 81920, FileOptions.Asynchronous | FileOptions.SequentialScan))
            {
                var buffer = new byte[81920];
                while (true)
                {
                    var read = await source.ReadAsync(buffer.AsMemory(), cancellationToken);
                    if (read == 0)
                        break;

                    totalBytes += read;
                    if (totalBytes > maximumSizeBytes)
                        throw new LegalDocumentStorageValidationException(
                            "LEGAL_FILE_INVALID", "The PDF exceeds the configured size limit.");

                    if (prefixLength < prefix.Length)
                    {
                        var copyLength = Math.Min(prefix.Length - prefixLength, read);
                        buffer.AsSpan(0, copyLength).CopyTo(prefix.AsSpan(prefixLength));
                        prefixLength += copyLength;
                    }

                    hash.AppendData(buffer, 0, read);
                    await output.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
                }

                await output.FlushAsync(cancellationToken);
            }

            if (totalBytes != expectedSizeBytes || prefixLength != prefix.Length ||
                !prefix.AsSpan().SequenceEqual("%PDF-"u8))
                throw new LegalDocumentStorageValidationException(
                    "LEGAL_FILE_INVALID", "The uploaded file is not a complete PDF.");

            var contentHash = hash.GetHashAndReset();
            File.Move(temporaryPath, finalPath);
            fileStored = true;
            return new StoredLegalDocument(storageId.ToString("N"), totalBytes, contentHash);
        }
        catch (IOException)
        {
            throw new LegalDocumentStorageUnavailableException("Legal document storage is unavailable.");
        }
        catch (UnauthorizedAccessException)
        {
            throw new LegalDocumentStorageUnavailableException("Legal document storage is unavailable.");
        }
        finally
        {
            if (!fileStored && File.Exists(temporaryPath))
                File.Delete(temporaryPath);
        }
    }

    public async Task<Stream> OpenPdf(string storageReference, long expectedSizeBytes, long maximumSizeBytes,
        byte[] expectedSha256, CancellationToken cancellationToken)
    {
        if (!Guid.TryParseExact(storageReference, "N", out var storageId) || expectedSizeBytes <= 0 ||
            expectedSizeBytes > maximumSizeBytes || expectedSha256.Length != 32)
            throw new LegalDocumentStorageUnavailableException("Legal document storage metadata is invalid.");

        var root = GetPrivateStorageRoot();
        var path = ResolveStoragePath(root, $"{storageId:N}.pdf");

        FileStream stream;
        var returnStream = false;
        try
        {
            stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 81920,
                FileOptions.Asynchronous | FileOptions.SequentialScan);
        }
        catch (FileNotFoundException exception)
        {
            throw new LegalDocumentStorageUnavailableException(exception.GetType().Name);
        }
        catch (DirectoryNotFoundException exception)
        {
            throw new LegalDocumentStorageUnavailableException(exception.GetType().Name);
        }

        try
        {
            if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0 ||
                stream.Length != expectedSizeBytes || stream.Length > maximumSizeBytes)
                throw new LegalDocumentStorageUnavailableException("Legal document integrity validation failed.");

            var signature = new byte[5];
            var signatureRead = await stream.ReadAsync(signature, cancellationToken);
            if (signatureRead != signature.Length || !signature.AsSpan().SequenceEqual("%PDF-"u8))
                throw new LegalDocumentStorageUnavailableException("Legal document integrity validation failed.");

            stream.Position = 0;
            var actualHash = await SHA256.HashDataAsync(stream, cancellationToken);
            if (!CryptographicOperations.FixedTimeEquals(actualHash, expectedSha256))
                throw new LegalDocumentStorageUnavailableException("Legal document integrity validation failed.");

            stream.Position = 0;
            returnStream = true;
            return stream;
        }
        catch (IOException exception)
        {
            throw new LegalDocumentStorageUnavailableException(exception.GetType().Name);
        }
        catch (UnauthorizedAccessException exception)
        {
            throw new LegalDocumentStorageUnavailableException(exception.GetType().Name);
        }
        finally
        {
            if (!returnStream)
                await stream.DisposeAsync();
        }
    }

    public Task DeletePdf(string storageReference, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (!Guid.TryParseExact(storageReference, "N", out var storageId))
            throw new LegalDocumentStorageUnavailableException("Legal document storage metadata is invalid.");

        var root = GetPrivateStorageRoot();
        var path = ResolveStoragePath(root, $"{storageId:N}.pdf");
        if (File.Exists(path))
        {
            if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
                throw new LegalDocumentStorageUnavailableException("Legal document storage reference is invalid.");
            File.Delete(path);
        }
        return Task.CompletedTask;
    }

    private string GetPrivateStorageRoot()
    {
        var rootValue = configuration["LegalDocuments:StorageRoot"];
        if (string.IsNullOrWhiteSpace(rootValue) || !Path.IsPathFullyQualified(rootValue))
            throw new LegalDocumentStorageUnavailableException("Legal document storage is not configured.");

        var root = Path.TrimEndingDirectorySeparator(Path.GetFullPath(rootValue));
        if (!Directory.Exists(root))
            throw new LegalDocumentStorageUnavailableException("Legal document storage is unavailable.");

        var publicRoot = Path.TrimEndingDirectorySeparator(
            Path.GetFullPath(Path.Combine(environment.ContentRootPath, "wwwroot")));
        var comparison = OperatingSystem.IsWindows()
            ? StringComparison.OrdinalIgnoreCase
            : StringComparison.Ordinal;
        if (IsSameOrWithin(root, publicRoot, comparison))
            throw new LegalDocumentStorageUnavailableException("Legal document storage must not be public web content.");

        for (var directory = new DirectoryInfo(root); directory is not null; directory = directory.Parent)
        {
            if ((directory.Attributes & FileAttributes.ReparsePoint) != 0)
                throw new LegalDocumentStorageUnavailableException("Legal document storage path is invalid.");
        }

        return root;
    }

    private static string ResolveStoragePath(string root, string fileName)
    {
        var path = Path.GetFullPath(Path.Combine(root, fileName));
        var rootPrefix = Path.TrimEndingDirectorySeparator(root) + Path.DirectorySeparatorChar;
        var comparison = OperatingSystem.IsWindows()
            ? StringComparison.OrdinalIgnoreCase
            : StringComparison.Ordinal;
        if (!path.StartsWith(rootPrefix, comparison))
            throw new LegalDocumentStorageUnavailableException("Legal document storage reference is invalid.");
        return path;
    }

    private static bool IsSameOrWithin(string path, string parent, StringComparison comparison)
    {
        var normalizedParent = Path.TrimEndingDirectorySeparator(parent);
        return string.Equals(path, normalizedParent, comparison) ||
            path.StartsWith(normalizedParent + Path.DirectorySeparatorChar, comparison);
    }
}
