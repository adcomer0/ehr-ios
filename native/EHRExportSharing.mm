#import "EHRExportSharing.h"
#include "EHRExportFiles.hpp"

@interface EHRExportListController:UITableViewController {
    ehr::exports::Scan _scan;
}
@property(nonatomic,copy) NSString *sourceRoot;
@end
@implementation EHRExportListController
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"Share EHR exports";
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refreshExports)];
    NSURL *support=[[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:nil];
    self.sourceRoot=[support URLByAppendingPathComponent:@"EHRSource" isDirectory:YES].path;
    [self refreshExports];
}
- (void)done {[self.navigationController dismissViewControllerAnimated:YES completion:nil];}
- (void)refreshExports {
    try{_scan=self.sourceRoot?ehr::exports::scan(self.sourceRoot.fileSystemRepresentation):ehr::exports::Scan{};}
    catch(...){_scan={};}
    if(_scan.entries.empty()){
        UILabel *empty=[UILabel new];empty.numberOfLines=0;empty.textAlignment=NSTextAlignmentCenter;empty.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        empty.text=@"No completed exports yet.\n\nUse Dump log or Export translation in EHR controls, then tap Refresh.";self.tableView.backgroundView=empty;
    }else self.tableView.backgroundView=nil;
    [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {(void)tableView;(void)section;return static_cast<NSInteger>(_scan.entries.size());}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;(void)section;
    return _scan.limited?@"The list is limited to available recent exports. Select one file to open the iOS share sheet.":@"Select one completed log or translation file to open the iOS share sheet.";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"export"];
    if(!cell)cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"export"];
    const auto&entry=_scan.entries.at(static_cast<size_t>(indexPath.row));NSString *relative=[NSString stringWithUTF8String:entry.relative.c_str()];
    cell.textLabel.text=relative.lastPathComponent;cell.textLabel.numberOfLines=2;
    cell.detailTextLabel.text=[NSString stringWithFormat:@"%@ · %@",entry.kind==ehr::exports::Kind::Log?relative.stringByDeletingLastPathComponent.lastPathComponent:@"Translation",[NSByteCountFormatter stringFromByteCount:entry.file.st_size countStyle:NSByteCountFormatterCountStyleFile]];
    cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return cell;
}
- (void)showError:(NSString *)message {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Export unavailable" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:alert animated:YES completion:nil];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if(static_cast<size_t>(indexPath.row)>=_scan.entries.size())return;
    try{
        const auto entry=_scan.entries.at(static_cast<size_t>(indexPath.row));
        // Create a unique private snapshot beneath this app's own temporary
        // directory. Existing source exports and snapshots are never replaced.
        NSString *temporary=NSTemporaryDirectory();
        ehr::exports::FD temp(open(temporary.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC));
        if(temp.value<0||(mkdirat(temp.value,"EHRExportShare",0700)&&errno!=EEXIST)){[self showError:@"A private temporary folder could not be created."];return;}
        ehr::exports::FD share(ehr::exports::directory(temp.value,"EHRExportShare"));NSString *session=NSUUID.UUID.UUIDString;
        if(share.value<0||mkdirat(share.value,session.UTF8String,0700)){[self showError:@"A private temporary folder could not be created."];return;}
        ehr::exports::FD destination(ehr::exports::directory(share.value,session.UTF8String));std::string basename,error;
        if(destination.value<0||!ehr::exports::snapshot(self.sourceRoot.fileSystemRepresentation,entry,destination.value,basename,error)){
            [self showError:error.empty()?@"The export snapshot could not be completed.":[NSString stringWithUTF8String:error.c_str()]];return;
        }
        NSURL *url=[NSURL fileURLWithPath:[[[temporary stringByAppendingPathComponent:@"EHRExportShare"] stringByAppendingPathComponent:session] stringByAppendingPathComponent:[NSString stringWithUTF8String:basename.c_str()]]];
        UIActivityViewController *activity=[[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
        UIPopoverPresentationController *popover=activity.popoverPresentationController;
        if(popover){popover.sourceView=tableView;popover.sourceRect=[tableView rectForRowAtIndexPath:indexPath];}
        // Keep the completed read-only snapshot for the system activity's full
        // lifetime; normal OS temporary-file cleanup owns its later retirement.
        [self presentViewController:activity animated:YES completion:nil];
    }catch(...){[self showError:@"The export snapshot could not be completed."];}
}
@end

UIViewController *EHRExportSharingController(void) {
    EHRExportListController *list=[[EHRExportListController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *navigation=[[UINavigationController alloc] initWithRootViewController:list];navigation.modalPresentationStyle=UIModalPresentationFormSheet;return navigation;
}
