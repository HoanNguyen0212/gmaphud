#import "diagnostics-controller.h"
#import <UIKit/UIKit.h>
#import "diagnostics.h"
@interface GVMDiagnosticsController ()
@property(nonatomic,strong) UITextView *reportView;
@property(nonatomic,strong) UISwitch *includeCrashes;
@property(nonatomic,copy) NSArray<NSURL *> *crashFiles;
@property(nonatomic,copy) NSArray<UIButton *> *reportButtons;
@property(nonatomic) BOOL refreshing;
@end
@implementation GVMDiagnosticsController
- (NSArray *)specifiers { if (!_specifiers) _specifiers=[NSMutableArray new]; return _specifiers; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"Chẩn đoán";
    UIView *panel=[UIView new]; panel.translatesAutoresizingMaskIntoConstraints=NO;
    panel.backgroundColor=UIColor.systemGroupedBackgroundColor;
    [self.view addSubview:panel];
    [NSLayoutConstraint activateConstraints:@[
        [panel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [panel.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [panel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [panel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]]];
    UIStackView *stack=[UIStackView new]; stack.axis=UILayoutConstraintAxisVertical; stack.spacing=8;
    stack.translatesAutoresizingMaskIntoConstraints=NO; [panel addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:panel.topAnchor constant:12],
        [stack.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-12],
        [stack.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-16]]];
    UILabel *help=[UILabel new]; help.numberOfLines=0;
    help.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    help.adjustsFontForContentSizeCategory=YES;
    help.text=@"Làm mới báo cáo sau khi gặp lỗi. Sao chép hoặc xuất để gửi hỗ trợ; không tự gửi dữ liệu.";
    [stack addArrangedSubview:help];
    UIStackView *crashRow=[UIStackView new]; crashRow.axis=UILayoutConstraintAxisHorizontal; crashRow.spacing=12; crashRow.alignment=UIStackViewAlignmentCenter;
    UILabel *crashLabel=[UILabel new]; crashLabel.numberOfLines=0;
    crashLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    crashLabel.adjustsFontForContentSizeCategory=YES;
    [crashLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    crashLabel.text=@"Đính kèm crash liên quan khi xuất. Crash có thể chứa thông tin thiết bị/app; kiểm tra trước khi gửi.";
    self.includeCrashes=[UISwitch new]; self.includeCrashes.on=YES;
    self.includeCrashes.accessibilityLabel=@"Đính kèm crash liên quan";
    [crashRow addArrangedSubview:crashLabel]; [crashRow addArrangedSubview:self.includeCrashes];
    [stack addArrangedSubview:crashRow];
    NSArray *titles=@[@"Làm mới",@"Sao chép báo cáo",@"Xuất file…"];
    SEL actions[]={@selector(refreshReport),@selector(copyReport),@selector(exportReport:)};
    NSMutableArray *buttons=[NSMutableArray new];
    for (NSUInteger i=0;i<titles.count;i++) {
        UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:titles[i] forState:UIControlStateNormal];
        button.titleLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        button.titleLabel.adjustsFontForContentSizeCategory=YES;
        if (@available(iOS 15.0,*)) {
            UIButtonConfiguration *configuration=[UIButtonConfiguration grayButtonConfiguration];
            configuration.title=titles[i]; configuration.cornerStyle=UIButtonConfigurationCornerStyleMedium;
            configuration.contentInsets=NSDirectionalEdgeInsetsMake(12,16,12,16);
            button.configuration=configuration;
        }
        [button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active=YES;
        [button addTarget:self action:actions[i] forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:button]; [buttons addObject:button];
    }
    self.reportButtons=buttons;
    self.reportView=[UITextView new]; self.reportView.editable=NO;
    self.reportView.font=[[UIFontMetrics metricsForTextStyle:UIFontTextStyleFootnote] scaledFontForFont:[UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular]];
    self.reportView.adjustsFontForContentSizeCategory=YES;
    self.reportView.accessibilityLabel=@"Báo cáo chẩn đoán";
    self.reportView.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;
    self.reportView.layer.cornerRadius=10; [stack addArrangedSubview:self.reportView];
    [self refreshReport];
}
- (void)refreshReport {
    if (self.refreshing) return;
    self.refreshing=YES;
    for (UIButton *button in self.reportButtons) button.enabled=NO;
    self.reportView.text=@"Đang lấy báo cáo và kiểm tra crash…";
    __weak GVMDiagnosticsController *weakSelf=self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        NSString *status=nil;
        NSArray *crashes=GVMDiagnosticsCrashFiles(&status);
        NSMutableString *report=[GVMDiagnosticsReport() mutableCopy];
        [report appendFormat:@"\n=== Crash đính kèm khi xuất ===\n%@\n",status];
        for (NSURL *file in crashes) [report appendFormat:@"- %@\n",file.lastPathComponent];
        dispatch_async(dispatch_get_main_queue(), ^{
            GVMDiagnosticsController *controller=weakSelf;
            controller.crashFiles=crashes; controller.reportView.text=report;
            controller.includeCrashes.enabled=crashes.count>0;
            controller.refreshing=NO;
            for (UIButton *button in controller.reportButtons) button.enabled=YES;
        });
    });
}
- (void)message:(NSString *)text {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"GMapHUD" message:text preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)copyReport {
    UIPasteboard.generalPasteboard.string=self.reportView.text;
    [self message:@"Đã sao chép báo cáo đang hiển thị."];
}
- (void)exportReport:(UIButton *)sender {
    NSURL *directory=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[@"GMapHUD-" stringByAppendingString:NSUUID.UUID.UUIDString]] isDirectory:YES];
    NSFileManager *manager=NSFileManager.defaultManager;
    NSError *error=nil;
    if (![manager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
        [self message:@"Không thể tạo thư mục xuất. Bạn có thể sao chép báo cáo."]; return;
    }
    NSMutableArray *files=[NSMutableArray new];
    NSMutableString *report=[self.reportView.text mutableCopy];
    if (self.includeCrashes.on && self.includeCrashes.enabled) {
        for (NSURL *source in self.crashFiles) {
            NSDictionary *attributes=[manager attributesOfItemAtPath:source.path error:nil];
            if ([attributes[NSFileSize] unsignedLongLongValue]>2*1024*1024 || ![attributes[NSFileType] isEqual:NSFileTypeRegular]) continue;
            NSURL *destination=[directory URLByAppendingPathComponent:source.lastPathComponent];
            if ([manager copyItemAtURL:source toURL:destination error:nil]) [files addObject:destination];
            else [report appendFormat:@"Không sao chép được crash: %@\n",source.lastPathComponent];
        }
    }
    [report appendFormat:@"\nSố crash thực tế đính kèm: %lu\n",(unsigned long)files.count];
    NSURL *file=[directory URLByAppendingPathComponent:@"GMapHUD-diagnostics.txt"];
    if (![report writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        [manager removeItemAtURL:directory error:nil];
        [self message:@"Không thể tạo file báo cáo. Bạn có thể dùng Sao chép báo cáo."]; return;
    }
    [files insertObject:file atIndex:0];
    UIActivityViewController *share=[[UIActivityViewController alloc] initWithActivityItems:files applicationActivities:nil];
    share.popoverPresentationController.sourceView=sender;
    share.popoverPresentationController.sourceRect=sender.bounds;
    share.completionWithItemsHandler=^(__unused UIActivityType type,__unused BOOL completed,__unused NSArray *items,__unused NSError *failure) {
        [[NSFileManager defaultManager] removeItemAtURL:directory error:nil];
    };
    [self presentViewController:share animated:YES completion:nil];
}
@end
