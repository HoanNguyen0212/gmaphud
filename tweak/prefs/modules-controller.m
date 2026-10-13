#import "modules-controller.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import "placement-state.h"
#include <notify.h>

static NSArray<NSString *> *GVMReadModuleOrder(NSString *key) {
    CFPreferencesAppSynchronize(CFSTR("com.chou.gmaphud"));
    id saved=CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,CFSTR("com.chou.gmaphud")));
    NSString *layoutKey=[key stringByReplacingOccurrencesOfString:@"Modules" withString:@"Layout"];
    id layout=CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)layoutKey,CFSTR("com.chou.gmaphud")));
    BOOL vertical=[layout isEqual:@"vertical"] || (![layout isEqual:@"horizontal"] &&
        ([key isEqual:@"dashboardModules"] || ([key isEqual:@"phoneModules"] && UIScreen.mainScreen.bounds.size.height>UIScreen.mainScreen.bounds.size.width)));
    return GVMNormalizeModuleOrder(saved,vertical);
}

@interface GVMModuleOrderDataSource : NSObject <UITableViewDataSource,UITableViewDelegate>
@property(nonatomic,strong) NSMutableArray<NSString *> *order;
@property(nonatomic,copy) NSString *preferenceKey;
@end
@interface GVMModuleOrderController ()
@property(nonatomic,strong) UITableView *moduleTable;
@property(nonatomic,strong) GVMModuleOrderDataSource *moduleDataSource;
@end
@implementation GVMModuleOrderController
- (NSArray *)specifiers { if (!_specifiers) _specifiers=[NSMutableArray new]; return _specifiers; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=self.specifier.name;
    NSString *key=[self.specifier propertyForKey:@"key"];
    self.moduleDataSource=[GVMModuleOrderDataSource new];
    self.moduleDataSource.order=[GVMReadModuleOrder(key) mutableCopy];
    self.moduleDataSource.preferenceKey=key;
    self.moduleTable=[[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.moduleTable.translatesAutoresizingMaskIntoConstraints=NO;
    self.moduleTable.dataSource=self.moduleDataSource; self.moduleTable.delegate=self.moduleDataSource;
    UIView *footer=[[UIView alloc] initWithFrame:CGRectMake(0,0,self.view.bounds.size.width,60)];
    UIButton *reset=[UIButton buttonWithType:UIButtonTypeSystem];
    reset.translatesAutoresizingMaskIntoConstraints=NO;
    [reset setTitle:@"Đặt lại thứ tự" forState:UIControlStateNormal];
    reset.titleLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    reset.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;
    reset.contentEdgeInsets=UIEdgeInsetsMake(0,16,0,16);
    reset.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;
    reset.layer.cornerRadius=10;
    [reset addTarget:self action:@selector(resetOrder) forControlEvents:UIControlEventTouchUpInside];
    [footer addSubview:reset];
    [NSLayoutConstraint activateConstraints:@[
        [reset.topAnchor constraintEqualToAnchor:footer.topAnchor],
        [reset.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor constant:16],
        [reset.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor constant:-16],
        [reset.heightAnchor constraintEqualToConstant:44]
    ]];
    self.moduleTable.tableFooterView=footer;
    [self.view addSubview:self.moduleTable];
    [NSLayoutConstraint activateConstraints:@[
        [self.moduleTable.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.moduleTable.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [self.moduleTable.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.moduleTable.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]]];
    [self.moduleTable reloadData];
    [self.moduleTable setEditing:YES animated:NO];
}
- (void)resetOrder {
    NSString *key=self.moduleDataSource.preferenceKey;
    if (![@[@"fullModules",@"dashboardModules",@"phoneModules"] containsObject:key]) return;
    // Removing the override keeps the default responsive to the selected orientation.
    CFPreferencesSetAppValue((__bridge CFStringRef)key,NULL,CFSTR("com.chou.gmaphud"));
    if (!CFPreferencesAppSynchronize(CFSTR("com.chou.gmaphud"))) return;
    GVMPublishSavedSizes(); notify_post(GVMSizeChangedName);
    self.moduleDataSource.order=[GVMReadModuleOrder(key) mutableCopy];
    [self.moduleTable reloadData];
}
@end
// A plain UIKit delegate avoids PSListController callbacks that expect specifiers.
@implementation GVMModuleOrderDataSource
- (NSInteger)numberOfSectionsInTableView:(__unused UITableView *)table { return 1; }
- (NSInteger)tableView:(__unused UITableView *)table numberOfRowsInSection:(__unused NSInteger)section { return self.order.count; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[table dequeueReusableCellWithIdentifier:@"module"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"module"];
    cell.textLabel.text=@{@"speed":@"Tốc độ hiện tại",@"limit":@"Giới hạn hiện tại",@"alerts":@"Cảnh báo sắp tới"}[self.order[path.row]];
    cell.showsReorderControl=YES; cell.selectionStyle=UITableViewCellSelectionStyleNone; return cell;
}
- (BOOL)tableView:(__unused UITableView *)table canMoveRowAtIndexPath:(__unused NSIndexPath *)path { return YES; }
- (UITableViewCellEditingStyle)tableView:(__unused UITableView *)table editingStyleForRowAtIndexPath:(__unused NSIndexPath *)path { return UITableViewCellEditingStyleNone; }
- (BOOL)tableView:(__unused UITableView *)table shouldIndentWhileEditingRowAtIndexPath:(__unused NSIndexPath *)path { return NO; }
- (NSString *)tableView:(__unused UITableView *)table titleForFooterInSection:(__unused NSInteger)section { return @"Thứ tự từ trái sang phải ở bố cục ngang, từ trên xuống dưới ở bố cục dọc. Cảnh báo sắp tới tự ẩn khi không có dữ liệu."; }
- (void)tableView:(__unused UITableView *)table moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
    NSString *item=self.order[from.row]; [self.order removeObjectAtIndex:from.row]; [self.order insertObject:item atIndex:to.row];
    NSString *key=self.preferenceKey;
    if (![@[@"fullModules",@"dashboardModules",@"phoneModules"] containsObject:key]) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key,(__bridge CFArrayRef)self.order,CFSTR("com.chou.gmaphud"));
    if (CFPreferencesAppSynchronize(CFSTR("com.chou.gmaphud"))) { GVMPublishSavedSizes(); notify_post(GVMSizeChangedName); }
}
@end
