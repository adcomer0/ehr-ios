// Original opt-in EHR directory support. No itch.io key enters this assembly.
using System;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace EHR;

internal sealed class EHRLobbyDirectoryOption(int id, string name, TabGroup tab)
    : BooleanOptionItem(id, name, false, tab)
{
    internal const string Label = "List this lobby on the EHR website";
    public override void SetValue(int value, bool doSync = true)
    {
        bool wasEnabled = GetBool();
        base.SetValue(value, doSync);
        if (EHRDirectoryGate.IsMain && wasEnabled != GetBool())
            Modules.LobbySharingAPI.NotifyLobbyStatusChanged(GameStates.InGame ? Modules.LobbyStatus.In_Game : Modules.LobbyStatus.In_Lobby);
    }
}

// Log-only transformation. Never pass the result to command dispatch, history,
// JSON, RPC or other game behavior. Redacting every slash command also covers
// translated aliases without depending on game/translation initialization.
internal static class EHRDirectoryLog
{
    internal static string ForLog(string text)
    {
        if (string.IsNullOrEmpty(text)) return text;
        ReadOnlySpan<char> visible = text.AsSpan().TrimStart();
        return !visible.IsEmpty && visible[0] == '/' ? "[slash command redacted]" : text;
    }
}

internal static unsafe class EHRDirectoryGate
{
    private static delegate* unmanaged[Cdecl]<int> allowed;
    internal static bool IsMain => SourceHost.NativeSourceHost.IsMainThread;
    internal static bool Allowed => IsMain && allowed != null && allowed() == 1;

    [UnmanagedCallersOnly(EntryPoint = "ehr_source_directory_bind_v1", CallConvs = [typeof(CallConvCdecl)])]
    internal static int Bind(delegate* unmanaged[Cdecl]<int> callback)
    {
        if (callback == null) return 4;
        if (!IsMain) return 2;
        if (allowed != null && (nuint)allowed != (nuint)callback) return 4;
        allowed = callback;
        return 0;
    }

    [UnmanagedCallersOnly(EntryPoint = "ehr_source_directory_tick_v1", CallConvs = [typeof(CallConvCdecl)])]
    internal static int Tick()
    {
        if (!IsMain) return 2;
        try { Modules.LobbySharingAPI.Tick(); return 0; }
        catch (Exception) { return 6; }
    }
}

internal enum DirectoryEndpoint { Create, Status, Verify }
internal enum DirectoryFailure { None, Disabled, Cancelled, Network, Rejected, Redirect, TooLarge, Malformed }
internal sealed record DirectoryReply(DirectoryFailure Failure, int HttpStatus, byte[] Body)
{
    internal bool Success => Failure == DirectoryFailure.None;
    internal static DirectoryReply Failed(DirectoryFailure failure, int status = 0) => new(failure, status, []);
}

internal static class EHRDirectoryClock
{
#if EHR_DIRECTORY_FIXTURE
    internal static long Now;
#else
    internal static long Now => Environment.TickCount64;
#endif
}

internal static class EHRDirectoryTransport
{
    internal const int MaxBodyBytes = 8192, MaxRequestBytes = 16384, TimeoutSeconds = 10;
#if EHR_DIRECTORY_FIXTURE
    // The owned fixture never falls through to a real network handler.
    internal static Func<HttpMessageHandler>? FixtureHandler;
#endif
    private static string Endpoint(DirectoryEndpoint endpoint) => endpoint switch
    {
        DirectoryEndpoint.Create => "https://app.gurge44.eu/lobby_created",
        DirectoryEndpoint.Status => "https://app.gurge44.eu/update_status",
        DirectoryEndpoint.Verify => "https://app.gurge44.eu/api/verify_ingame",
        _ => throw new ArgumentOutOfRangeException(nameof(endpoint))
    };

    private static HttpMessageHandler Handler()
    {
#if EHR_DIRECTORY_FIXTURE
        return FixtureHandler?.Invoke() ?? throw new InvalidOperationException("Owned transport fixture requires its fake handler");
#else
        return new HttpClientHandler
        {
            AllowAutoRedirect = false, UseCookies = false,
            UseDefaultCredentials = false, AutomaticDecompression = DecompressionMethods.None
        };
#endif
    }

    // Only immutable DTO bytes/strings and cancellation enter this asynchronous
    // path. It never calls a game facade, main-thread gate or native object API.
    internal static async Task<DirectoryReply> PostAsync(DirectoryEndpoint endpoint, byte[] body,
        string? bearer, CancellationToken cancellation)
    {
        if (body.Length == 0 || body.Length > MaxRequestBytes ||
            (endpoint != DirectoryEndpoint.Create && !string.IsNullOrEmpty(bearer)) ||
            (bearer != null && (bearer.Length == 0 || bearer.Length > MaxRequestBytes || bearer.Contains('\r') || bearer.Contains('\n'))))
            return DirectoryReply.Failed(DirectoryFailure.Malformed);
        try
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
            timeout.CancelAfter(TimeSpan.FromSeconds(TimeoutSeconds));
            using var client = new HttpClient(Handler(), true) { Timeout = Timeout.InfiniteTimeSpan, MaxResponseContentBufferSize = MaxBodyBytes };
            using var request = new HttpRequestMessage(HttpMethod.Post, Endpoint(endpoint));
            request.Headers.UserAgent.ParseAdd("EHR-iOS/8.0.3");
            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
            if (endpoint == DirectoryEndpoint.Create && !string.IsNullOrEmpty(bearer))
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
            request.Content = new ByteArrayContent(body);
            request.Content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
            using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, timeout.Token).ConfigureAwait(false);
            int status = (int)response.StatusCode;
            if (status is >= 300 and < 400) return DirectoryReply.Failed(DirectoryFailure.Redirect, status);
            if (!response.IsSuccessStatusCode) return DirectoryReply.Failed(DirectoryFailure.Rejected, status);
            if (response.Content.Headers.ContentEncoding.Count != 0 || response.Content.Headers.ContentLength > MaxBodyBytes)
                return DirectoryReply.Failed(DirectoryFailure.TooLarge, status);
            await using var input = await response.Content.ReadAsStreamAsync(timeout.Token).ConfigureAwait(false);
            using var output = new MemoryStream();
            byte[] chunk = new byte[1024];
            while (true)
            {
                int remaining = MaxBodyBytes + 1 - checked((int)output.Length);
                int count = await input.ReadAsync(chunk.AsMemory(0, Math.Min(chunk.Length, remaining)), timeout.Token).ConfigureAwait(false);
                if (count == 0) return new(DirectoryFailure.None, status, output.ToArray());
                output.Write(chunk, 0, count);
                if (output.Length > MaxBodyBytes) return DirectoryReply.Failed(DirectoryFailure.TooLarge, status);
            }
        }
        catch (OperationCanceledException) { return DirectoryReply.Failed(DirectoryFailure.Cancelled); }
        catch (Exception) { return DirectoryReply.Failed(DirectoryFailure.Network); }
    }

    internal static byte[] Json(params (string Key, string Value)[] fields)
    {
        using var bytes = new MemoryStream();
        using (var writer = new Utf8JsonWriter(bytes))
        {
            writer.WriteStartObject();
            foreach (var field in fields) writer.WriteString(field.Key, field.Value);
            writer.WriteEndObject();
        }
        return bytes.ToArray();
    }

    internal static string? RoomToken(byte[] body)
    {
        if (body.Length == 0 || body.Length > MaxBodyBytes) return null;
        try
        {
            using var json = JsonDocument.Parse(body, new JsonDocumentOptions { MaxDepth = 8 });
            if (json.RootElement.ValueKind != JsonValueKind.Object) return null;
            if (!json.RootElement.TryGetProperty("token", out var value) || value.ValueKind != JsonValueKind.String) return null;
            string? token = value.GetString();
            if (string.IsNullOrEmpty(token) || token.Length > 2048) return null;
            foreach (char unit in token) if (unit < 0x21 || unit > 0x7e) return null;
            return token;
        }
        catch (JsonException) { return null; }
    }
}
