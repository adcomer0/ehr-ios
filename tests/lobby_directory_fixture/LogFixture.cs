// Own capture sentinels. The other partial declaration is generated directly
// from the five selected production log statements by the Python fixture.
internal static partial class DirectoryLogSites
{
    private sealed class OwnData { internal string PlayerName = "Own Player"; }
    private sealed class OwnClient { internal string GetHashedPuid() => "Own Puid"; }
    private sealed class OwnPlayer
    {
        internal string FriendCode = "Own Friend";
        internal OwnData Data = new();
        internal OwnClient GetClient() => new();
        internal string GetNameWithRole() => "Own Player Role";
    }
    private sealed class OwnCommand { internal Action Action = OwnEffect; }
    private static void OwnEffect() => throw new InvalidOperationException("A logging fixture must not dispatch a command");
    private static class Logger
    {
        internal static readonly List<(string Text, string Tag)> Entries = [];
        internal static void Info(string text, string tag) => Entries.Add((text, tag));
    }
    internal static int Run()
    {
        int checks = 0;
        void Check(bool okay) { ++checks; if (!okay) throw new InvalidOperationException("Own command log capture failed"); }
        string[] commands = ["confirmauth", "CoNfIrMaUtH", "确认身份", "подтверждение", "確認認証", "confirmar", "anyothercommand"];
        string[] whitespace = ["", " ", "\t", "\n", "\r\n", "\u2003"];
        string[] canaries = ["OWN-VERIFICATION-CANARY", "OWN-QUOTED-\"\\-CANARY"];
        var recognized = new OwnRecognizedCommand(commands.Select(form => form.ToLower()).ToArray());
        foreach (string command in commands)
        foreach (string prefix in whitespace)
        foreach (string canary in canaries)
        {
            string message = prefix + "/" + command + " " + canary;
            Check(recognized.IsThisCommand("/" + command + " " + canary));
            var captured = Capture(message);
            Check(captured.Count == 5);
            foreach (var entry in captured)
                Check(entry.Text.Contains("[slash command redacted]", StringComparison.Ordinal) && !entry.Text.Contains(canary, StringComparison.Ordinal));
            Check(message.EndsWith(canary, StringComparison.Ordinal));
        }
        foreach (string message in new[] { "hello", "ordinary words /confirmauth are not a slash command", "  ordinary chat\nmore words", "", "\t " })
        {
            var captured = Capture(message);
            Check(captured.Count == 5);
            foreach (var entry in captured) Check(entry.Text.Contains(message, StringComparison.Ordinal));
            Check(!captured.Any(entry => entry.Text.Contains("[slash command redacted]", StringComparison.Ordinal)));
            Check(ReferenceEquals(EHR.EHRDirectoryLog.ForLog(message), message));
        }
        return checks;
    }
}
