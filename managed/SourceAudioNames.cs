using System;
using System.IO;

namespace EHR.SourceAudio;

internal static class SourceAudioNames
{
    internal static string Resolve(string requested,Func<string,bool> existingExact,string[] resourceNames)
    {
        if(existingExact(requested))return requested;
        const string prefix="EHR.Resources.Sounds.";const string suffix=".wav";
        foreach(string name in resourceNames)
            if(string.Equals(name,prefix+requested+suffix,StringComparison.Ordinal))return requested;
        string? match=null;
        foreach(string name in resourceNames)
        {
            if(!name.StartsWith(prefix,StringComparison.Ordinal)||!name.EndsWith(suffix,StringComparison.Ordinal))continue;
            string stem=name.Substring(prefix.Length,name.Length-prefix.Length-suffix.Length);
            if(!string.Equals(stem,requested,StringComparison.OrdinalIgnoreCase))continue;
            if(match is not null&&!string.Equals(match,stem,StringComparison.Ordinal))
                throw new InvalidDataException("ambiguous authored sound name");
            match=stem;
        }
        // The normal bounded loader checks the canonical existing custom file
        // before opening this embedded resource. Unknown names remain unknown.
        return match??requested;
    }
}
