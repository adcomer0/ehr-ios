// Own Mach-O mapping and inactive-registry fixture. No game library is loaded.
// Unused game imports are deliberately unresolved in this fixture executable;
// exercising any such path would fail the process instead of faking success.
#include "EHRNativePatchThunks.mm"
#include <cstdio>
#include <thread>
int main() {
    struct ImageFixture {mach_header_64 header;segment_command_64 text,data;} image{};
    image.header.magic=MH_MAGIC_64;image.header.ncmds=2;image.header.sizeofcmds=2*sizeof(segment_command_64);
    image.text.cmd=LC_SEGMENT_64;image.text.cmdsize=sizeof(segment_command_64);image.text.vmaddr=0;image.text.vmsize=0x2000;image.text.filesize=0x1000;image.text.initprot=VM_PROT_READ|VM_PROT_EXECUTE;
    image.data=image.text;image.data.vmaddr=0x2000;image.data.filesize=0x1000;image.data.initprot=VM_PROT_READ|VM_PROT_WRITE;
    Mapping own{0x100000,&image.header};
    if(!own.range(0x100,4,VM_PROT_READ|VM_PROT_EXECUTE)||!own.range(0x2100,8,VM_PROT_READ|VM_PROT_WRITE))return 1;
    if(own.range(0x1100,8,VM_PROT_READ|VM_PROT_EXECUTE)||own.range(0x100,8,VM_PROT_READ|VM_PROT_WRITE)||own.range(0x2100,8,VM_PROT_READ|VM_PROT_EXECUTE)||own.range(UINT64_MAX,8,VM_PROT_READ))return 2;
    image.data.initprot|=VM_PROT_EXECUTE;if(own.range(0x2100,8,VM_PROT_READ|VM_PROT_WRITE)||own.range(0x2100,8,VM_PROT_READ|VM_PROT_EXECUTE))return 3;image.data.initprot=VM_PROT_READ|VM_PROT_WRITE;
    const uint8_t ownUUID[16]{};const EHRNativePatchTypeV1 none{"System.Void",0,0,1,0,nullptr,nullptr,0};
    const EHRNativePatchSiteV1 site{42,0x1000,0x06000001,0,ownUUID,reinterpret_cast<void *>(&main),nullptr,nullptr,&none,nullptr,0,true};
    const EHRNativePatchSiteV1 *duplicate[]{&site,&site};EHRManagedPatchTargetsV1 table{};EHRNativePatchMakeTargetsTable(&table);
    if(table.abi_version!=1||table.byte_size!=32||EHRNativePatchRegisterCompiled(duplicate,2)!=EHR_RUNTIME_BAD_ARGUMENT||table.validate(42)!=EHR_RUNTIME_NOT_FOUND)return 4;
    const EHRNativePatchSiteV1 *one[]{&site};if(EHRNativePatchRegisterCompiled(one,1)!=EHR_RUNTIME_OK||EHRNativePatchRegisterCompiled(one,1)!=EHR_RUNTIME_BAD_ARGUMENT)return 5;
    uint64_t id=42,duplicateIDs[]{42,42},absent=77;
    if(table.validate(id)!=EHR_RUNTIME_NOT_READY||table.activate(&id,1)!=EHR_RUNTIME_NOT_READY||EHRNativePatchShouldDispatch(site))return 6;
    if(table.activate(duplicateIDs,2)!=EHR_RUNTIME_BAD_ARGUMENT||table.activate(&absent,1)!=EHR_RUNTIME_NOT_FOUND||EHRNativePatchShouldDispatch(site))return 7;
    int backgroundValidate=0,backgroundActivate=0;std::thread worker([&]{backgroundValidate=table.validate(id);backgroundActivate=table.activate(&id,1);});worker.join();
    if(backgroundValidate!=EHR_RUNTIME_WRONG_THREAD||backgroundActivate!=EHR_RUNTIME_WRONG_THREAD||table.activate(nullptr,0)!=EHR_RUNTIME_OK||table.deactivate()!=EHR_RUNTIME_OK||EHRNativePatchShouldDispatch(site))return 8;
    std::puts("{\"pass\":true,\"gameLoaded\":false,\"gameApiCalls\":0,\"segmentProtectionAndBounds\":true,\"missingEvidenceInactive\":true,\"transactionFailuresInactive\":true,\"mainThreadRequired\":true}");
}
