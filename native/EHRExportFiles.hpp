#pragma once
#include <algorithm>
#include <cerrno>
#include <cstdint>
#include <cstring>
#include <dirent.h>
#include <fcntl.h>
#include <string>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

namespace ehr::exports {
struct FD {
    int value=-1;
    explicit FD(int fd=-1):value(fd){}
    ~FD(){if(value>=0)close(value);}
    FD(const FD&)=delete;FD&operator=(const FD&)=delete;
};
enum class Kind {Log,Translation};
struct Entry {
    Kind kind=Kind::Log;
    std::string relative;
    struct stat file{};
    dev_t rootDevice{};ino_t rootInode{};
};
struct Scan {std::vector<Entry> entries;bool limited=false;};
constexpr size_t ScanBudget=4096,MaximumEntries=128;
inline uint64_t maximum(Kind kind){return kind==Kind::Log?16*1024*1024:8*1024*1024;}
inline bool asciiDigit(char c){return c>='0'&&c<='9';}
inline bool asciiLetter(char c){return (c>='A'&&c<='Z')||(c>='a'&&c<='z');}
inline int number(const std::string&s,size_t start,size_t count){int n=0;for(size_t i=start;i<start+count;i++){if(!asciiDigit(s[i]))return -1;n=n*10+s[i]-'0';}return n;}
inline bool timestamp(const std::string&s){
    if(s.size()!=19||s[4]!='-'||s[7]!='-'||s[10]!='_'||s[13]!='.'||s[16]!='.')return false;
    int year=number(s,0,4),month=number(s,5,2),day=number(s,8,2),hour=number(s,11,2),minute=number(s,14,2),second=number(s,17,2);
    if(year<1||month<1||month>12||hour<0||hour>23||minute<0||minute>59||second<0||second>59)return false;
    const int days[]={31,28,31,30,31,30,31,31,30,31,30,31};int last=days[month-1];
    if(month==2&&year%4==0&&(year%100!=0||year%400==0))last++;
    return day>=1&&day<=last;
}
inline bool logName(const std::string&s){
    const std::string prefix="EHR-v",suffix="-LOG.html";
    if(s.size()<=prefix.size()+suffix.size()||s.size()>96||s.compare(0,prefix.size(),prefix)||s.compare(s.size()-suffix.size(),suffix.size(),suffix))return false;
    for(size_t i=prefix.size();i<s.size()-suffix.size();i++)if(!asciiDigit(s[i])&&!asciiLetter(s[i])&&s[i]!='.'&&s[i]!='_'&&s[i]!='+'&&s[i]!='-')return false;
    return asciiDigit(s[prefix.size()]);
}
inline bool translationName(const std::string&s){
    const std::string prefix="export_",suffix=".dat";
    if(s.size()<=prefix.size()+suffix.size()||s.size()>80||s.compare(0,prefix.size(),prefix)||s.compare(s.size()-suffix.size(),suffix.size(),suffix))return false;
    for(size_t i=prefix.size();i<s.size()-suffix.size();i++)if(!asciiDigit(s[i])&&!asciiLetter(s[i])&&s[i]!='_')return false;
    return true;
}
inline bool parts(const std::string&relative,Kind&kind,std::vector<std::string>&out){
    out.clear();size_t start=0;
    for(size_t i=0;i<=relative.size();i++)if(i==relative.size()||relative[i]=='/'){out.push_back(relative.substr(start,i-start));start=i+1;}
    if(out.size()==3&&out[0]=="EHR_Logs"&&timestamp(out[1])&&logName(out[2])){kind=Kind::Log;return true;}
    if(out.size()==2&&out[0]=="Language"&&translationName(out[1])){kind=Kind::Translation;return true;}
    return false;
}
inline int directory(int parent,const std::string&name){return openat(parent,name.c_str(),O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);}
inline bool regular(const struct stat&s,Kind kind){return S_ISREG(s.st_mode)&&s.st_nlink==1&&s.st_size>0&&static_cast<uint64_t>(s.st_size)<=maximum(kind);}
inline bool same(const struct stat&a,const struct stat&b){
    if(a.st_dev!=b.st_dev||a.st_ino!=b.st_ino||a.st_size!=b.st_size||a.st_nlink!=b.st_nlink||a.st_mode!=b.st_mode)return false;
#if defined(__APPLE__)
    return a.st_mtimespec.tv_sec==b.st_mtimespec.tv_sec&&a.st_mtimespec.tv_nsec==b.st_mtimespec.tv_nsec&&a.st_ctimespec.tv_sec==b.st_ctimespec.tv_sec&&a.st_ctimespec.tv_nsec==b.st_ctimespec.tv_nsec;
#else
    return a.st_mtim.tv_sec==b.st_mtim.tv_sec&&a.st_mtim.tv_nsec==b.st_mtim.tv_nsec&&a.st_ctim.tv_sec==b.st_ctim.tv_sec&&a.st_ctim.tv_nsec==b.st_ctim.tv_nsec;
#endif
}
template<class Visit>inline void list(int fd,size_t&budget,bool&limited,Visit visit){
    DIR*stream=fdopendir(dup(fd));if(!stream)return;
    while(auto*item=readdir(stream)){
        std::string name(item->d_name);if(name=="."||name=="..")continue;
        if(budget==0){limited=true;break;}budget--;visit(name);
    }
    closedir(stream);
}
inline void candidate(Scan&scan,int parent,const std::string&name,const std::string&relative,Kind kind,const struct stat&root){
    FD file(openat(parent,name.c_str(),O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC));struct stat facts{};
    if(file.value<0||fstat(file.value,&facts)||!regular(facts,kind))return;
    scan.entries.push_back({kind,relative,facts,root.st_dev,root.st_ino});
}
inline Scan scan(const std::string&rootPath){
    Scan result;FD root(open(rootPath.c_str(),O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC));struct stat rootFacts{};
    if(root.value<0||fstat(root.value,&rootFacts))return result;
    size_t budget=ScanBudget;FD logs(directory(root.value,"EHR_Logs"));
    if(logs.value>=0)list(logs.value,budget,result.limited,[&](const std::string&date){
        if(!timestamp(date))return;FD folder(directory(logs.value,date));if(folder.value<0)return;
        list(folder.value,budget,result.limited,[&](const std::string&name){if(logName(name))candidate(result,folder.value,name,"EHR_Logs/"+date+"/"+name,Kind::Log,rootFacts);});
    });
    FD language(directory(root.value,"Language"));
    if(language.value>=0)list(language.value,budget,result.limited,[&](const std::string&name){if(translationName(name))candidate(result,language.value,name,"Language/"+name,Kind::Translation,rootFacts);});
    std::sort(result.entries.begin(),result.entries.end(),[](const Entry&a,const Entry&b){
        if(a.file.st_mtime!=b.file.st_mtime)return a.file.st_mtime>b.file.st_mtime;return a.relative>b.relative;
    });
    if(result.entries.size()>MaximumEntries){result.limited=true;result.entries.resize(MaximumEntries);}return result;
}
// An approved row is reopened by directory descriptors without following links.
// The destination directory is a new private per-tap folder. Its filename is
// created exclusively; neither existing source exports nor snapshots overwrite.
inline bool snapshot(const std::string&rootPath,const Entry&entry,int destination,std::string&basename,std::string&error
#if defined(EHR_EXPORT_TESTING)
    ,void(*afterRead)(void*)=nullptr,void*context=nullptr
#endif
){
    std::vector<std::string> path;Kind kind{};
    if(!parts(entry.relative,kind,path)||kind!=entry.kind){error="Export path is not allowed.";return false;}
    FD root(open(rootPath.c_str(),O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC));struct stat rootFacts{};
    if(root.value<0||fstat(root.value,&rootFacts)||rootFacts.st_dev!=entry.rootDevice||rootFacts.st_ino!=entry.rootInode){error="Export folder changed. Refresh the list.";return false;}
    int parent=root.value;std::vector<int> opened;
    for(size_t i=0;i+1<path.size();i++){
        int next=directory(parent,path[i]);if(next<0){for(int fd:opened)close(fd);error="Export folder is unavailable.";return false;}opened.push_back(next);parent=next;
    }
    FD source(openat(parent,path.back().c_str(),O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC));for(int fd:opened)close(fd);
    struct stat before{};
    if(source.value<0||fstat(source.value,&before)||!regular(before,kind)||!same(before,entry.file)){error="Export changed. Refresh the list.";return false;}
    FD output(openat(destination,path.back().c_str(),O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600));
    if(output.value<0){error="A private export snapshot could not be created.";return false;}
    struct stat created{};bool hasIdentity=fstat(output.value,&created)==0;
    auto reject=[&](const char*message){
        struct stat current{};if(hasIdentity&&!fstatat(destination,path.back().c_str(),&current,AT_SYMLINK_NOFOLLOW)&&current.st_dev==created.st_dev&&current.st_ino==created.st_ino)unlinkat(destination,path.back().c_str(),0);
        error=message;return false;
    };
    if(!hasIdentity)return reject("The snapshot identity could not be checked.");
    uint64_t copied=0;char buffer[16384];
    while(copied<static_cast<uint64_t>(before.st_size)){
        ssize_t count=read(source.value,buffer,std::min<size_t>(sizeof(buffer),static_cast<size_t>(before.st_size-copied)));
        if(count<0&&errno==EINTR)continue;if(count<=0)return reject("Export changed while copying. Try again.");
        for(ssize_t offset=0;offset<count;){ssize_t written=write(output.value,buffer+offset,static_cast<size_t>(count-offset));if(written<0&&errno==EINTR)continue;if(written<=0)return reject("The export snapshot could not be written.");offset+=written;}
        copied+=static_cast<uint64_t>(count);
#if defined(EHR_EXPORT_TESTING)
        if(afterRead){auto callback=afterRead;afterRead=nullptr;callback(context);}
#endif
    }
    char extra;ssize_t extraCount;do{extraCount=read(source.value,&extra,1);}while(extraCount<0&&errno==EINTR);
    struct stat after{},saved{};
    if(extraCount!=0||fstat(source.value,&after)||!same(before,after)||fstat(output.value,&saved)||saved.st_size!=before.st_size||saved.st_nlink!=1)return reject("Export changed while copying. Refresh the list.");
    if(fsync(output.value)||fchmod(output.value,0400))return reject("The export snapshot could not be completed.");
    basename=path.back();error.clear();return true;
}
} // namespace ehr::exports
