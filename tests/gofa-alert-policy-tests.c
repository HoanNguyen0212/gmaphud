#include "../tweak/gofa-alert-policy.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    bool passed=false;
    double approach[]={293,149,34,10};
    for (unsigned i=0;i<sizeof(approach)/sizeof(approach[0]);i++) {
        passed=GVMGofaPointPassed(passed,approach[i]); assert(!passed);
    }
    passed=GVMGofaPointPassed(passed,4); assert(passed);
    assert(GVMGofaPointPassed(passed,14));
    assert(GVMGofaPointPassed(passed,27));
    assert(!GVMGofaPointPassed(false,293)); // A new native membership can approach again.
    assert(GVMGofaPointPassed(false,5));
    assert(!GVMGofaPointPassed(false,NAN));
    assert(!GVMGofaPointPassed(false,-1));
    // The latest native board stays current only while the latest GPS remains near its anchor.
    assert(GVMGofaBoardNear(0));
    assert(GVMGofaBoardNear(GVM_GOFA_BOARD_RADIUS));
    assert(!GVMGofaBoardNear(GVM_GOFA_BOARD_RADIUS+1));
    assert(!GVMGofaBoardNear(NAN));
    assert(!GVMGofaBoardNear(-1));
    assert(!GVMGofaBoardNear(INFINITY));
    puts("GOFA passed-point and board policy passed");
}
