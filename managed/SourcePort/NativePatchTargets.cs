// Separate installed-handler validation/activation contract. Metadata lookup and
// original registration alone never make a source callback available.
using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using EHR.Generated;

namespace EHR;

internal sealed record NativePatchCandidate(ulong Id,string Selector,EHRStaticTargetSpec Source);

[StructLayout(LayoutKind.Sequential)]
internal unsafe struct NativePatchTargetsTableV1
{
    internal uint AbiVersion,ByteSize;
    internal delegate* unmanaged[Cdecl]<ulong,int> Validate;
    internal delegate* unmanaged[Cdecl]<ulong*,nuint,int> Activate;
    internal delegate* unmanaged[Cdecl]<int> Deactivate;
}

internal sealed unsafe class NativePatchTargetResolver : IEHRStaticTargetResolver
{
    private static NativePatchTargetsTableV1 host;
    private static bool bound;
    private readonly NativePatchCandidate[] candidates;
    private readonly Dictionary<ulong,int> validation=new();

    private NativePatchTargetResolver(NativePatchCandidate[] candidates) { this.candidates=candidates; }

    [UnmanagedCallersOnly(EntryPoint="ehr_source_bind_patch_targets_v1")]
    internal static int Bind(NativePatchTargetsTableV1* table,nuint size)
    {
        if(bound||table==null||size!=32||sizeof(NativePatchTargetsTableV1)!=32||table->AbiVersion!=1||
            table->ByteSize!=size||table->Validate==null||table->Activate==null||table->Deactivate==null)return 4;
        host=*table;bound=true;return 0;
    }

    internal static NativePatchTargetResolver Prepare(NativePatchDefinition[] passive,NativePatchCandidate[] candidates)
    {
        if(!bound)throw new RuntimeGatewayException(1,"installed native patch targets not bound");
        FacadeRuntime.RequireReady();
        FacadeRuntime.Require(host.Deactivate(),"deactivate source patch targets");
        if(passive.Length!=candidates.Length||passive.Length>512||
            passive.Select(d=>d.Id).Distinct().Count()!=passive.Length||
            candidates.Select(d=>d.Id).Distinct().Count()!=candidates.Length||
            candidates.Select(d=>d.Selector).Distinct(StringComparer.Ordinal).Count()!=candidates.Length||
            !passive.Select(d=>d.Id).OrderBy(id=>id).SequenceEqual(candidates.Select(d=>d.Id).OrderBy(id=>id)))
            throw new InvalidOperationException("Generated source/native candidate identities differ.");
        // Native entries remain inactive throughout metadata preparation. The
        // native validator reads SignatureV1 only after this complete configure.
        NativePatchRuntime.Configure(passive);
        var frozen=candidates.Select(c=>new NativePatchCandidate(c.Id,c.Selector,new EHRStaticTargetSpec(
            c.Source.TypeName,c.Source.MemberName,c.Source.MethodKind,(string[])c.Source.ArgumentTypeNames.Clone(),
            c.Source.ExactArgumentTypes,c.Source.Image,c.Source.ReturnType,c.Source.IsStatic,
            (string[])c.Source.ParameterNames.Clone(),c.Source.ResolutionStatus))).ToArray();
        var resolver=new NativePatchTargetResolver(frozen);
        foreach(var candidate in candidates)resolver.validation.Add(candidate.Id,host.Validate(candidate.Id));
        return resolver;
    }

    internal static bool SameSource(EHRStaticTargetSpec first,EHRStaticTargetSpec second) =>
        first.TypeName==second.TypeName&&first.MemberName==second.MemberName&&first.MethodKind==second.MethodKind&&
        first.ExactArgumentTypes==second.ExactArgumentTypes&&first.Image==second.Image&&first.ReturnType==second.ReturnType&&
        first.IsStatic==second.IsStatic&&first.ResolutionStatus==second.ResolutionStatus&&
        first.ArgumentTypeNames.SequenceEqual(second.ArgumentTypeNames,StringComparer.Ordinal)&&
        first.ParameterNames.SequenceEqual(second.ParameterNames,StringComparer.Ordinal);

    public bool TryResolve(EHRStaticTargetSpec sourceSpec,out string targetKey,out string unavailableReason)
    {
        targetKey="";unavailableReason="source_target_not_in_pinned_native_catalog";
        NativePatchCandidate? found=null;
        foreach(var candidate in candidates)if(SameSource(sourceSpec,candidate.Source))
        {
            if(found!=null){unavailableReason="ambiguous_pinned_source_target";return false;}
            found=candidate;
        }
        if(found==null)return false;
        int status=validation[found.Id];
        if(status!=0){unavailableReason="installed_native_handler_validation_status_"+status;return false;}
        targetKey=found.Selector;unavailableReason="";return true;
    }

    internal void Activate(NativePatchDefinition[] definitions)
    {
        FacadeRuntime.RequireReady();
        FacadeRuntime.Require(host.Deactivate(),"deactivate source patch targets before activation");
        foreach(var definition in definitions)
            if(!validation.TryGetValue(definition.Id,out int status)||status!=0)
                throw new InvalidOperationException("An unvalidated native source target cannot be activated.");
        NativePatchRuntime.Configure(definitions);
        ulong[] ids=definitions.Select(d=>d.Id).ToArray();
        fixed(ulong* pointer=ids)
        {
            int status=host.Activate(pointer,(nuint)ids.Length);
            if(status!=0)
            {
                int disabled=host.Deactivate();
                throw new RuntimeGatewayException(disabled==0?status:disabled,"source patch target activation");
            }
        }
    }
}
