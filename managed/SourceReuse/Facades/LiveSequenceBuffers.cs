// Narrow source-compatible facade for the actual game SequenceBuffer<T>.
// The used BumpSid method has no generic-shaped parameter/return values.
public sealed class SequenceBuffer<T>:Il2CppSystem.Object
{
    internal SequenceBuffer(ulong owned,bool takeOwnership):base(owned){}
    internal static ulong NativeClass=>EHR.Generated.LiveReflection.MakeGenericClass(
        EHR.Generated.FacadeRuntime.Class("Assembly-CSharp.dll","","SequenceBuffer`1"),[EHR.Generated.ElementCodecs.Get<T>().NativeClass()]);
    public void BumpSid(){using var result=EHR.Generated.FacadeRuntime.InvokeOnClass(NativeClass,"BumpSid","System.Void",Token);}
}
