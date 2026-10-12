#include "../tweak/background-policy.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    assert(!GVMBackgroundActive(10,0));
    assert(GVMBackgroundActive(10,10000));
    assert(GVMBackgroundActive(21.999,10000));
    assert(!GVMBackgroundActive(22,10000));
    assert(!GVMBackgroundActive(9,10000));
    assert(!GVMBackgroundActive(NAN,10000));
    assert(GVMBackgroundMayLaunch(15,15,1));
    assert(!GVMBackgroundMayLaunch(14,15,1));
    assert(!GVMBackgroundMayLaunch(100,15,3));
    assert(!GVMBackgroundMayLaunch(NAN,15,0));
    assert(GVMBackgroundRetryDelay(2)>GVMBackgroundRetryDelay(1));
    assert(!GVMBackgroundNewClient(0,17));
    assert(!GVMBackgroundNewClient(17,17));
    assert(!GVMBackgroundNewClient(17,0));
    assert(GVMBackgroundNewClient(17,18));
    assert(GVMBackgroundPermissionAllowed(100,GVMBackgroundPermissionState(100,true)));
    assert(!GVMBackgroundPermissionAllowed(106,GVMBackgroundPermissionState(100,true)));
    assert(!GVMBackgroundPermissionAllowed(99,GVMBackgroundPermissionState(100,true)));
    assert(!GVMBackgroundPermissionAllowed(100,GVMBackgroundPermissionState(100,false)));
    assert(!GVMBackgroundPermissionAllowed(100,0));
    assert(!GVMBackgroundPermissionAllowed(NAN,201));
    assert(GVMBackgroundPermissionState(NAN,true)==0);
    puts("background policy tests passed");
}
