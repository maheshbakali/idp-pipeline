using System.Buffers.Binary;

namespace Project1.Api;

internal static class UploadValidation
{
    internal const long MaxBytes = 5L * 1024 * 1024;

    internal static readonly HashSet<string> AllowedExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".pdf",
        ".png",
        ".jpg",
        ".jpeg",
    };

    internal static readonly HashSet<string> AllowedDocTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        "invoice",
        "receipt",
        "contract",
        "other",
    };

    /// <summary>
    /// Validates file extension and magic bytes (PDF / PNG / JPEG).
    /// </summary>
    internal static bool IsAllowedContent(ReadOnlySpan<byte> header, string extension)
    {
        if (AllowedExtensions.Contains(extension) == false)
            return false;

        if (extension.Equals(".pdf", StringComparison.OrdinalIgnoreCase))
            return header.Length >= 4 && header.StartsWith("%PDF"u8);

        if (extension is ".jpg" or ".jpeg")
            return header.Length >= 3 && header[0] == 0xFF && header[1] == 0xD8 && header[2] == 0xFF;

        if (extension.Equals(".png", StringComparison.OrdinalIgnoreCase))
            return header.Length >= 8
                && BinaryPrimitives.ReadUInt32BigEndian(header[..4]) == 0x89504E47
                && BinaryPrimitives.ReadUInt32BigEndian(header.Slice(4, 4)) == 0x0D0A1A0A;

        return false;
    }

    internal static string SanitizeFileName(string? original)
    {
        if (string.IsNullOrWhiteSpace(original))
            return "document";

        var name = Path.GetFileName(original.Trim());
        foreach (var c in Path.GetInvalidFileNameChars())
            name = name.Replace(c, '_');

        name = name.Trim();
        return string.IsNullOrEmpty(name) ? "document" : name;
    }
}
