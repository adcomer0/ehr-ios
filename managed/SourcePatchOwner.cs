using System;
namespace EHR;
// Explicit static registration owner, not a Harmony runtime patching engine.
public sealed class SourcePatchOwner
{
    public string Id {get;}
    public SourcePatchOwner(string id)
    {
        if(string.IsNullOrWhiteSpace(id))throw new ArgumentException("A source patch owner is required.",nameof(id));
        Id=id;
    }
    public void UnpatchSelf()=>EHRStaticPatchCatalog.Registration.DisableOwner(Id);
}
