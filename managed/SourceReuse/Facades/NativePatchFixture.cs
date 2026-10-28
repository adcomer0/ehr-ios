using System;
using System.Runtime.InteropServices;
using EHR.Generated;
namespace EHR;

// Owned arithmetic callbacks exercise the production frame bridge independently
// of full EHR startup. They are explicitly configured and cleared by native test.
internal static class NativePatchFixture
{
    [UnmanagedCallersOnly(EntryPoint="ehr_source_patch_fixture_setup")]
    internal static int Setup(ulong versionRva,ulong predicateRva)
        =>Configure(versionRva,predicateRva,0);
    [UnmanagedCallersOnly(EntryPoint="ehr_source_patch_fixture_fail_setup")]
    internal static int FailureSetup(ulong versionRva,ulong predicateRva,uint phase)
        =>phase is 1 or 2?Configure(versionRva,predicateRva,phase):4;
    private static int Configure(ulong versionRva,ulong predicateRva,uint phase)
    {
        try
        {
            var postfix=new EHRStaticPatchDescriptor("own.version.postfix","own.version","own.fixture",EHRStaticPatchKind.Postfix,
                400,0,false,true,[],[],[],frame=>{frame.Result=checked(frame.GetResult<int>()+7);if(phase==2)throw new InvalidOperationException("own postfix failure after original");},null);
            var failure=new EHRStaticPatchDescriptor("own.version.failure","own.version","own.fixture",EHRStaticPatchKind.Prefix,
                400,2,true,true,[],[],[],frame=>{if(phase==1)throw new InvalidOperationException("own prefix failure before original");},null);
            var prefix=new EHRStaticPatchDescriptor("own.predicate.prefix","own.predicate","own.fixture",EHRStaticPatchKind.Prefix,
                400,1,true,true,[],[],[],static frame=>{frame.Result=true;frame.RunOriginal=false;},null);
            NativePatchRuntime.Configure([
                new(1,"own.version",new("Assembly-CSharp.dll","","Constants","GetBroadcastVersion",true,false,"System.Int32",[]),
                    null,[],[],[],[],typeof(int),versionRva,new("own.version",[failure,postfix])),
                new(2,"own.predicate",new("Assembly-CSharp.dll","","Constants","IsVersionModded",true,false,"System.Boolean",[]),
                    null,[],[],[],[],typeof(bool),predicateRva,new("own.predicate",[prefix]))]);
            return 0;
        }
        catch(RuntimeGatewayException error){return error.Status;}catch{return 6;}
    }
    [UnmanagedCallersOnly(EntryPoint="ehr_source_patch_fixture_clear")]
    internal static int Clear()
    {
        try{NativePatchRuntime.Configure([]);return 0;}catch(RuntimeGatewayException error){return error.Status;}catch{return 6;}
    }
}
