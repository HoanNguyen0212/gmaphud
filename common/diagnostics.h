#import <Foundation/Foundation.h>
typedef NS_ENUM(NSUInteger, GVMDiagnosticEvent) {
    GVMDiagnosticLoaded=1, GVMDiagnosticHook, GVMDiagnosticChannel,
    GVMDiagnosticPayload, GVMDiagnosticSamples, GVMDiagnosticCarPlay, GVMDiagnosticError, GVMDiagnosticRequest, GVMDiagnosticResponse, GVMDiagnosticShape
};
void GVMDiagnosticsStart(NSString *component);
void GVMDiagnosticsRecord(GVMDiagnosticEvent event, NSUInteger detail);
NSString *GVMDiagnosticsReport(void);
uint64_t GVMEncodeDiagnostic(NSUInteger event, NSUInteger detail, NSTimeInterval uptime);
NSString *GVMDescribeDiagnostic(uint64_t state, NSTimeInterval now);
