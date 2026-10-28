using System;
using System.Collections.Generic;
using BepInEx;
using BepInEx.Configuration;
using BepInEx.Logging;
using EHR.SourceHost;

namespace BepInEx.Unity.IL2CPP
{
    // This is a source adapter, not the desktop IL2CPP chainloader implementation.
    public abstract class BasePlugin
    {
        internal SourcePluginHost Host { get; }
        protected BasePlugin()
        {
            Host = SourcePluginHost.ConstructionHost;
            Host.AttachBase();
        }
        public ConfigFile Config => Host.Config;
        public ManualLogSource Log => Host.Log;
        public abstract void Load();
        public virtual bool Unload() => false;
        public T AddComponent<T>() => Host.AddComponent<T>();
    }

    public sealed class IL2CPPChainloader
    {
        private static IL2CPPChainloader? active;
        private readonly SourcePluginHost host;
        internal IL2CPPChainloader(SourcePluginHost host) => this.host = host;
        public static IL2CPPChainloader Instance => SourcePluginHost.CurrentConstruction?.Chainloader ?? active ??
            throw new InvalidOperationException("Source host has not started");
        internal static IL2CPPChainloader? Active => active;
        internal static void Activate(IL2CPPChainloader? value) => active = value;
        // Exact source API; registry contains only modules instantiated by this host.
        public Dictionary<string, PluginInfo> Plugins { get; } = new(StringComparer.Ordinal);
        public event Action Finished
        {
            add => host.SubscribeFinished(value);
            remove => host.UnsubscribeFinished(value);
        }
        public void RegisterSourceComponent(Type type) => host.RegisterComponent(type);
    }
}

namespace Il2CppInterop.Runtime.Injection
{
    public static class ClassInjector
    {
        public static void RegisterTypeInIl2Cpp<T>() =>
            BepInEx.Unity.IL2CPP.IL2CPPChainloader.Instance.RegisterSourceComponent(typeof(T));
    }
}

namespace Il2CppInterop.Runtime.Attributes
{
    [AttributeUsage(AttributeTargets.Method | AttributeTargets.Property)]
    public sealed class HideFromIl2CppAttribute : Attribute { }
}
