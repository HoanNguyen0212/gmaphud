#import "diagnostics.h"
#include <notify.h>
#include <sys/sysctl.h>
#include <math.h>

static NSString *component;
static NSMutableDictionary<NSString *, NSNumber *> *tokens;
static uint64_t previous[8];
static NSUInteger cursor;
static NSString *Key(NSString *source, NSString *slot) {
    return [NSString stringWithFormat:@"com.chou.gmaphud.debug.v1.%@.%@",source,slot];
}
static BOOL Write(NSString *key,uint64_t state) {
    if (!tokens) tokens=[NSMutableDictionary new];
    NSNumber *saved=tokens[key]; int token=-1;
    if (saved) token=saved.intValue;
    else {
        if (notify_register_check(key.UTF8String,&token)!=NOTIFY_STATUS_OK) return NO;
        tokens[key]=@(token);
    }
    return notify_set_state(token,state)==NOTIFY_STATUS_OK;
}
static uint64_t Read(NSString *key) {
    int token=-1; uint64_t state=0;
    if (notify_register_check(key.UTF8String,&token)!=NOTIFY_STATUS_OK) return 0;
    notify_get_state(token,&state); notify_cancel(token); return state;
}
uint64_t GVMEncodeDiagnostic(NSUInteger event,NSUInteger detail,NSTimeInterval uptime) {
    if (event<1 || event>7 || detail>0xffffff || !isfinite(uptime) || uptime<1 || uptime>=UINT32_MAX) return 0;
    return ((uint64_t)floor(uptime)<<32) | ((uint64_t)detail<<8) | event;
}
NSString *GVMDescribeDiagnostic(uint64_t state,NSTimeInterval now) {
    NSUInteger event=state&255, detail=(state>>8)&0xffffff;
    NSTimeInterval age=now-(state>>32);
    if (!state || event<1 || event>7 || !isfinite(now) || age<0) return @"Chưa có dữ liệu trong phiên này";
    NSString *message;
    switch (event) {
        case GVMDiagnosticLoaded: message=[NSString stringWithFormat:@"Module 0.1.16 đã nạp; app %lu.%lu.%lu",(unsigned long)(detail>>16),(unsigned long)((detail>>8)&255),(unsigned long)(detail&255)]; break;
        case GVMDiagnosticHook: message=detail==1 ? @"Hook sẵn sàng" : detail==2 ? @"Chưa tìm thấy lớp/hàm cần thiết" : detail==3 ? @"Cấu trúc hàm không tương thích" : @"Không đăng ký được kênh dữ liệu"; break;
        case GVMDiagnosticChannel: message=@"Đã bắt gặp kênh overlay VietMap"; break;
        case GVMDiagnosticPayload: message=detail==1 ? @"Nhận gói tốc độ đúng cấu trúc" : @"Gói tốc độ khác cấu trúc hỗ trợ"; break;
        case GVMDiagnosticSamples: message=[NSString stringWithFormat:@"Nguồn: tốc độ %@, giới hạn %@; app %@",detail&1 ? @"còn mới" : @"thiếu/hết hạn",detail&2 ? @"còn mới" : @"thiếu/hết hạn",detail&4 ? @"foreground" : @"background/inactive"]; break;
        case GVMDiagnosticCarPlay: message=[NSString stringWithFormat:@"Đã cập nhật view CarPlay: tốc độ %@, giới hạn %@, chế độ %@",detail&1 ? @"có" : @"thiếu",detail&2 ? @"có" : @"thiếu",detail&4 ? @"mẫu thử" : @"thật"]; break;
        default: message=@"Lỗi cập nhật hoặc truyền dữ liệu"; break;
    }
    return [NSString stringWithFormat:@"%.0f giây trước: %@",age,message];
}
void GVMDiagnosticsRecord(GVMDiagnosticEvent event,NSUInteger detail) {
    @synchronized(NSProcessInfo.processInfo) {
        if (!component || event<1 || event>7) return;
        NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
        uint64_t state=GVMEncodeDiagnostic(event,detail,now);
        if (!state) return;
        // Repeat snapshots at most once per ten seconds; state changes are immediate.
        if ((previous[event]&UINT32_MAX)==(state&UINT32_MAX) && now-(previous[event]>>32)<10) return;
        previous[event]=state;
        Write(Key(component,[NSString stringWithFormat:@"event%lu",(unsigned long)event]),state);
        Write(Key(component,[NSString stringWithFormat:@"recent%lu",(unsigned long)(cursor++%16)]),state);
    }
}
void GVMDiagnosticsStart(NSString *source) {
    @synchronized(NSProcessInfo.processInfo) {
        if (component) return;
        component=[source copy];
        for (NSUInteger i=1;i<=7;i++) Write(Key(component,[NSString stringWithFormat:@"event%lu",(unsigned long)i]),0);
        for (NSUInteger i=0;i<16;i++) Write(Key(component,[NSString stringWithFormat:@"recent%lu",(unsigned long)i]),0);
        NSArray *parts=[[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] componentsSeparatedByString:@"."];
        NSUInteger version=0;
        for (NSUInteger i=0;i<3;i++) version=(version<<8) | (i<parts.count ? MIN(255,MAX(0,[parts[i] integerValue])) : 0);
        GVMDiagnosticsRecord(GVMDiagnosticLoaded,version);
    }
}
NSString *GVMDiagnosticsReport(void) {
    char model[128]={0}; size_t size=sizeof(model);
    sysctlbyname("hw.machine",model,&size,NULL,0);
    NSMutableString *report=[NSMutableString stringWithFormat:@"GMapHUD 0.1.16 — Chẩn đoán\nNgày xuất: %@\nThiết bị: %s\nOS: %@\nRootless /var/jb: %@\n\nKhông chứa tọa độ, tuyến đường, tài khoản hoặc số sê-ri.\nĐây là các mốc chẩn đoán gần nhất, không phải toàn bộ log ứng dụng.\nKhông có dữ liệu không đồng nghĩa tweak bị tắt. Mở lại cả hai app sau khi cài.\n",NSDate.date,model,NSProcessInfo.processInfo.operatingSystemVersionString,[[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"] ? @"có" : @"không"];
    NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
    for (NSString *source in @[@"vietmap",@"googlemaps"]) {
        [report appendFormat:@"\n=== %@ ===\n",source];
        NSArray *labels=@[@"Module",@"Hook",@"Kênh overlay",@"Gói tốc độ",@"Dữ liệu nguồn",@"View CarPlay",@"Lỗi"];
        for (NSUInteger i=1;i<=7;i++) {
            if (([source isEqual:@"googlemaps"] && i>=3 && i<=5) || ([source isEqual:@"vietmap"] && i==6)) continue;
            [report appendFormat:@"%@: %@\n",labels[i-1],GVMDescribeDiagnostic(Read(Key(source,[NSString stringWithFormat:@"event%lu",(unsigned long)i])),now)];
        }
        NSMutableArray *recent=[NSMutableArray new];
        for (NSUInteger i=0;i<16;i++) {
            uint64_t value=Read(Key(source,[NSString stringWithFormat:@"recent%lu",(unsigned long)i]));
            if (value && (value>>32)<=now) [recent addObject:@(value)];
        }
        [recent sortUsingSelector:@selector(compare:)];
        [report appendString:@"Các mốc gần nhất:\n"];
        for (NSNumber *value in recent) [report appendFormat:@"- %@\n",GVMDescribeDiagnostic(value.unsignedLongLongValue,now)];
    }
    [report appendString:@"\nThông tin bổ sung: phiên bản jailbreak, tweak chia màn hình và các bước gây lỗi (người gửi tự bổ sung).\n"];
    return report;
}
