#include "../tweak/background-policy.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    assert(!GVMBackgroundDisconnectDue(100,0));
    assert(!GVMBackgroundDisconnectDue(119.999,100));
    assert(GVMBackgroundDisconnectDue(120,100));
    assert(GVMBackgroundDisconnectDue(125,100));
    assert(!GVMBackgroundDisconnectDue(99,100));
    assert(!GVMBackgroundDisconnectDue(NAN,100));
    assert(!GVMBackgroundDisconnectDue(120,NAN));
    assert(GVMBackgroundSourceLocationActive(true,4,true,10,10000,0));
    assert(GVMBackgroundSourceLocationActive(true,3,true,10,0,10000));
    assert(!GVMBackgroundSourceLocationActive(false,4,true,10,10000,0));
    assert(!GVMBackgroundSourceLocationActive(true,2,true,10,10000,0));
    assert(!GVMBackgroundSourceLocationActive(true,4,false,10,10000,0));
    assert(!GVMBackgroundSourceLocationActive(true,4,true,22,10000,0));
    assert(!GVMBackgroundSourceLocationActive(true,4,true,9,10000,0));
    assert(!GVMBackgroundSourceLocationActive(true,4,true,10,0,0));

    assert(GVMBackgroundLocationAuthorized(3));
    assert(GVMBackgroundLocationAuthorized(4));
    for (int status=-1;status<=2;status++) assert(!GVMBackgroundLocationAuthorized(status));
    assert(!GVMBackgroundLocationAuthorized(5));
    assert(GVMBackgroundNeedsUsageContext(4,true));
    assert(!GVMBackgroundNeedsUsageContext(4,false));
    for (int status=-1;status<=5;status++) {
        if (status!=4) assert(!GVMBackgroundNeedsUsageContext(status,true));
    }
    assert(!GVMBackgroundActive(10,0));
    assert(GVMBackgroundActive(10,10000));
    assert(GVMBackgroundActive(21.999,10000));
    assert(!GVMBackgroundActive(22,10000));
    assert(!GVMBackgroundActive(9,10000));
    assert(!GVMBackgroundActive(NAN,10000));
    assert(GVMBackgroundAnyHostActive(10,10000,0));
    assert(GVMBackgroundAnyHostActive(10,0,10000));
    assert(GVMBackgroundAnyHostActive(22,10000,21000));
    assert(GVMBackgroundAnyHostActive(22,21000,10000));
    assert(!GVMBackgroundAnyHostActive(22,10000,10000));
    assert(!GVMBackgroundAnyHostActive(10,0,0));
    assert(!GVMBackgroundAnyHostActive(10,11000,0));
    assert(!GVMBackgroundAnyHostActive(NAN,10000,10000));
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
