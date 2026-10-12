#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
#import <UIKit/UIKit.h>
#import "placement-state.h"
#import "diagnostics-controller.h"
#include <notify.h>
#include <math.h>
#import "background-policy.h"

@interface GVMReferenceSlider : UISlider
@property(nonatomic, strong) UIView *referenceMark;
@end
@implementation GVMReferenceSlider
- (instancetype)initWithFrame:(CGRect)frame {
    self=[super initWithFrame:frame];
    if (self) {
        self.referenceMark=[UIView new];
        self.referenceMark.backgroundColor=UIColor.secondaryLabelColor;
        self.referenceMark.userInteractionEnabled=NO;
        self.referenceMark.layer.cornerRadius=1;
        [self addSubview:self.referenceMark];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect track=[self trackRectForBounds:self.bounds];
    // Both ranges put the neutral value at the track midpoint.
    self.referenceMark.frame=CGRectMake(CGRectGetMidX(track)-1,CGRectGetMidY(track)-2,2,4);
    CGRect thumb=[self thumbRectForBounds:self.bounds trackRect:track value:self.value];
    self.referenceMark.hidden=CGRectIntersectsRect(thumb,self.referenceMark.frame);
}
@end

@interface GVMSizeSliderCell : PSTableCell
@property(nonatomic, copy) NSString *sizeKey;
@property(nonatomic, strong) UISlider *sizeSlider;
@property(nonatomic, strong) UILabel *sizeLabel;
@property(nonatomic, strong) UILabel *valueLabel;
@property(nonatomic, copy) NSString *sizeTitle;
@property(nonatomic) BOOL offset;
@property(nonatomic) BOOL atNeutral;
@property(nonatomic, strong) UISelectionFeedbackGenerator *feedback;
@end
@implementation GVMSizeSliderCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier specifier:(PSSpecifier *)specifier {
    self=[super initWithStyle:style reuseIdentifier:identifier specifier:specifier];
    if (!self) return nil;
    self.selectionStyle=UITableViewCellSelectionStyleNone;
    self.textLabel.hidden=YES;
    self.detailTextLabel.hidden=YES;
    self.contentView.userInteractionEnabled=YES;
    self.sizeKey=[specifier propertyForKey:@"key"];
    self.sizeTitle=specifier.name;
    self.sizeLabel=[UILabel new];
    self.sizeLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.sizeLabel.numberOfLines=2;
    self.sizeLabel.text=self.sizeTitle;
    self.valueLabel=[UILabel new];
    self.valueLabel.font=[UIFont monospacedDigitSystemFontOfSize:16 weight:UIFontWeightMedium];
    self.valueLabel.textAlignment=NSTextAlignmentRight;
    [self.valueLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    self.sizeSlider=[[GVMReferenceSlider alloc] initWithFrame:CGRectZero];
    self.feedback=[UISelectionFeedbackGenerator new];
    self.offset=[@[@"phoneXPercent",@"phoneYPercent"] containsObject:self.sizeKey];
    self.sizeSlider.minimumValue=self.offset ? -100 : 50; self.sizeSlider.maximumValue=self.offset ? 100 : 150;
    CFPreferencesAppSynchronize(CFSTR("com.chou.gmaphud"));
    id saved=CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)self.sizeKey,CFSTR("com.chou.gmaphud")));
    self.sizeSlider.value=self.offset ? GVMOffsetPercent(saved) : GVMSizePercent(saved);
    self.atNeutral=self.sizeSlider.value==(self.offset ? 0 : 100);
    self.sizeSlider.accessibilityLabel=self.sizeTitle;
    self.sizeSlider.accessibilityHint=self.offset ? @"Mốc giữa là 0 phần trăm" : @"Mốc giữa là 100 phần trăm";
    [self.sizeSlider addTarget:self action:@selector(sizeChanged:) forControlEvents:UIControlEventValueChanged];
    for (UIView *view in @[self.sizeLabel,self.sizeSlider,self.valueLabel]) {
        view.translatesAutoresizingMaskIntoConstraints=NO; [self.contentView addSubview:view];
    }
    if (self.offset) {
        self.sizeLabel.hidden=YES;
        UILabel *low=[UILabel new], *high=[UILabel new];
        BOOL horizontal=[self.sizeKey isEqualToString:@"phoneXPercent"];
        low.text=horizontal ? @"Trái" : @"Lên";
        high.text=horizontal ? @"Phải" : @"Xuống";
        for (UILabel *label in @[low,high]) {
            label.font=[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
            label.textColor=UIColor.secondaryLabelColor;
            label.translatesAutoresizingMaskIntoConstraints=NO;
            [label setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
            [label setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
            [self.contentView addSubview:label];
        }
        self.valueLabel.textAlignment=NSTextAlignmentCenter;
        [NSLayoutConstraint activateConstraints:@[
            [low.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [low.centerYAnchor constraintEqualToAnchor:self.sizeSlider.centerYAnchor],
            [self.sizeSlider.leadingAnchor constraintEqualToAnchor:low.trailingAnchor constant:12],
            [self.sizeSlider.trailingAnchor constraintEqualToAnchor:high.leadingAnchor constant:-12],
            [high.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [high.centerYAnchor constraintEqualToAnchor:self.sizeSlider.centerYAnchor],
            [self.sizeSlider.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
            [self.sizeSlider.heightAnchor constraintEqualToConstant:44],
            [self.valueLabel.topAnchor constraintEqualToAnchor:self.sizeSlider.bottomAnchor],
            [self.valueLabel.centerXAnchor constraintEqualToAnchor:self.sizeSlider.centerXAnchor],
            [self.valueLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-8]
        ]];
    } else {
        self.valueLabel.textAlignment=NSTextAlignmentCenter;
        [NSLayoutConstraint activateConstraints:@[
            [self.sizeLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
            [self.sizeLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [self.sizeLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [self.sizeSlider.topAnchor constraintEqualToAnchor:self.sizeLabel.bottomAnchor constant:4],
            [self.sizeSlider.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [self.sizeSlider.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [self.sizeSlider.heightAnchor constraintEqualToConstant:44],
            [self.valueLabel.topAnchor constraintEqualToAnchor:self.sizeSlider.bottomAnchor],
            [self.valueLabel.centerXAnchor constraintEqualToAnchor:self.sizeSlider.centerXAnchor],
            [self.valueLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-8]
        ]];
    }
    [self updateSizeLabel];
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    // Preferences may reapply its native labels after the cell initializer.
    self.textLabel.hidden=YES;
    self.detailTextLabel.hidden=YES;
}
- (void)updateSizeLabel {
    NSInteger value=self.offset ? GVMOffsetPercent(@(self.sizeSlider.value)) : (NSInteger)GVMSizePercent(@(self.sizeSlider.value));
    NSString *unit=@"%";
    self.valueLabel.text=[NSString stringWithFormat:@"%ld%@",(long)value,unit];
    self.sizeSlider.accessibilityValue=[NSString stringWithFormat:@"%ld%@",(long)value,unit];
}
- (void)sizeChanged:(UISlider *)slider {
    if (![@[@"fullScale",@"dashboardScale",@"phoneScale",@"phoneXPercent",@"phoneYPercent"] containsObject:self.sizeKey]) return;
    float neutral=self.offset ? 0 : 100;
    BOOL nearNeutral=fabsf(slider.value-neutral)<=2;
    if (nearNeutral) slider.value=neutral;
    if (nearNeutral && !self.atNeutral && slider.tracking) [self.feedback selectionChanged];
    self.atNeutral=nearNeutral;
    NSNumber *value=self.offset ? @(GVMOffsetPercent(@(slider.value))) : @(GVMSizePercent(@(slider.value)));
    CFPreferencesSetAppValue((__bridge CFStringRef)self.sizeKey,(__bridge CFPropertyListRef)value,CFSTR("com.chou.gmaphud"));
    if (CFPreferencesAppSynchronize(CFSTR("com.chou.gmaphud"))) {
        GVMPublishSavedSizes(); notify_post(GVMSizeChangedName);
    }
    [self updateSizeLabel];
}
@end

@interface GVMOptionPicker : UIView
@property(nonatomic, strong) UISegmentedControl *control;
- (instancetype)initWithTitle:(NSString *)title items:(NSArray<NSString *> *)items;
@end
@implementation GVMOptionPicker
- (instancetype)initWithTitle:(NSString *)title items:(NSArray<NSString *> *)items {
    self=[super initWithFrame:CGRectZero];
    if (!self) return nil;
    self.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;
    self.layer.cornerRadius=12;
    UILabel *label=[UILabel new];
    label.text=title;
    label.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    label.numberOfLines=0;
    label.adjustsFontForContentSizeCategory=YES;
    label.translatesAutoresizingMaskIntoConstraints=NO;
    [self addSubview:label];
    self.control=[[UISegmentedControl alloc] initWithItems:items];
    self.control.translatesAutoresizingMaskIntoConstraints=NO;
    self.control.accessibilityLabel=title;
    [self addSubview:self.control];
    [NSLayoutConstraint activateConstraints:@[
        [label.topAnchor constraintEqualToAnchor:self.topAnchor constant:12],
        [label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [self.control.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:10],
        [self.control.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [self.control.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [self.control.heightAnchor constraintGreaterThanOrEqualToConstant:32],
        [self.control.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12]
    ]];
    return self;
}
@end

@interface GVMPreferencesController : PSListController
@property(nonatomic, strong) NSTimer *permissionTimer;
@property(nonatomic, strong) PSSpecifier *wakeSpecifier;
@property(nonatomic) BOOL wakeAllowed;
@end
static BOOL GVMWakeAllowed(void) {
    int token=-1; uint64_t state=0;
    if (notify_register_check(GVM_BACKGROUND_PERMISSION,&token)!=NOTIFY_STATUS_OK) return NO;
    BOOL read=notify_get_state(token,&state)==NOTIFY_STATUS_OK;
    notify_cancel(token);
    return read && GVMBackgroundPermissionAllowed(NSProcessInfo.processInfo.systemUptime,state);
}
static void GVMDisableWake(void) {
    CFStringRef domain=CFSTR("com.chou.gmaphud");
    CFPreferencesSetAppValue(CFSTR("autoWake"),kCFBooleanFalse,domain);
    CFPreferencesAppSynchronize(domain);
}
@interface GVMSizeController : GVMPreferencesController
@end
@interface GVMPhonePositionController : GVMPreferencesController
@end
@interface GVMPositionController : GVMPreferencesController
@property(nonatomic, strong) GVMOptionPicker *positionPicker;
@property(nonatomic, strong) UIImageView *preview;
@end
typedef NS_ENUM(NSInteger, GVMPositionOption) {
    GVMPositionTopLeft, GVMPositionTopRight, GVMPositionBottomLeft,
    GVMPositionBottomRight, GVMPositionLeft, GVMPositionRight
};
static NSString *GVMPositionValue(GVMPositionOption option) {
    switch (option) {
        case GVMPositionTopLeft: return @"top-left";
        case GVMPositionTopRight: return @"top-right";
        case GVMPositionBottomLeft: return @"bottom-left";
        case GVMPositionBottomRight: return @"bottom-right";
        case GVMPositionLeft: return @"left";
        case GVMPositionRight: return @"right";
    }
    return @"top-right";
}
static GVMPositionOption GVMPositionFromValue(NSString *value, BOOL compact) {
    GVMPositionOption options[] = {GVMPositionTopLeft, GVMPositionTopRight,
        GVMPositionBottomLeft, GVMPositionBottomRight, GVMPositionLeft, GVMPositionRight};
    for (NSUInteger index=0; index<sizeof(options)/sizeof(options[0]); index++) {
        if ([value isEqualToString:GVMPositionValue(options[index])]) return options[index];
    }
    return compact ? GVMPositionRight : GVMPositionTopRight;
}
@implementation GVMPreferencesController
- (void)refreshWakePermission {
    if (!self.wakeSpecifier) return;
    BOOL allowed=GVMWakeAllowed();
    if (!allowed) GVMDisableWake();
    if (self.wakeAllowed!=allowed) {
        self.wakeAllowed=allowed;
        [self.wakeSpecifier setProperty:@(allowed) forKey:@"enabled"];
        [self reloadSpecifier:self.wakeSpecifier];
    }
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    CGSize screen=UIScreen.mainScreen.bounds.size;
    GVMMigratePhoneOffsets(screen.width,screen.height);
    GVMPublishSavedSizes();
    [self refreshWakePermission];
    [self.permissionTimer invalidate];
    __weak GVMPreferencesController *weakSelf=self;
    self.permissionTimer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(__unused NSTimer *timer) {
        [weakSelf refreshWakePermission];
    }];
}
- (void)viewWillDisappear:(BOOL)animated {
    [self.permissionTimer invalidate]; self.permissionTimer=nil;
    [super viewWillDisappear:animated];
}
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *items = [NSMutableArray new];
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"Nguồn cảnh báo"];
    [group setProperty:@"Hiện hỗ trợ nguồn cảnh báo VietMap Live." forKey:@"footerText"];
    [items addObject:group];
    PSSpecifier *source = [PSSpecifier preferenceSpecifierNamed:@"VietMap Live" target:self
        set:NULL get:NULL detail:Nil cell:PSTitleValueCell edit:Nil];
    [source setProperty:@NO forKey:@"enabled"];
    [items addObject:source];
    group = [PSSpecifier groupSpecifierWithName:@"Chạy nền"];
    [group setProperty:@"Tự mở VietMap Live ở nền khi dùng Google Maps trên CarPlay hoặc iPhone. Cần bật cảnh báo trong VietMap và cấp định vị ‘Khi dùng ứng dụng’ hoặc ‘Luôn luôn’. Công tắc tự tắt khi thiếu quyền." forKey:@"footerText"];
    [items addObject:group];
    PSSpecifier *autoWake = [PSSpecifier preferenceSpecifierNamed:@"Tự đánh thức VietMap Live" target:self
        set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:Nil cell:PSSwitchCell edit:Nil];
    [autoWake setProperty:@"autoWake" forKey:@"key"];
    [autoWake setProperty:@NO forKey:@"default"];
    self.wakeAllowed=GVMWakeAllowed();
    [autoWake setProperty:@(self.wakeAllowed) forKey:@"enabled"];
    self.wakeSpecifier=autoWake;
    if (!self.wakeAllowed) GVMDisableWake();
    [items addObject:autoWake];
    [items addObject:[PSSpecifier preferenceSpecifierNamed:@"Kích cỡ bong bóng" target:self
        set:NULL get:NULL detail:GVMSizeController.class cell:PSLinkCell edit:Nil]];
    group = [PSSpecifier groupSpecifierWithName:@"Vị trí bong bóng"];
    [group setProperty:@"Chọn góc trên bản đồ đầy đủ hoặc cạnh trái/phải trong Dashboard." forKey:@"footerText"];
    [items addObject:group];
    PSSpecifier *full = [PSSpecifier preferenceSpecifierNamed:@"Bản đồ đầy đủ" target:self
        set:NULL get:NULL detail:GVMPositionController.class cell:PSLinkCell edit:Nil];
    [full setProperty:@"fullPosition" forKey:@"key"];
    [full setProperty:@"top-right" forKey:@"default"];
    [items addObject:full];
    PSSpecifier *dashboard = [PSSpecifier preferenceSpecifierNamed:@"Dashboard" target:self
        set:NULL get:NULL detail:GVMPositionController.class cell:PSLinkCell edit:Nil];
    [dashboard setProperty:@"dashboardPosition" forKey:@"key"];
    [dashboard setProperty:@"right" forKey:@"default"];
    [items addObject:dashboard];
    [items addObject:[PSSpecifier groupSpecifierWithName:@"iPhone"]];
    [items addObject:[PSSpecifier preferenceSpecifierNamed:@"Google Maps trên iPhone" target:self
        set:NULL get:NULL detail:GVMPhonePositionController.class cell:PSLinkCell edit:Nil]];
    [items addObject:[PSSpecifier groupSpecifierWithName:@"Hỗ trợ"]];
    [items addObject:[PSSpecifier preferenceSpecifierNamed:@"Chẩn đoán / Xuất log" target:self
        set:NULL get:NULL detail:GVMDiagnosticsController.class cell:PSLinkCell edit:Nil]];
    _specifiers = items;
    return _specifiers;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key=[specifier propertyForKey:@"key"];
    if (![key isKindOfClass:NSString.class]) return nil;
    CFStringRef domain=CFSTR("com.chou.gmaphud");
    CFPreferencesAppSynchronize(domain);
    if ([key isEqualToString:@"autoWake"] && !GVMWakeAllowed()) return @NO;
    id value=CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,domain));
    return value ?: [specifier propertyForKey:@"default"];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key=[specifier propertyForKey:@"key"];
    BOOL offsetPreference=[@[@"phoneXPercent",@"phoneYPercent"] containsObject:key];
    BOOL sizePreference=offsetPreference || [@[@"fullScale",@"dashboardScale",@"phoneScale"] containsObject:key];
    if (sizePreference) {
        CFPreferencesSetAppValue((__bridge CFStringRef)key,(__bridge CFNumberRef)(offsetPreference ? @(GVMOffsetPercent(value)) : @(GVMSizePercent(value))),CFSTR("com.chou.gmaphud"));
        if (CFPreferencesAppSynchronize(CFSTR("com.chou.gmaphud"))) {
            GVMPublishSavedSizes(); notify_post(GVMSizeChangedName);
        }
        return;
    }
    if (![key isEqualToString:@"fullPosition"] && ![key isEqualToString:@"dashboardPosition"] && ![key isEqualToString:@"autoWake"]) return;
    if ([key isEqualToString:@"autoWake"] && !GVMWakeAllowed()) {
        GVMDisableWake(); [self refreshWakePermission]; return;
    }
    CFStringRef domain=CFSTR("com.chou.gmaphud");
    CFPreferencesSetAppValue((__bridge CFStringRef)key,(__bridge CFPropertyListRef)value,domain);
    if (!CFPreferencesAppSynchronize(domain)) return;
    if ([key isEqualToString:@"autoWake"]) return;
    NSString *full=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("fullPosition"),domain));
    NSString *dashboard=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("dashboardPosition"),domain));
    int token=-1;
    if (notify_register_check(GVMPlacementStateName,&token)==NOTIFY_STATUS_OK) {
        notify_set_state(token,GVMEncodePlacement(full,dashboard));
        notify_post(GVMPlacementStateName);
        notify_cancel(token);
    }
}
@end

@implementation GVMPositionController
- (NSArray *)specifiers {
    if (!_specifiers) _specifiers=[NSMutableArray new];
    return _specifiers;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    BOOL dashboard=[[self.specifier propertyForKey:@"key"] isEqualToString:@"dashboardPosition"];
    self.title=self.specifier.name;
    UIScrollView *scroll=[[UIScrollView alloc] initWithFrame:self.view.bounds];
    scroll.translatesAutoresizingMaskIntoConstraints=NO;
    scroll.backgroundColor=UIColor.systemGroupedBackgroundColor;
    scroll.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;
    [self.view addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
    ]];
    UIStackView *content=[[UIStackView alloc] init];
    content.axis=UILayoutConstraintAxisVertical;
    content.spacing=12;
    content.alignment=UIStackViewAlignmentFill;
    content.translatesAutoresizingMaskIntoConstraints=NO;
    [scroll addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:24],
        [content.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor constant:16],
        [content.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor constant:-16],
        [content.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24]
    ]];
    UILabel *previewTitle=[[UILabel alloc] init];
    previewTitle.text=dashboard ? @"Trong ô bản đồ Dashboard" : @"Trên bản đồ đầy đủ";
    previewTitle.font=[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    previewTitle.adjustsFontForContentSizeCategory=YES;
    previewTitle.numberOfLines=0;
    previewTitle.lineBreakMode=NSLineBreakByWordWrapping;
    [previewTitle setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [content addArrangedSubview:previewTitle];
    UILabel *explanation=[[UILabel alloc] init];
    explanation.numberOfLines=0;
    explanation.font=[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    explanation.adjustsFontForContentSizeCategory=YES;
    explanation.textColor=UIColor.secondaryLabelColor;
    explanation.lineBreakMode=NSLineBreakByWordWrapping;
    [explanation setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    explanation.text=dashboard ?
        @"Chọn cạnh trái hoặc phải của ô bản đồ Dashboard." :
        @"Chọn một trong bốn góc của màn hình Google Maps CarPlay.";
    [content addArrangedSubview:explanation];
    UIImageView *preview=[[UIImageView alloc] init];
    preview.contentMode=UIViewContentModeScaleAspectFit;
    preview.backgroundColor=[UIColor colorWithRed:0.08 green:0.13 blue:0.18 alpha:1];
    preview.layer.cornerRadius=12;
    preview.clipsToBounds=YES;
    preview.isAccessibilityElement=YES;
    self.preview=preview;
    [content addArrangedSubview:preview];
    [preview.heightAnchor constraintEqualToAnchor:preview.widthAnchor multiplier:0.60].active=YES;
    UILabel *caption=[[UILabel alloc] init];
    caption.text=@"Ảnh minh họa vị trí bong bóng.";
    caption.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    caption.adjustsFontForContentSizeCategory=YES;
    caption.textColor=UIColor.tertiaryLabelColor;
    caption.numberOfLines=0;
    caption.lineBreakMode=NSLineBreakByWordWrapping;
    [caption setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [content addArrangedSubview:caption];
    UIView *spacer=[[UIView alloc] init];
    [spacer.heightAnchor constraintEqualToConstant:8].active=YES;
    [content addArrangedSubview:spacer];
    NSArray *titles=dashboard ? @[@"Bên trái",@"Bên phải"] : @[@"Trên trái",@"Trên phải",@"Dưới trái",@"Dưới phải"];
    self.positionPicker=[[GVMOptionPicker alloc] initWithTitle:@"Vị trí" items:titles];
    [self.positionPicker.control addTarget:self action:@selector(positionChanged:) forControlEvents:UIControlEventValueChanged];
    [content addArrangedSubview:self.positionPicker];
    [self refreshPositionSelection];
}
- (void)positionChanged:(UISegmentedControl *)control {
    BOOL dashboard=[[self.specifier propertyForKey:@"key"] isEqualToString:@"dashboardPosition"];
    NSInteger index=control.selectedSegmentIndex;
    if (index<0 || index>=(dashboard ? 2 : 4)) return;
    GVMPositionOption option=dashboard ? (index==0 ? GVMPositionLeft : GVMPositionRight) : (GVMPositionOption)index;
    [self setPreferenceValue:GVMPositionValue(option) specifier:self.specifier];
    [self refreshPositionSelection];
}
- (void)refreshPositionSelection {
    BOOL dashboard=[[self.specifier propertyForKey:@"key"] isEqualToString:@"dashboardPosition"];
    GVMPositionOption selected=GVMPositionFromValue([self readPreferenceValue:self.specifier],dashboard);
    self.positionPicker.control.selectedSegmentIndex=dashboard ? (selected==GVMPositionLeft ? 0 : 1) : selected;
    NSString *imageName=[NSString stringWithFormat:@"%@-%@",dashboard ? @"dashboard" : @"full-map",GVMPositionValue(selected)];
    UIImage *image=[UIImage imageNamed:imageName inBundle:[NSBundle bundleForClass:self.class] compatibleWithTraitCollection:nil];
    if (image) self.preview.image=image;
    self.preview.accessibilityLabel=dashboard ? @"Ảnh chụp Google Maps trên CarPlay Dashboard" : @"Ảnh chụp Google Maps trên CarPlay toàn màn hình";
}

@end

@implementation GVMSizeController
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    self.title=@"Kích cỡ bong bóng";
    NSMutableArray *items=[NSMutableArray new];
    PSSpecifier *group=[PSSpecifier groupSpecifierWithName:@""];
    [group setProperty:@"Chỉnh kích cỡ riêng cho từng chế độ. 100% là mặc định." forKey:@"footerText"];
    [items addObject:group];
    NSArray *sizeKeys=@[@"fullScale",@"dashboardScale"];
    NSArray *sizeTitles=@[@"Bản đồ đầy đủ",@"Dashboard"];
    for (NSUInteger i=0;i<sizeKeys.count;i++) {
        PSSpecifier *slider=[PSSpecifier preferenceSpecifierNamed:sizeTitles[i] target:self
            set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:Nil cell:PSStaticTextCell edit:Nil];
        [slider setProperty:GVMSizeSliderCell.class forKey:@"cellClass"];
        [slider setProperty:@112 forKey:@"height"];
        [slider setProperty:sizeKeys[i] forKey:@"key"];
        [slider setProperty:@100 forKey:@"default"];
        [slider setProperty:@50 forKey:@"min"];
        [slider setProperty:@150 forKey:@"max"];
        [slider setProperty:@YES forKey:@"showValue"];
        [items addObject:slider];
    }
    _specifiers=items; return _specifiers;
}
@end

@interface GVMPhoneOptionCell : PSTableCell
@property(nonatomic, copy) NSString *preferenceKey;
@property(nonatomic, copy) NSArray<NSString *> *values;
@property(nonatomic, strong) GVMOptionPicker *picker;
@end
@implementation GVMPhoneOptionCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier specifier:(PSSpecifier *)specifier {
    self=[super initWithStyle:style reuseIdentifier:identifier specifier:specifier];
    if (!self) return nil;
    self.selectionStyle=UITableViewCellSelectionStyleNone;
    self.contentView.userInteractionEnabled=YES;
    self.preferenceKey=[specifier propertyForKey:@"key"];
    BOOL layout=[self.preferenceKey isEqualToString:@"phoneLayout"];
    self.values=layout ? @[@"auto",@"horizontal",@"vertical"] : @[@"top-left",@"top-right",@"bottom-left",@"bottom-right"];
    NSArray *titles=layout ? @[@"Tự động",@"Ngang",@"Dọc"] : @[@"Trên trái",@"Trên phải",@"Dưới trái",@"Dưới phải"];
    self.picker=[[GVMOptionPicker alloc] initWithTitle:specifier.name items:titles];
    self.picker.translatesAutoresizingMaskIntoConstraints=NO;
    [self.contentView addSubview:self.picker];
    [NSLayoutConstraint activateConstraints:@[
        [self.picker.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.picker.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.picker.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
        [self.picker.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor]
    ]];
    CFPreferencesAppSynchronize(CFSTR("com.chou.gmaphud"));
    id saved=CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)self.preferenceKey,CFSTR("com.chou.gmaphud")));
    NSUInteger selected=[self.values indexOfObject:saved ?: @""];
    self.picker.control.selectedSegmentIndex=selected==NSNotFound ? (layout ? 0 : 1) : selected;
    [self.picker.control addTarget:self action:@selector(selectionChanged:) forControlEvents:UIControlEventValueChanged];
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.textLabel.hidden=YES;
    self.detailTextLabel.hidden=YES;
}
- (void)selectionChanged:(UISegmentedControl *)control {
    NSInteger index=control.selectedSegmentIndex;
    if (index<0 || (NSUInteger)index>=self.values.count) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)self.preferenceKey,(__bridge CFStringRef)self.values[index],CFSTR("com.chou.gmaphud"));
    if (CFPreferencesAppSynchronize(CFSTR("com.chou.gmaphud"))) {
        GVMPublishSavedSizes(); notify_post(GVMSizeChangedName);
    }
}
@end

@implementation GVMPhonePositionController
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    self.title=@"Google Maps trên iPhone";
    NSMutableArray *items=[NSMutableArray new];
    PSSpecifier *group=[PSSpecifier groupSpecifierWithName:@"Hiển thị"];
    [group setProperty:@"Chọn góc và bố cục bong bóng. Dùng thanh trượt bên dưới để dịch trái/phải, lên/xuống; 0% giữ vị trí theo góc đã chọn." forKey:@"footerText"];
    [items addObject:group];
    for (NSString *key in @[@"phonePosition",@"phoneLayout"]) {
        PSSpecifier *position=[PSSpecifier preferenceSpecifierNamed:[key isEqual:@"phoneLayout"] ? @"Bố cục" : @"Vị trí" target:self set:NULL get:NULL detail:Nil cell:PSStaticTextCell edit:Nil];
        [position setProperty:key forKey:@"key"];
        [position setProperty:GVMPhoneOptionCell.class forKey:@"cellClass"];
        [position setProperty:@YES forKey:@"enabled"];
        [position setProperty:@100 forKey:@"height"];
        [items addObject:position];
    }
    PSSpecifier *sizeGroup=[PSSpecifier groupSpecifierWithName:@"Kích cỡ"];
    [sizeGroup setProperty:@"100% là kích cỡ mặc định. Bố cục Tự động đổi theo chiều xoay máy." forKey:@"footerText"];
    [items addObject:sizeGroup];
    PSSpecifier *size=[PSSpecifier preferenceSpecifierNamed:@"Kích cỡ bong bóng" target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:Nil cell:PSStaticTextCell edit:Nil];
    [size setProperty:@"phoneScale" forKey:@"key"];
    [size setProperty:@100 forKey:@"default"];
    [size setProperty:@YES forKey:@"enabled"];
    [size setProperty:GVMSizeSliderCell.class forKey:@"cellClass"];
    [size setProperty:@112 forKey:@"height"];
    [items addObject:size];
    [items addObject:[PSSpecifier groupSpecifierWithName:@"Tinh chỉnh vị trí"]];
    for (NSString *key in @[@"phoneXPercent",@"phoneYPercent"]) {
        PSSpecifier *item=[PSSpecifier preferenceSpecifierNamed:[key isEqual:@"phoneXPercent"] ? @"Trục X (trái / phải)" : @"Trục Y (lên / xuống)" target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:Nil cell:PSStaticTextCell edit:Nil];
        [item setProperty:@YES forKey:@"enabled"];
        [item setProperty:@0 forKey:@"default"];
        [item setProperty:key forKey:@"key"];
        [item setProperty:GVMSizeSliderCell.class forKey:@"cellClass"];
        [item setProperty:@84 forKey:@"height"];
        [items addObject:item];
    }
    _specifiers=items; return _specifiers;
}
@end
