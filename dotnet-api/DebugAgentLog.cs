using System.Text.Json;

namespace Project1.Api;

internal static class DebugAgentLog
{
    public static void Write(string hypothesisId, string location, string message, Dictionary<string, object?> data)
    {
        try
        {
            var logPath = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "debug-ec444b.log"));
            var payload = new Dictionary<string, object?>
            {
                ["sessionId"] = "ec444b",
                ["timestamp"] = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
                ["hypothesisId"] = hypothesisId,
                ["location"] = location,
                ["message"] = message,
                ["data"] = data,
                ["runId"] = "pre-fix",
            };
            File.AppendAllText(logPath, JsonSerializer.Serialize(payload) + Environment.NewLine);
        }
        catch
        {
            // debug ingest must never break API
        }
    }
}
