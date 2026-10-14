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
    puts("GOFA passed-point policy passed");
}
