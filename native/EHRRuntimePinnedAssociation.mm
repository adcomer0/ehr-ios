#import <Foundation/Foundation.h>
#include "EHRRuntimePinnedAssociationCore.h"
#include <CommonCrypto/CommonDigest.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach/machine.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <cerrno>
#include <string>
#include <array>

#if __has_include("EHRNativeAssociation.generated.h")
#include "EHRNativeAssociation.generated.h"
#else
// Compiling without a candidate-specific generated header is allowed for
// portable gateway development, but association always remains UNSUPPORTED.
static const uint8_t EHRAssociationFrameworkUUID[16] = {};
static const char EHRAssociationSourceSHA256Hex[] = "";
static const char EHRAssociationCandidateSHA256Hex[] = "";
#endif

namespace ehr_pinned {
namespace {
constexpr char kProvenSourceHash[] = "42e47c2e676fd5389385d12ddefc45bdcb88a9c3db54285381521abb762ba84f";
constexpr uint8_t kProvenUUID[16] = {0xa2,0x87,0xea,0x19,0xe9,0x14,0x3f,0xe9,0xb2,0xa1,0x24,0x15,0xce,0x6e,0x73,0xe9};
constexpr uint64_t kMaxImageBytes = 1024ULL * 1024 * 1024;
struct LoadedImage { const mach_header_64 *header = nullptr; std::string path; VerifiedImage verified; uint64_t max_file_end = 0; };
struct CachedImage {
    const mach_header_64 *header = nullptr;
    std::string path;
    EHRRuntimeStatus status = EHR_RUNTIME_NOT_READY;
    uint64_t file_size = 0;
};
CachedImage &cache() { static CachedImage value; return value; }
struct File { int fd; ~File() { if (fd >= 0) close(fd); } };
bool span(uintptr_t begin, uint64_t size) { return size <= std::numeric_limits<uintptr_t>::max() - begin; }
bool exactHex(const char *text, std::array<uint8_t, 32> &decoded) {
    if (!text || strnlen(text, 65) != 64) return false;
    auto nibble = [](char value) -> int {
        if (value >= '0' && value <= '9') return value - '0';
        if (value >= 'a' && value <= 'f') return value - 'a' + 10;
        return -1;
    };
    for (size_t i=0; i<decoded.size(); ++i) {
        const int high=nibble(text[i*2]), low=nibble(text[i*2+1]);
        if (high<0 || low<0) return false;
        decoded[i]=static_cast<uint8_t>((high<<4)|low);
    }
    return true;
}
EHRRuntimeStatus hashCandidate(const std::string &path, uint64_t *file_size) {
    *file_size = 0;
    std::array<uint8_t, 32> expected{}, actual{};
    if (!exactHex(EHRAssociationCandidateSHA256Hex, expected)) return EHR_RUNTIME_UNSUPPORTED;
    const File file{open(path.c_str(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW)};
    if (file.fd < 0) return EHR_RUNTIME_NOT_READY;
    struct stat before{}, after{};
    if (fstat(file.fd,&before) || !S_ISREG(before.st_mode) || before.st_size<=0 ||
        static_cast<uint64_t>(before.st_size)>kMaxImageBytes) return EHR_RUNTIME_UNSUPPORTED;
    CC_SHA256_CTX context;
    if (!CC_SHA256_Init(&context)) return EHR_RUNTIME_NOT_READY;
    std::array<uint8_t, 65536> buffer;
    uint64_t readBytes=0;
    while (true) {
        const ssize_t count=read(file.fd,buffer.data(),buffer.size());
        if (count<0) { if (errno==EINTR) continue; return EHR_RUNTIME_NOT_READY; }
        if (!count) break;
        readBytes+=static_cast<uint64_t>(count);
        if (readBytes>kMaxImageBytes || !CC_SHA256_Update(&context,buffer.data(),static_cast<CC_LONG>(count)))
            return EHR_RUNTIME_UNSUPPORTED;
    }
    if (!CC_SHA256_Final(actual.data(),&context) || fstat(file.fd,&after)) return EHR_RUNTIME_NOT_READY;
    if (readBytes!=static_cast<uint64_t>(before.st_size) || before.st_size!=after.st_size || before.st_ino!=after.st_ino ||
        before.st_dev!=after.st_dev || before.st_mtimespec.tv_sec!=after.st_mtimespec.tv_sec ||
        before.st_mtimespec.tv_nsec!=after.st_mtimespec.tv_nsec || before.st_ctimespec.tv_sec!=after.st_ctimespec.tv_sec ||
        before.st_ctimespec.tv_nsec!=after.st_ctimespec.tv_nsec) return EHR_RUNTIME_UNSUPPORTED;
    *file_size=readBytes;
    return actual==expected ? EHR_RUNTIME_OK : EHR_RUNTIME_TYPE_MISMATCH;
}
EHRRuntimeStatus loadedImage(LoadedImage &result) {
    if (strcmp(EHRAssociationSourceSHA256Hex,kProvenSourceHash)) return EHR_RUNTIME_UNSUPPORTED;
    if (memcmp(EHRAssociationFrameworkUUID,kProvenUUID,sizeof(kProvenUUID))) return EHR_RUNTIME_UNSUPPORTED;
    bool found=false;
    for (uint32_t index=0; index<_dyld_image_count(); ++index) {
        const char *path=_dyld_get_image_name(index);
        if (!path || !strstr(path,"/UnityFramework.framework/UnityFramework") ||
            strcmp(strrchr(path,'/')+1,"UnityFramework")) continue;
        const auto *header=reinterpret_cast<const mach_header_64 *>(_dyld_get_image_header(index));
        if (!header || header->magic!=MH_MAGIC_64 || header->cputype!=CPU_TYPE_ARM64 ||
            header->filetype!=MH_DYLIB || header->ncmds>16384 || header->sizeofcmds>16*1024*1024)
            return EHR_RUNTIME_UNSUPPORTED;
        const uintptr_t base=reinterpret_cast<uintptr_t>(header);
        if (!span(base,sizeof(*header)+header->sizeofcmds)) return EHR_RUNTIME_UNSUPPORTED;
        const uintptr_t end=base+sizeof(*header)+header->sizeofcmds;
        uintptr_t cursor=base+sizeof(*header);
        bool uuidFound=false, textFound=false;
        VerifiedImage image;image.base=base;image.header_end=end;
        uint64_t maxFileEnd=0;
        for (uint32_t i=0; i<header->ncmds; ++i) {
            if (cursor>end || sizeof(load_command)>end-cursor) return EHR_RUNTIME_UNSUPPORTED;
            const auto *command=reinterpret_cast<const load_command *>(cursor);
            if (command->cmdsize<sizeof(*command) || command->cmdsize%8 || command->cmdsize>end-cursor)
                return EHR_RUNTIME_UNSUPPORTED;
            if (command->cmd==LC_UUID) {
                if (uuidFound || command->cmdsize!=sizeof(uuid_command)) return EHR_RUNTIME_UNSUPPORTED;
                const auto *uuid=reinterpret_cast<const uuid_command *>(cursor);
                uuidFound=memcmp(uuid->uuid,EHRAssociationFrameworkUUID,16)==0;
                if (!uuidFound) return EHR_RUNTIME_TYPE_MISMATCH;
            } else if (command->cmd==LC_SEGMENT_64) {
                if (command->cmdsize<sizeof(segment_command_64)) return EHR_RUNTIME_UNSUPPORTED;
                const auto *segment=reinterpret_cast<const segment_command_64 *>(cursor);
                if (segment->filesize>segment->vmsize || segment->filesize>kMaxImageBytes ||
                    segment->fileoff>kMaxImageBytes-segment->filesize) return EHR_RUNTIME_UNSUPPORTED;
                if (segment->filesize && segment->fileoff+segment->filesize>maxFileEnd)
                    maxFileEnd=segment->fileoff+segment->filesize;
                const intptr_t slide=_dyld_get_image_vmaddr_slide(index);
                if (slide<0 || !span(segment->vmaddr,static_cast<uint64_t>(slide))) return EHR_RUNTIME_UNSUPPORTED;
                const uintptr_t start=segment->vmaddr+static_cast<uintptr_t>(slide);
                if (!span(start,segment->filesize)) return EHR_RUNTIME_UNSUPPORTED;
                if (!strncmp(segment->segname,"__TEXT",16)) {
                    if (textFound || segment->fileoff!=0 || start!=base) return EHR_RUNTIME_UNSUPPORTED;
                    textFound=true;
                }
                if ((segment->initprot & VM_PROT_EXECUTE) && segment->filesize)
                    image.executable_file_ranges.push_back({start,segment->filesize});
            }
            cursor+=command->cmdsize;
        }
        if (cursor!=end || !uuidFound || !textFound || image.executable_file_ranges.empty()) return EHR_RUNTIME_UNSUPPORTED;
        if (found) return EHR_RUNTIME_AMBIGUOUS;
        found=true;image.uuid_verified=true;image.source_verified=true;
        result={header,path,std::move(image),maxFileEnd};
    }
    return found ? EHR_RUNTIME_OK : EHR_RUNTIME_NOT_READY;
}
}
EHRRuntimeStatus validate(const MethodFacts &facts,uint64_t expected,uint64_t *observed) {
    if (!observed) return EHR_RUNTIME_BAD_ARGUMENT;
    *observed=0;
    if (![NSThread isMainThread]) return EHR_RUNTIME_WRONG_THREAD;
    if (!expected || expected%4) return EHR_RUNTIME_BAD_ARGUMENT;
    try {
        LoadedImage image;
        auto status=loadedImage(image);
        if (status!=EHR_RUNTIME_OK) return status;
        auto &prior=cache();
        if (prior.header!=image.header || prior.path!=image.path || prior.status==EHR_RUNTIME_NOT_READY) {
            prior.header=image.header;prior.path=image.path;
            prior.status=hashCandidate(prior.path,&prior.file_size);
        }
        if (prior.status!=EHR_RUNTIME_OK) return prior.status;
        if (image.max_file_end>prior.file_size) return EHR_RUNTIME_TYPE_MISMATCH;
        image.verified.candidate_hash_verified=true;
        // No MethodInfo field read occurs until source allowlist, loaded UUID,
        // full signed candidate-file SHA256 and executable ranges are verified.
        return compare_known_layout(facts,image.verified,expected,observed);
    } catch (...) { return EHR_RUNTIME_UNSUPPORTED; }
}
EHRRuntimeStatus validate_engine_entry(const void *entry) {
    if (!entry) return EHR_RUNTIME_BAD_ARGUMENT;
    if (![NSThread isMainThread]) return EHR_RUNTIME_WRONG_THREAD;
    try {
        LoadedImage image;
        auto status=loadedImage(image);
        if (status!=EHR_RUNTIME_OK) return status;
        auto &prior=cache();
        if (prior.header!=image.header || prior.path!=image.path || prior.status==EHR_RUNTIME_NOT_READY) {
            prior.header=image.header;prior.path=image.path;
            prior.status=hashCandidate(prior.path,&prior.file_size);
        }
        if (prior.status!=EHR_RUNTIME_OK) return prior.status;
        if (image.max_file_end>prior.file_size) return EHR_RUNTIME_TYPE_MISMATCH;
        const uintptr_t address=reinterpret_cast<uintptr_t>(entry);
        for (const auto &range:image.verified.executable_file_ranges)
            if (address%4==0 && address>=range.begin && address-range.begin<=range.size && 4<=range.size-(address-range.begin)) return EHR_RUNTIME_OK;
        return EHR_RUNTIME_TYPE_MISMATCH;
    } catch (...) { return EHR_RUNTIME_UNSUPPORTED; }
}

}
