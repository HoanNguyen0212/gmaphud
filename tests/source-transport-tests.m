#import "source-transport.h"
#import <CoreFoundation/CoreFoundation.h>
#include <notify.h>
#include <sys/wait.h>
#include <unistd.h>
#include <spawn.h>
extern char **environ;

#ifndef GVM_OUTPUT_NAMESPACE
#error Transport tests require a private notification and preferences namespace.
#endif
static void Require(BOOL condition,NSString *name) {
    if (!condition) { fprintf(stderr,"FAIL: %s\n",name.UTF8String); exit(1); }
}
static NSDictionary *Output(NSUInteger sourceID,double now) {
    return GVMSourceOutput(sourceID,@{@"speed":@{@"value":@42,@"receivedAt":@(now)},@"speedLimit":@{@"value":@50,@"receivedAt":@(now)}},@[],now);
}
int main(int argc,char **argv) { @autoreleasepool {
    double now=NSProcessInfo.processInfo.systemUptime;
    if (argc==2) {
        NSDictionary *output=GVMReadSourceOutput(now);
        Require([output[@"sourceID"] isEqual:@1] && [output[@"speed"][@"value"] isEqual:@42] && [output[@"speedLimit"][@"value"] isEqual:@50],@"independent consumer reads the complete selected frame");
        return 0;
    }
    Require(GVMSelectedSourceID()==1 && !GVMReadSourceOutput(now),@"initial source is VietMap, no invented data");
    GVMRestoreOutputSelection();
    Require(GVMPublishSourceOutput(Output(1,now),now,NO),@"selected source publishes");
    Require([GVMReadSourceOutput(now)[@"speedLimit"][@"value"] isEqual:@50],@"Darwin frame read");
    Require(!GVMSelectOutputSource(0) && !GVMSelectOutputSource(8),@"invalid selection refused");
    Require(!GVMPublishSourceOutput(Output(2,now),now,NO),@"unselected source cannot publish");
    Require(GVMSelectOutputSource(2) && !GVMReadSourceOutput(now),@"selection does not fall back to VietMap");
    Require(!GVMPublishSourceOutput(Output(1,now),now,NO),@"previous source cannot overwrite selected data");
    Require(GVMPublishSourceOutput(Output(2,now),now,NO) && [GVMReadSourceOutput(now)[@"sourceID"] isEqual:@2],@"isolated second source frame");
    Require(GVMSelectOutputSource(1) && !GVMReadSourceOutput(now),@"return requires a new frame, cannot replay old source");
    Require(GVMPublishSourceOutput(Output(1,now),now,NO),@"same values publish in new epoch");
    Require(!GVMReadSourceOutput(now+5)[@"speed"],@"expiry checked by reader without publisher");
    Require(GVMPublishSourceOutput(Output(1,now),now+5,YES) && !GVMReadSourceOutput(now+5)[@"speedLimit"],@"forced reply cannot revive expired values");
    Require(GVMPublishSourceOutput(GVMSourceOutput(1,nil,@[],now),now,YES) && !GVMReadSourceOutput(now)[@"speed"],@"explicit empty output clears");

    NSString *commit=[@GVM_OUTPUT_NAMESPACE stringByAppendingString:@".output.v1.1.commit"];
    int token=-1; uint64_t header=0;
    Require(notify_register_check(commit.UTF8String,&token)==NOTIFY_STATUS_OK,@"inspect real channel");
    Require(notify_get_state(token,&header)==NOTIFY_STATUS_OK && notify_set_state(token,((((header>>8)+1)|1)<<8)|1)==NOTIFY_STATUS_OK,@"interrupt write");
    Require(!GVMReadSourceOutput(now),@"real incomplete frame unavailable");
    Require(GVMPublishSourceOutput(Output(1,now),now,NO) && GVMReadSourceOutput(now)[@"speed"],@"publisher recovers odd frame");
    // Independent executable has separate globals/tokens, exercising actual IPC.
    pid_t child=0;
    char *arguments[]={argv[0],"--read",NULL};
    Require(posix_spawn(&child,argv[0],NULL,NULL,arguments,environ)==0,@"start independent consumer");
    int status=0; Require(child>0 && waitpid(child,&status,0)==child && WIFEXITED(status) && WEXITSTATUS(status)==0,@"committed state visible across process boundary");

    __block NSUInteger calls=0;
    dispatch_semaphore_t semaphore=dispatch_semaphore_create(0);
    int requestToken=-1;
    Require(notify_register_dispatch(GVMOutputRequestName(1).UTF8String,&requestToken,dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^(__unused int t) { calls++; dispatch_semaphore_signal(semaphore); })==NOTIFY_STATUS_OK,@"source request receiver");
    Require(GVMRequestSelectedSource() && dispatch_semaphore_wait(semaphore,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC))==0 && calls==1,@"selected source receives refresh request");
    Require(GVMSelectOutputSource(2) && GVMRequestSelectedSource(),@"request switches source");
    Require(dispatch_semaphore_wait(semaphore,dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC))!=0,@"unselected source receives no request");
    notify_cancel(requestToken); notify_cancel(token);
    CFPreferencesSetAppValue(CFSTR("sourceID"),NULL,CFSTR(GVM_OUTPUT_NAMESPACE));
    CFPreferencesAppSynchronize(CFSTR(GVM_OUTPUT_NAMESPACE));
    puts("source-transport tests passed");
} return 0; }
