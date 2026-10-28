// Original iOS source-host adapter. This contains no Unity/IL2CPP class injector.
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.CompilerServices;
using System.Threading;
using BepInEx;
using BepInEx.Configuration;
using BepInEx.Logging;
using BepInEx.Unity.IL2CPP;

namespace EHR.SourceHost;

public enum SourceHostState { Ready, Loading, Loaded, Failed }

public sealed class SourceHostOptions
{
    public required string DataRoot { get; init; }
    public required string NativeModulePath { get; init; }
    public required Func<bool> IsMainThread { get; init; }
    public Action<LogLevel, string>? LogSink { get; init; }
    public IEnumerable<BepInDependency> Dependencies { get; init; } = Array.Empty<BepInDependency>();
    public IEnumerable<BepInProcess> Processes { get; init; } = Array.Empty<BepInProcess>();
    public IEnumerable<BepInIncompatibility> Incompatibilities { get; init; } = Array.Empty<BepInIncompatibility>();
    // The caller must provide a generated, closed factory registry. Reflection
    // activation and unregistered custom IL2CPP classes are never synthesized.
    public Func<Type, object>? AddComponent { get; init; }
    public Action<Type>? RegisterComponent { get; init; }
}

public sealed class SourcePluginHost
{
    [ThreadStatic] private static SourcePluginHost? constructing;
    private readonly SourceHostOptions options;
    private readonly int ownerThread;
    private readonly BepInPlugin metadata;
    private readonly object logLock = new();
    private readonly string logPath;
    private BasePlugin? instance;
    private bool baseConstructed;
    private Action? finished;
    public string DataRoot { get; }
    public ConfigFile Config { get; }
    public ManualLogSource Log { get; }
    public PluginInfo? Plugin { get; private set; }
    public SourceHostState State { get; private set; }
    public Exception? Failure { get; private set; }
    public IL2CPPChainloader Chainloader { get; }

    public SourcePluginHost(SourceHostOptions options, BepInPlugin metadata)
    {
        ArgumentNullException.ThrowIfNull(options);
        ArgumentNullException.ThrowIfNull(metadata);
        this.options = options;
        this.metadata = metadata;
        ownerThread = Environment.CurrentManagedThreadId;
        CheckThread();
        if (!Path.IsPathFullyQualified(options.DataRoot) ||
            !Path.IsPathFullyQualified(options.NativeModulePath))
            throw new ArgumentException("Native host must supply absolute data/module paths");
        if (!File.Exists(options.NativeModulePath))
            throw new FileNotFoundException("Native module path must identify an existing host image");
        if (string.IsNullOrEmpty(metadata.GUID) || metadata.GUID.IndexOfAny(new[]{'/', '\\', '\0'}) >= 0 ||
            metadata.GUID is "." or "..")
            throw new ArgumentException("Plugin GUID is not a filename component");
        DataRoot = Path.GetFullPath(options.DataRoot);
        Directory.CreateDirectory(DataRoot);
        string configPath = Path.Combine(DataRoot, "config");
        Directory.CreateDirectory(configPath);
        Directory.CreateDirectory(Path.Combine(DataRoot, "logs"));
        CoreAccess.ConfigurePaths(DataRoot, configPath);
        SourcePlatformPaths.Publish(DataRoot);
        Log = new ManualLogSource(metadata.Name);
        logPath = Path.Combine(DataRoot, "logs", metadata.GUID + ".log");
        Log.LogEvent += OnLog;
        BepInEx.Logging.Logger.Sources.Add(Log);
        // Real pinned BepInEx.Core implementation; no dictionary substitute.
        Config = new ConfigFile(Path.Combine(configPath, metadata.GUID + ".cfg"), false, metadata);
        Chainloader = new IL2CPPChainloader(this);
    }

    internal static SourcePluginHost ConstructionHost => constructing ??
        throw new InvalidOperationException("Construct source plugins through SourcePluginHost.Load");
    internal static SourcePluginHost? CurrentConstruction => constructing;

    internal void AttachBase()
    {
        CheckThread();
        if (State != SourceHostState.Loading || baseConstructed)
            throw new InvalidOperationException("A factory must construct exactly one plugin");
        baseConstructed = true;
    }

    public BasePlugin Load(Func<BasePlugin> factory)
    {
        ArgumentNullException.ThrowIfNull(factory);
        CheckThread();
        if (State == SourceHostState.Loaded) return instance!;
        if (State != SourceHostState.Ready || constructing != null)
            throw new InvalidOperationException("Plugin startup is reentrant or has already failed", Failure);
        State = SourceHostState.Loading;
        constructing = this;
        IL2CPPChainloader? previousChainloader = IL2CPPChainloader.Active;
        bool activated = false;
        try
        {
            instance = factory() ?? throw new InvalidOperationException("Plugin factory returned null");
            if (!baseConstructed || !ReferenceEquals(instance.Host, this))
                throw new InvalidOperationException("Plugin does not belong to this host");
            Plugin = CoreAccess.NewPluginInfo(metadata, instance, options);
            Chainloader.Plugins.Add(metadata.GUID, Plugin);
            // Publish only the actual plugin before Load: source compatibility
            // checks can observe itself, never invented optional desktop mods.
            IL2CPPChainloader.Activate(Chainloader);
            activated = true;
            instance.Load();
            Config.Save();
            // The event is consumed before invocation: failures/reentrancy must
            // not invoke an earlier subscriber a second time.
            Action? handlers = finished;
            finished = null;
            handlers?.Invoke();
            State = SourceHostState.Loaded;
            return instance;
        }
        catch (Exception error)
        {
            Failure = error;
            State = SourceHostState.Failed;
            Chainloader.Plugins.Remove(metadata.GUID);
            if (activated) IL2CPPChainloader.Activate(previousChainloader);
            finished = null;
            throw;
        }
        finally { constructing = null; }
    }

    internal void SubscribeFinished(Action handler)
    {
        CheckThread();
        if (State != SourceHostState.Ready && State != SourceHostState.Loading)
            throw new InvalidOperationException("Startup has already completed");
        finished += handler;
    }
    internal void UnsubscribeFinished(Action handler) { CheckThread(); finished -= handler; }

    public void CheckThread()
    {
        if (Environment.CurrentManagedThreadId != ownerThread || !options.IsMainThread())
            throw new InvalidOperationException("Source plugin lifecycle requires the native main thread");
    }

    internal T AddComponent<T>()
    {
        CheckThread();
        return options.AddComponent is { } add ? (T)add(typeof(T)) :
            throw new PlatformNotSupportedException("Source component factory/lifecycle bridge is not installed");
    }
    internal void RegisterComponent(Type type)
    {
        CheckThread();
        if (options.RegisterComponent is not { } register)
            throw new PlatformNotSupportedException("Source component factory/lifecycle bridge is not installed");
        register(type);
    }

    private void OnLog(object? sender, LogEventArgs entry)
    {
        string message = entry.Data?.ToString() ?? string.Empty;
        lock (logLock)
            File.AppendAllText(logPath, $"[{DateTime.UtcNow:O}][{entry.Level}] {message}{Environment.NewLine}");
        options.LogSink?.Invoke(entry.Level, message);
    }
}

public static class SourcePlatformPaths
{
    private static string? dataRoot;
    public static string DataRoot => dataRoot ??
        throw new InvalidOperationException("Initialize the native source host before source static data");
    internal static void Publish(string value)
    {
        if (dataRoot != null && !string.Equals(value, dataRoot, StringComparison.Ordinal))
            throw new InvalidOperationException("Source data root is already configured");
        dataRoot = value;
    }
}

// These are compile-time accessors against pinned BepInEx.Core. They generate
// ordinary direct calls under NativeAOT; no Reflection.Emit, JIT or setter lookup.
internal static class CoreAccess
{
    private static string? configuredRoot;
    public static void ConfigurePaths(string root, string config)
    {
        if (configuredRoot != null && !string.Equals(root, configuredRoot, StringComparison.Ordinal))
            throw new InvalidOperationException("BepInEx.Core paths are process-global and already configured");
        SetRoot(null!, root);
        SetConfig(null!, config);
        SetCoreConfig(null!, Path.Combine(config, "BepInEx.cfg"));
        SetCache(null!, Path.Combine(root, "cache"));
        SetPlugins(null!, Path.Combine(root, "plugins"));
        configuredRoot = root;
    }
    public static PluginInfo NewPluginInfo(BepInPlugin metadata, object instance, SourceHostOptions options)
    {
        PluginInfo info = new();
        SetMetadata(info, metadata);
        SetInstance(info, instance);
        SetLocation(info, options.NativeModulePath);
        SetTypeName(info, instance.GetType().FullName ?? instance.GetType().Name);
        SetDependencies(info, options.Dependencies);
        SetProcesses(info, options.Processes);
        SetIncompatibilities(info, options.Incompatibilities);
        return info;
    }
    [UnsafeAccessor(UnsafeAccessorKind.Method, Name="set_Metadata")]
    private static extern void SetMetadata(PluginInfo info, BepInPlugin value);
    [UnsafeAccessor(UnsafeAccessorKind.Method, Name="set_Instance")]
    private static extern void SetInstance(PluginInfo info, object value);
    [UnsafeAccessor(UnsafeAccessorKind.Method, Name="set_Location")]
    private static extern void SetLocation(PluginInfo info, string value);
    [UnsafeAccessor(UnsafeAccessorKind.Method, Name="set_TypeName")]
    private static extern void SetTypeName(PluginInfo info, string value);
    [UnsafeAccessor(UnsafeAccessorKind.Method, Name="set_Dependencies")]
    private static extern void SetDependencies(PluginInfo info, IEnumerable<BepInDependency> value);
    [UnsafeAccessor(UnsafeAccessorKind.Method, Name="set_Processes")]
    private static extern void SetProcesses(PluginInfo info, IEnumerable<BepInProcess> value);
    [UnsafeAccessor(UnsafeAccessorKind.Method, Name="set_Incompatibilities")]
    private static extern void SetIncompatibilities(PluginInfo info, IEnumerable<BepInIncompatibility> value);
    [UnsafeAccessor(UnsafeAccessorKind.StaticMethod, Name="set_BepInExRootPath")]
    private static extern void SetRoot([UnsafeAccessorType("BepInEx.Paths, BepInEx.Core")] object _, string value);
    [UnsafeAccessor(UnsafeAccessorKind.StaticMethod, Name="set_ConfigPath")]
    private static extern void SetConfig([UnsafeAccessorType("BepInEx.Paths, BepInEx.Core")] object _, string value);
    [UnsafeAccessor(UnsafeAccessorKind.StaticMethod, Name="set_BepInExConfigPath")]
    private static extern void SetCoreConfig([UnsafeAccessorType("BepInEx.Paths, BepInEx.Core")] object _, string value);
    [UnsafeAccessor(UnsafeAccessorKind.StaticMethod, Name="set_CachePath")]
    private static extern void SetCache([UnsafeAccessorType("BepInEx.Paths, BepInEx.Core")] object _, string value);
    [UnsafeAccessor(UnsafeAccessorKind.StaticMethod, Name="set_PluginPath")]
    private static extern void SetPlugins([UnsafeAccessorType("BepInEx.Paths, BepInEx.Core")] object _, string value);
}
