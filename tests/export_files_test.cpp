#define EHR_EXPORT_TESTING 1
#include "../native/EHRExportFiles.hpp"
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>

namespace fs=std::filesystem;
static size_t checks=0;
static void check(bool value,const char*label){checks++;if(!value)throw std::runtime_error(label);}
static void writeFile(const fs::path&p,const std::string&text){fs::create_directories(p.parent_path());std::ofstream out(p,std::ios::binary);out<<text;}
static std::string readFile(const fs::path&p){std::ifstream in(p,std::ios::binary);return {std::istreambuf_iterator<char>(in),{}};}
static ehr::exports::Entry find(const ehr::exports::Scan&scan,const std::string&name){for(auto&entry:scan.entries)if(entry.relative==name)return entry;throw std::runtime_error("fixture row missing");}
static void appendDuringRead(void*context){std::ofstream out(*static_cast<fs::path*>(context),std::ios::app);out<<"changed";}
int main(){
    char pattern[]="/tmp/ehr-own-exports-XXXXXX";char*created=mkdtemp(pattern);if(!created)return 2;fs::path base(created),root=base/"EHRSource",dest=base/"snapshots";
    try{
        using namespace ehr::exports;fs::create_directories(root);fs::create_directory(dest);
        std::string log="EHR_Logs/2026-10-28_10.35.00/EHR-v8.0.3-LOG.html",translation="Language/export_English.dat";
        writeFile(root/log,"<html>completed own fixture</html>\n");writeFile(root/translation,"Own.Key:Own translated fixture\n");
        writeFile(root/"BepInEx/log.html","live log excluded");writeFile(root/"config/EHR.cfg","own excluded fixture");writeFile(root/"Language/template.dat","excluded template");writeFile(root/"Language/English.dat","excluded input");writeFile(root/"EHR_Logs/log.html","live excluded");
        auto rows=scan(root.string());check(rows.entries.size()==2,"only completed-shaped outputs listed");
        FD output(open(dest.c_str(),O_RDONLY|O_DIRECTORY|O_NOFOLLOW));std::string name,error;auto selected=find(rows,log);
        check(snapshot(root.string(),selected,output.value,name,error),"snapshot succeeds");check(name=="EHR-v8.0.3-LOG.html","snapshot basename");check(readFile(dest/name)==readFile(root/log),"snapshot exact full contents");
        struct stat mode{};lstat((dest/name).c_str(),&mode);check((mode.st_mode&0777)==0400,"snapshot read only");
        check(!snapshot(root.string(),selected,output.value,name,error),"snapshot never overwrites");check(readFile(root/log)=="<html>completed own fixture</html>\n","source export untouched");
        auto changed=find(rows,translation);writeFile(root/translation,"different completed own fixture\n");
        check(!snapshot(root.string(),changed,output.value,name,error),"changed since list rejected");check(!fs::exists(dest/"export_English.dat"),"changed file not shared");
        rows=scan(root.string());changed=find(rows,translation);auto oldFile=root/"old.dat";fs::rename(root/translation,oldFile);writeFile(root/translation,"different completed own fixture\n");
        check(!snapshot(root.string(),changed,output.value,name,error),"replaced inode rejected");
        auto forged=selected;forged.relative="../config/EHR.cfg";check(!snapshot(root.string(),forged,output.value,name,error),"traversal row rejected");
        forged=selected;forged.relative="EHR_Logs/2026-10-28_10.35.00/../../config/EHR.cfg";check(!snapshot(root.string(),forged,output.value,name,error),"extra path row rejected");
        writeFile(base/"outside.dat","own outside fixture");fs::create_symlink(base/"outside.dat",root/"Language/export_Link.dat");
        rows=scan(root.string());check(rows.entries.size()==2,"linked file excluded");
        fs::create_directory_symlink(base,root/"EHR_Logs/2026-10-29_10.35.00");check(scan(root.string()).entries.size()==2,"linked timestamp excluded");
        fs::create_directory_symlink(root,base/"root-link");check(scan((base/"root-link").string()).entries.empty(),"linked own root rejected");
        writeFile(root/"Language/export_Hard.dat","hard link fixture");fs::create_hard_link(root/"Language/export_Hard.dat",base/"hard-copy.dat");check(scan(root.string()).entries.size()==2,"hard linked output excluded");
        fs::create_directory(root/"Language/export_Directory.dat");mkfifo((root/"Language/export_Pipe.dat").c_str(),0600);check(scan(root.string()).entries.size()==2,"directory and pipe excluded without blocking");
        writeFile(root/"Language/export_Empty.dat","");check(scan(root.string()).entries.size()==2,"empty partial output excluded");
        FD huge(open((root/"Language/export_Huge.dat").c_str(),O_WRONLY|O_CREAT|O_EXCL,0600));ftruncate(huge.value,9*1024*1024);check(scan(root.string()).entries.size()==2,"oversized output excluded");
        for(auto invalid:{"2026-02-29_00.00.00","2026-04-31_00.00.00","2026-10-28_24.00.00","2026-10-28_10.60.00","2026-10-28_10.00.60","0000-10-28_10.00.00","2026-10-28_10:35:00","../2026-10-28_10.35.00"})check(!timestamp(invalid),"invalid timestamp rejected");
        check(timestamp("2024-02-29_23.59.59"),"Gregorian leap timestamp accepted");
        for(auto invalid:{"EHR-v8.0.3-LOG.html.tmp","EHR-v../x-LOG.html","EHR-v-LOG.html","log.html","EHR-v8.0.3-LOG.htm"})check(!logName(invalid),"invalid log name rejected");
        for(auto invalid:{"export_.dat","template.dat","export_English.dat.tmp","export_../outside.dat","export_English.json"})check(!translationName(invalid),"invalid translation name rejected");
        std::string racing="Language/export_Racing.dat";writeFile(root/racing,std::string(100000,'R'));auto race=find(scan(root.string()),racing);fs::path racePath=root/racing;
        check(!snapshot(root.string(),race,output.value,name,error,appendDuringRead,&racePath),"modification during snapshot rejected");check(!fs::exists(dest/"export_Racing.dat"),"failed partial private snapshot removed");
        auto rootChanged=selected;rootChanged.rootInode++;check(!snapshot(root.string(),rootChanged,output.value,name,error),"root replacement facts rejected");
        auto translationEntry=find(scan(root.string()),translation);check(snapshot(root.string(),translationEntry,output.value,name,error),"translation snapshot succeeds");check(readFile(dest/name)==readFile(root/translation),"translation exact contents");
        fs::path many=base/"many";fs::create_directories(many/"Language");for(size_t i=0;i<MaximumEntries+3;i++)writeFile(many/"Language"/("export_Own"+std::to_string(i)+".dat"),"Key:Value\n");
        auto limited=scan(many.string());check(limited.limited&&limited.entries.size()==MaximumEntries,"candidate count bounded");
        fs::path budget=base/"budget";fs::create_directories(budget/"Language");for(size_t i=0;i<ScanBudget+2;i++)writeFile(budget/"Language"/("ignored"+std::to_string(i)),"x");check(scan(budget.string()).limited,"directory walk globally bounded");
        check(readFile(base/"outside.dat")=="own outside fixture","outside file unchanged");
        fs::remove_all(base);std::cout<<"PASS "<<checks<<" allowlist/snapshot checks; own fixture files only; no UIKit presentation, game, account or network\n";return 0;
    }catch(const std::exception&error){std::cerr<<error.what()<<"\n";fs::remove_all(base);return 1;}
}
