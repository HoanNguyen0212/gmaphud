#import "diagnostics-controller.h"
#import <UIKit/UIKit.h>
#import "diagnostics.h"
@interface GVMDiagnosticsController ()
@property(nonatomic,strong) UITextView *reportView;
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
    UIStackView *stack=[UIStackView new]; stack.axis=UILayoutConstraintAxisVertical; stack.spacing=10;
    stack.translatesAutoresizingMaskIntoConstraints=NO; [panel addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:panel.topAnchor constant:12],
        [stack.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-12],
        [stack.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-16]]];
    UILabel *help=[UILabel new]; help.numberOfLines=0;
    help.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    help.adjustsFontForContentSizeCategory=YES;
    help.text=@"Mở lại VietMap Live và Google Maps sau khi cài. Khi lỗi xuất hiện, bấm Làm mới rồi sao chép hoặc xuất báo cáo để gửi hỗ trợ. Không tự gửi dữ liệu.";
    [stack addArrangedSubview:help];
    NSArray *titles=@[@"Làm mới",@"Sao chép báo cáo",@"Xuất file…"];
    SEL actions[]={@selector(refreshReport),@selector(copyReport),@selector(exportReport:)};
    for (NSUInteger i=0;i<titles.count;i++) {
        UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:titles[i] forState:UIControlStateNormal];
        button.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor; button.layer.cornerRadius=10;
        [button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active=YES;
        [button addTarget:self action:actions[i] forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:button];
    }
    self.reportView=[UITextView new]; self.reportView.editable=NO;
    self.reportView.font=[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.reportView.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;
    self.reportView.layer.cornerRadius=10; [stack addArrangedSubview:self.reportView];
    [self refreshReport];
}
- (void)refreshReport { self.reportView.text=GVMDiagnosticsReport(); }
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
    NSURL *file=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"GMapHUD-diagnostics.txt"]];
    NSError *error=nil;
    if (![self.reportView.text writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        [self message:@"Không thể tạo file báo cáo. Bạn có thể dùng Sao chép báo cáo."]; return;
    }
    UIActivityViewController *share=[[UIActivityViewController alloc] initWithActivityItems:@[file] applicationActivities:nil];
    share.popoverPresentationController.sourceView=sender;
    share.popoverPresentationController.sourceRect=sender.bounds;
    share.completionWithItemsHandler=^(__unused UIActivityType type,__unused BOOL completed,__unused NSArray *items,__unused NSError *failure) {
        [[NSFileManager defaultManager] removeItemAtURL:file error:nil];
    };
    [self presentViewController:share animated:YES completion:nil];
}
@end
