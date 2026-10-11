#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import "placement-state.h"
#include <notify.h>

@interface GVMPreferencesController : PSListController
@end
@interface GVMPositionController : GVMPreferencesController
@property(nonatomic, strong) UIButton *positionButton;
@property(nonatomic, strong) UILabel *positionValue;
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
static NSString *GVMPositionTitle(GVMPositionOption option) {
    switch (option) {
        case GVMPositionTopLeft: return @"Trên trái";
        case GVMPositionTopRight: return @"Trên phải";
        case GVMPositionBottomLeft: return @"Dưới trái";
        case GVMPositionBottomRight: return @"Dưới phải";
        case GVMPositionLeft: return @"Bên trái";
        case GVMPositionRight: return @"Bên phải";
    }
    return @"Trên phải";
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
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *items = [NSMutableArray new];
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"Nguồn cảnh báo"];
    [group setProperty:@"Hiện chỉ hỗ trợ VietMap Live. Tùy chọn nguồn sẽ mở khi có thêm ứng dụng được hỗ trợ." forKey:@"footerText"];
    [items addObject:group];
    PSSpecifier *source = [PSSpecifier preferenceSpecifierNamed:@"VietMap Live" target:self
        set:NULL get:NULL detail:Nil cell:PSTitleValueCell edit:Nil];
    [source setProperty:@NO forKey:@"enabled"];
    [items addObject:source];
    group = [PSSpecifier groupSpecifierWithName:@"Vị trí bong bóng"];
    [group setProperty:@"Thay đổi áp dụng ngay trên Google Maps CarPlay. Dashboard chọn cạnh trái hoặc phải của phần bản đồ." forKey:@"footerText"];
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
    _specifiers = items;
    return _specifiers;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key=[specifier propertyForKey:@"key"];
    if (![key isKindOfClass:NSString.class]) return nil;
    CFStringRef domain=CFSTR("com.chou.gmaphud");
    CFPreferencesAppSynchronize(domain);
    id value=CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,domain));
    return value ?: [specifier propertyForKey:@"default"];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key=[specifier propertyForKey:@"key"];
    if (![key isEqualToString:@"fullPosition"] && ![key isEqualToString:@"dashboardPosition"]) return;
    CFStringRef domain=CFSTR("com.chou.gmaphud");
    CFPreferencesSetAppValue((__bridge CFStringRef)key,(__bridge CFPropertyListRef)value,domain);
    if (!CFPreferencesAppSynchronize(domain)) return;
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
        @"Bong bóng nằm ở cạnh trái hoặc phải của ô bản đồ, cạnh các tiện ích CarPlay." :
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
    caption.text=@"Ảnh mô tả CarPlay với giới hạn sắp tới và cảnh báo camera.";
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
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
    button.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;
    button.layer.cornerRadius=12;
    button.showsMenuAsPrimaryAction=YES;
    button.accessibilityTraits=UIAccessibilityTraitButton;
    UILabel *rowTitle=[[UILabel alloc] init];
    rowTitle.text=@"Vị trí";
    rowTitle.textColor=UIColor.labelColor;
    rowTitle.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    rowTitle.adjustsFontForContentSizeCategory=YES;
    rowTitle.translatesAutoresizingMaskIntoConstraints=NO;
    [rowTitle setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [button addSubview:rowTitle];
    UILabel *value=[[UILabel alloc] init];
    value.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    value.adjustsFontForContentSizeCategory=YES;
    value.textColor=UIColor.secondaryLabelColor;
    value.textAlignment=NSTextAlignmentRight;
    value.translatesAutoresizingMaskIntoConstraints=NO;
    [value setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    self.positionValue=value;
    [button addSubview:value];
    UIImageView *chevron=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.up.chevron.down"]];
    chevron.tintColor=UIColor.tertiaryLabelColor;
    chevron.translatesAutoresizingMaskIntoConstraints=NO;
    [button addSubview:chevron];
    [NSLayoutConstraint activateConstraints:@[
        [rowTitle.leadingAnchor constraintEqualToAnchor:button.leadingAnchor constant:16],
        [rowTitle.topAnchor constraintGreaterThanOrEqualToAnchor:button.topAnchor constant:12],
        [rowTitle.bottomAnchor constraintLessThanOrEqualToAnchor:button.bottomAnchor constant:-12],
        [rowTitle.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
        [value.leadingAnchor constraintGreaterThanOrEqualToAnchor:rowTitle.trailingAnchor constant:8],
        [value.topAnchor constraintGreaterThanOrEqualToAnchor:button.topAnchor constant:12],
        [value.bottomAnchor constraintLessThanOrEqualToAnchor:button.bottomAnchor constant:-12],
        [value.trailingAnchor constraintEqualToAnchor:chevron.leadingAnchor constant:-8],
        [value.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
        [chevron.trailingAnchor constraintEqualToAnchor:button.trailingAnchor constant:-16],
        [chevron.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
        [chevron.widthAnchor constraintEqualToConstant:12]
    ]];
    self.positionButton=button;
    [content addArrangedSubview:button];
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:52].active=YES;
    [self refreshPositionMenu];
}
- (void)refreshPositionMenu {
    BOOL dashboard=[[self.specifier propertyForKey:@"key"] isEqualToString:@"dashboardPosition"];
    GVMPositionOption options[4]={GVMPositionTopLeft,GVMPositionTopRight,GVMPositionBottomLeft,GVMPositionBottomRight};
    if (dashboard) { options[0]=GVMPositionLeft; options[1]=GVMPositionRight; }
    NSUInteger count=dashboard ? 2 : 4;
    GVMPositionOption selected=GVMPositionFromValue([self readPreferenceValue:self.specifier],dashboard);
    NSMutableArray<UIMenuElement *> *actions=[NSMutableArray new];
    for (NSUInteger index=0; index<count; index++) {
        GVMPositionOption option=options[index];
        NSString *value=GVMPositionValue(option);
        UIAction *action=[UIAction actionWithTitle:GVMPositionTitle(option) image:nil identifier:nil handler:^(__kindof UIAction * __unused chosen) {
            [self setPreferenceValue:value specifier:self.specifier];
            [self refreshPositionMenu];
        }];
        action.state=selected==option ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    self.positionButton.menu=[UIMenu menuWithTitle:@"Vị trí bong bóng" children:actions];
    NSString *title=GVMPositionTitle(selected);
    self.positionValue.text=title;
    NSString *imageName=[NSString stringWithFormat:@"%@-%@",dashboard ? @"dashboard" : @"full-map",GVMPositionValue(selected)];
    UIImage *image=[UIImage imageNamed:imageName inBundle:[NSBundle bundleForClass:self.class] compatibleWithTraitCollection:nil];
    if (image) self.preview.image=image;
    self.positionButton.accessibilityLabel=[NSString stringWithFormat:@"Vị trí bong bóng, %@",title];
    self.preview.accessibilityLabel=dashboard ? @"Ảnh chụp Google Maps trên CarPlay Dashboard" : @"Ảnh chụp Google Maps trên CarPlay toàn màn hình";
}
@end
