using System;
using System.IO;

namespace EHR.SourceAudio;

// The native source host supplies the dedicated EHR data root. No official save
// directory, current directory or arbitrary absolute file is accepted here.
internal static class OwnedSoundFiles
{
    internal const int MaximumBytes=8*1024*1024;
    private static void NoLink(string path)
    {
        if((File.Exists(path)||Directory.Exists(path))&&
           (File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0)
            throw new IOException("sound storage cannot contain symbolic links");
    }
    internal static bool ExistingExact(string root,string stem)
    {
        string file=SourceAudioPaths.SoundFile(root,stem);
        string resources=Path.Combine(Path.GetFullPath(root),"resources");
        string directory=Path.GetDirectoryName(file)!;
        NoLink(resources);NoLink(directory);
        if(!Directory.Exists(directory))return false;
        string basename=Path.GetFileName(file);
        // File.Exists alone follows the filesystem's casing policy. Require an
        // actual ordinal filename match even on a case-insensitive volume.
        var options=new EnumerationOptions{MatchCasing=MatchCasing.CaseSensitive,MatchType=MatchType.Simple,AttributesToSkip=0};
        foreach(string found in Directory.EnumerateFiles(directory,basename,options))
        {
            if(!string.Equals(Path.GetFileName(found),basename,StringComparison.Ordinal))continue;
            NoLink(found);return File.Exists(found);
        }
        return false;
    }
    internal static string Prepare(string root,string stem)
    {
        string file=SourceAudioPaths.SoundFile(root,stem);
        string resources=Path.Combine(Path.GetFullPath(root),"resources");
        string directory=Path.GetDirectoryName(file)!;
        NoLink(resources);Directory.CreateDirectory(resources);NoLink(resources);
        NoLink(directory);Directory.CreateDirectory(directory);NoLink(directory);
        NoLink(file);return file;
    }
    internal static byte[] Read(Stream stream)
    {
        using var output=new MemoryStream();byte[] buffer=new byte[16384];
        for(;;)
        {
            int read=stream.Read(buffer,0,buffer.Length);if(read==0)break;
            if(output.Length+read>MaximumBytes)throw new IOException("sound exceeds the bounded WAV size");
            output.Write(buffer,0,read);
        }
        return output.ToArray();
    }
    internal static PcmWaveData Load(string root,string stem,Func<string,Stream?> resource)
    {
        string file=Prepare(root,stem);
        if(File.Exists(file))
        {
            NoLink(file);
            using var input=new FileStream(file,FileMode.Open,FileAccess.Read,FileShare.Read);
            return new PcmWaveData(Read(input));
        }
        using var embedded=resource("EHR.Resources.Sounds."+stem+".wav")??
            throw new FileNotFoundException("no owned custom WAV or embedded sound exists",stem);
        byte[] bytes=Read(embedded);var decoded=new PcmWaveData(bytes);
        NoLink(file);
        // Never overwrite an existing custom sound. Source calls are main-thread
        // only; CreateNew also rejects a concurrent file created after checking.
        using(var output=new FileStream(file,FileMode.CreateNew,FileAccess.Write,FileShare.None))
            output.Write(bytes,0,bytes.Length);
        return decoded;
    }
}
