// Source adaptation: these are NativeAOT managed callbacks, not IL2CPP delegate
// objects. Only explicit live-collection algorithms consume these signatures.
namespace Il2CppSystem
{
    public delegate bool Predicate<in T>(T value);
}
