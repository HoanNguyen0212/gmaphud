#import <Foundation/Foundation.h>
#import "speed-presentation.h"
#import "placement-state.h"
#include <assert.h>
#include <math.h>
int main(void) {
    @autoreleasepool {
        assert(GVMWarningFor(@44,@50)==GVMWarningNormal);
        assert(GVMWarningFor(@45,@50)==GVMWarningNear);
        assert(GVMWarningFor(@50,@50)==GVMWarningNear);
        assert(GVMWarningFor(@51,@50)==GVMWarningOver);
        assert(GVMWarningFor(@25,@30)==GVMWarningNear);
        assert(GVMWarningFor(@0,@50)==GVMWarningNormal);
        assert(GVMWarningFor(nil,@50)==GVMWarningNormal);
        assert(GVMWarningFor(@60,nil)==GVMWarningNormal);
        assert(GVMWarningFor(@60,@0)==GVMWarningNormal);
        assert(GVMProgressFor(@0,@50)==0);
        assert(GVMProgressFor(@25,@50)==0.5);
        assert(GVMProgressFor(@60,@50)==1);
        assert(GVMProgressFor(nil,@50)==0);
        assert(GVMProgressFor(@60,nil)==0);
        const double screens[][2] = {{320,180}, {400,240}, {640,240}, {800,480}, {240,160}};
        for (NSUInteger i = 0; i < sizeof(screens) / sizeof(screens[0]); i++) {
            double screenWidth = screens[i][0], screenHeight = screens[i][1];
            for (int dashboard = 0; dashboard < 2; dashboard++) {
                for (int camera = 0; camera < 3; camera++) {
                    double availableWidth = screenWidth * (dashboard ? 0.46 : 0.90) - 16;
                    double availableHeight = screenHeight - 40;
                    GVMCardSize size = GVMCardSizeFor(availableWidth, availableHeight,
                        screenWidth, screenHeight, camera);
                    assert(size.compact == dashboard);
                    assert(size.width > 0 && size.height > 0);
                    assert(size.width < availableWidth && size.height < availableHeight);
                    double canvasWidth = dashboard ? 84 : (camera==2 ? 296 : camera ? 240 : 208);
                    double canvasHeight = dashboard ? (camera==2 ? 350 : camera ? 260 : 160) : 106;
                    assert(fabs(size.width / size.height - canvasWidth / canvasHeight) < 0.00001);
                }
            }
        }
        GVMCardSize wide = GVMCardSizeFor(560,200,640,240,YES);
        GVMCardSize shortMap = GVMCardSizeFor(560,80,640,240,YES);
        assert(shortMap.height < wide.height && shortMap.height <= 80 * 0.24);
        assert(!GVMCardSizeFor(0,100,400,240,NO).width);
        assert(!GVMCardSizeFor(NAN,100,400,240,NO).width);
        assert(!GVMCardSizeFor(100,100,0,240,NO).width);
        GVMCardSize card = {40,60,NO};
        GVMCardOrigin tl = GVMCardOriginFor(10,210,20,180,card,GVMCardTopLeft);
        GVMCardOrigin tr = GVMCardOriginFor(10,210,20,180,card,GVMCardTopRight);
        GVMCardOrigin bl = GVMCardOriginFor(10,210,20,180,card,GVMCardBottomLeft);
        GVMCardOrigin br = GVMCardOriginFor(10,210,20,180,card,GVMCardBottomRight);
        assert(tl.x==10 && tl.y==20 && tr.x==170 && tr.y==20);
        assert(bl.x==10 && bl.y==120 && br.x==170 && br.y==120);
        for (NSUInteger corner=0;corner<4;corner++) {
            NSArray *positions=@[@"top-left",@"top-right",@"bottom-left",@"bottom-right"];
            for (NSUInteger side=0;side<2;side++) {
                NSUInteger decoded=99; BOOL isLeft=NO;
                uint64_t state=GVMEncodePlacement(positions[corner],side ? @"left" : @"right");
                assert(GVMDecodePlacement(state,&decoded,&isLeft));
                assert(decoded==corner && isLeft==side);
            }
        }
        assert(!GVMDecodePlacement(0,NULL,NULL));
        assert(!GVMDecodePlacement(9,NULL,NULL));
        puts("speed-presentation tests passed");
    }
}
