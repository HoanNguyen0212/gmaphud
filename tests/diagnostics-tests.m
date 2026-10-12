#import <Foundation/Foundation.h>
#import "diagnostics.h"
#include <assert.h>
#include <math.h>
int main(void) { @autoreleasepool {
    assert(!GVMEncodeDiagnostic(0,1,100));
    assert(!GVMEncodeDiagnostic(11,1,100));
    assert(!GVMEncodeDiagnostic(1,0x1000000,100));
    assert(!GVMEncodeDiagnostic(1,0,NAN));
    assert(!GVMEncodeDiagnostic(1,0,-1));
    assert(!GVMEncodeDiagnostic(1,0,UINT32_MAX));
    uint64_t sample=GVMEncodeDiagnostic(GVMDiagnosticSamples,7,100);
    assert([GVMDescribeDiagnostic(sample,110) containsString:@"10 giây"]);
    assert([GVMDescribeDiagnostic(sample,110) containsString:@"foreground"]);
    assert([GVMDescribeDiagnostic(sample,99) containsString:@"Chưa có dữ liệu"]);
    assert([GVMDescribeDiagnostic(GVMEncodeDiagnostic(GVMDiagnosticSamples,0,100),110) containsString:@"thiếu/hết hạn"]);
    assert([GVMDescribeDiagnostic(GVMEncodeDiagnostic(GVMDiagnosticLoaded,(26<<16)|(40<<8)|3,100),110) containsString:@"26.40.3"]);
    assert([GVMDescribeDiagnostic(GVMEncodeDiagnostic(GVMDiagnosticCarPlay,4,100),110) containsString:@"mẫu thử"]);
    NSString *report=GVMDiagnosticsReport();
    assert([report containsString:@"vietmap"] && [report containsString:@"googlemaps"]);
    puts("diagnostics encoding and report tests passed");
} return 0; }
