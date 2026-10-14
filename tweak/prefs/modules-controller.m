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
@property(nonatomic,copy) void (^orderChanged)(void);
@end
@interface GVMModuleOrderCell ()
@property(nonatomic,strong) UITableView *moduleTable;
@property(nonatomic,strong) GVMModuleOrderDataSource *moduleDataSource;
@property(nonatomic,strong) UIStackView *horizontalPreview;
@property(nonatomic,strong) UIStackView *verticalPreview;
@end
@implementation GVMModuleOrderCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier specifier:(PSSpecifier *)specifier {
    if (!(self=[super initWithStyle:style reuseIdentifier:identifier specifier:specifier])) return nil;
    self.selectionStyle=UITableViewCellSelectionStyleNone;
    NSString *key=[specifier propertyForKey:@"key"];
    self.moduleDataSource=[GVMModuleOrderDataSource new];
    self.moduleDataSource.order=[GVMReadModuleOrder(key) mutableCopy];
    self.moduleDataSource.preferenceKey=key;
    self.moduleTable=[[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.moduleTable.scrollEnabled=NO; self.moduleTable.backgroundColor=UIColor.clearColor;
    self.moduleTable.rowHeight=48; self.moduleTable.dataSource=self.moduleDataSource; self.moduleTable.delegate=self.moduleDataSource;
    [self.moduleTable.heightAnchor constraintEqualToConstant:144].active=YES;
    [self.moduleTable setEditing:YES animated:NO];
    UILabel *caption=[UILabel new]; caption.text=@"Minh họa ngang và dọc"; caption.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]; caption.textColor=UIColor.secondaryLabelColor;
    self.horizontalPreview=[UIStackView new]; self.verticalPreview=[UIStackView new];
    UIStackView *previews=[[UIStackView alloc] initWithArrangedSubviews:@[self.horizontalPreview,self.verticalPreview]];
    previews.axis=UILayoutConstraintAxisHorizontal; previews.alignment=UIStackViewAlignmentCenter; previews.distribution=UIStackViewDistributionEqualSpacing; previews.spacing=8;
    UIButton *reset=[UIButton buttonWithType:UIButtonTypeSystem]; [reset setTitle:@"Đặt lại" forState:UIControlStateNormal]; reset.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;
    [reset.heightAnchor constraintEqualToConstant:44].active=YES;
    [reset addTarget:self action:@selector(resetOrder) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[caption,previews,self.moduleTable,reset]];
    stack.axis=UILayoutConstraintAxisVertical; stack.spacing=8; stack.translatesAutoresizingMaskIntoConstraints=NO;
    [self.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],[stack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],[stack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12],[stack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-12]]];
    __weak GVMModuleOrderCell *weakSelf=self;
    self.moduleDataSource.orderChanged=^{ [weakSelf refreshPreview]; };
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(settingsChanged) name:@"GVMPreferencesValueChanged" object:nil];
    [self refreshPreview]; return self;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)layoutSubviews { [super layoutSubviews]; self.textLabel.hidden=YES; self.detailTextLabel.hidden=YES; }
- (void)settingsChanged { self.moduleDataSource.order=[GVMReadModuleOrder(self.moduleDataSource.preferenceKey) mutableCopy]; [self.moduleTable reloadData]; [self refreshPreview]; }
- (void)refreshPreview {
    for (UIStackView *preview in @[self.horizontalPreview,self.verticalPreview]) {
    preview.axis=preview==self.verticalPreview ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
    preview.spacing=0; preview.distribution=UIStackViewDistributionFillEqually;
    preview.backgroundColor=[UIColor colorWithWhite:0.12 alpha:0.65]; preview.layer.cornerRadius=preview==self.verticalPreview ? 25 : 14; preview.clipsToBounds=YES;
    for (UIView *view in preview.arrangedSubviews.copy) { [preview removeArrangedSubview:view]; [view removeFromSuperview]; }
    id saved=CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)self.moduleDataSource.preferenceKey,CFSTR("com.chou.gmaphud")));
    NSArray *previewOrder=GVMNormalizeModuleOrder(saved,preview==self.verticalPreview);
    for (NSString *module in previewOrder) {
        UIView *tile=[UIView new]; tile.backgroundColor=UIColor.clearColor;
        [tile.widthAnchor constraintEqualToConstant:50].active=YES; [tile.heightAnchor constraintEqualToConstant:50].active=YES;
        BOOL speed=[module isEqual:@"speed"], limit=[module isEqual:@"limit"];
        UILabel *value=[UILabel new]; value.text=speed ? @"54" : limit ? @"60" : @"80"; value.textAlignment=NSTextAlignmentCenter;
        value.font=[UIFont systemFontOfSize:19 weight:UIFontWeightSemibold]; value.textColor=speed ? UIColor.whiteColor : UIColor.blackColor;
        value.translatesAutoresizingMaskIntoConstraints=NO;
        if (!speed) { value.backgroundColor=UIColor.whiteColor; value.layer.cornerRadius=17; value.layer.masksToBounds=YES; value.layer.borderColor=UIColor.systemRedColor.CGColor; value.layer.borderWidth=4; }
        [tile addSubview:value];
        if (!speed) {
            NSString *filename=limit ? @"speed_limit_60.png" : @"speed_limit_80.png";
            UIImage *image=nil;
            for (NSString *root in @[@"/var/jb/usr/share/gmaphud/gmaphud",@"/usr/share/gmaphud/gmaphud"]) { image=[UIImage imageWithContentsOfFile:[root stringByAppendingPathComponent:filename]]; if (image) break; }
            if (image) {
                value.text=@""; value.layer.borderWidth=0; value.backgroundColor=UIColor.clearColor;
                UIImageView *sign=[[UIImageView alloc] initWithImage:image]; sign.contentMode=UIViewContentModeScaleAspectFit; sign.translatesAutoresizingMaskIntoConstraints=NO; [value addSubview:sign];
                [NSLayoutConstraint activateConstraints:@[[sign.leadingAnchor constraintEqualToAnchor:value.leadingAnchor],[sign.trailingAnchor constraintEqualToAnchor:value.trailingAnchor],[sign.topAnchor constraintEqualToAnchor:value.topAnchor],[sign.bottomAnchor constraintEqualToAnchor:value.bottomAnchor]]];
            }
        }
        UILabel *unit=[UILabel new]; unit.text=speed ? @"km/h" : limit ? @"" : @"200 m"; unit.font=[UIFont systemFontOfSize:9]; unit.textAlignment=NSTextAlignmentCenter; unit.textColor=UIColor.whiteColor; unit.translatesAutoresizingMaskIntoConstraints=NO; [tile addSubview:unit];
        [NSLayoutConstraint activateConstraints:@[[value.widthAnchor constraintEqualToConstant:34],[value.heightAnchor constraintEqualToConstant:34],[value.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor],[value.topAnchor constraintEqualToAnchor:tile.topAnchor constant:3],[unit.topAnchor constraintEqualToAnchor:value.bottomAnchor constant:1],[unit.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor]]];
        tile.isAccessibilityElement=YES; tile.accessibilityLabel=@{@"speed":@"Tốc độ hiện tại",@"limit":@"Giới hạn hiện tại",@"alerts":@"Cảnh báo sắp tới"}[module];
        [preview addArrangedSubview:tile];
    }
    }
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
    [self refreshPreview];
}
@end
// A plain UIKit delegate avoids PSListController callbacks that expect specifiers.
@implementation GVMModuleOrderDataSource
- (NSInteger)numberOfSectionsInTableView:(__unused UITableView *)table { return 1; }
- (NSInteger)tableView:(__unused UITableView *)table numberOfRowsInSection:(__unused NSInteger)section { return self.order.count; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[table dequeueReusableCellWithIdentifier:@"module"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"module"];
    cell.textLabel.text=@{@"speed":@"Tốc độ hiện tại",@"limit":@"Giới hạn hiện tại",@"alerts":@"Cảnh báo sắp tới"}[self.order[path.row]];
    cell.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.adjustsFontForContentSizeCategory=YES; cell.textLabel.numberOfLines=0;
    cell.showsReorderControl=YES; cell.selectionStyle=UITableViewCellSelectionStyleNone; return cell;
}
- (BOOL)tableView:(__unused UITableView *)table canMoveRowAtIndexPath:(__unused NSIndexPath *)path { return YES; }
- (UITableViewCellEditingStyle)tableView:(__unused UITableView *)table editingStyleForRowAtIndexPath:(__unused NSIndexPath *)path { return UITableViewCellEditingStyleNone; }
- (BOOL)tableView:(__unused UITableView *)table shouldIndentWhileEditingRowAtIndexPath:(__unused NSIndexPath *)path { return NO; }

- (void)tableView:(__unused UITableView *)table moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
    NSString *item=self.order[from.row]; [self.order removeObjectAtIndex:from.row]; [self.order insertObject:item atIndex:to.row];
    NSString *key=self.preferenceKey;
    if (![@[@"fullModules",@"dashboardModules",@"phoneModules"] containsObject:key]) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key,(__bridge CFArrayRef)self.order,CFSTR("com.chou.gmaphud"));
    if (CFPreferencesAppSynchronize(CFSTR("com.chou.gmaphud"))) { GVMPublishSavedSizes(); notify_post(GVMSizeChangedName); if (self.orderChanged) self.orderChanged(); }
}
@end
