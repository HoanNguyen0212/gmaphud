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
        // A full-map guidance panel reduces available space, not the presentation mode.
        for (NSUInteger alerts=0;alerts<3;alerts++) {
            GVMCardSize guided=GVMCarPlayCardSizeForView(190,189,355,400,240,alerts);
            assert(!guided.compact);
            double canvasWidth=alerts==2 ? 296 : alerts ? 240 : 208;
            assert(fabs(guided.width/guided.height-canvasWidth/106)<0.00001);
            GVMCardSize dash=GVMCarPlayCardSizeForView(130,189,165.5,400,240,alerts);
            assert(dash.compact && dash.height>dash.width);
        }
        GVMCardSize wide = GVMCardSizeFor(560,200,640,240,YES);
        // Navigation exclusions can exceed the remaining space at a corner.
        // Keep the viewport-sized card intact and move it inside the viewport.
        for (NSUInteger alerts=0;alerts<3;alerts++) {
            for (NSUInteger dashboard=0;dashboard<2;dashboard++) {
                double width=dashboard ? 165.5 : 355;
                GVMCardSize base=GVMCarPlayCardSizeForView(width-14,226,width,400,240,alerts);
                for (NSUInteger percent=50;percent<=150;percent+=50) {
                    GVMCardSize scaled=GVMScaleCardSize(base,percent,width-14,226);
                    assert(fabs(scaled.width-base.width*percent/100.0)<0.00001);
                    assert(fabs(scaled.height-base.height*percent/100.0)<0.00001);
                    for (NSUInteger corner=0;corner<4;corner++) {
                        GVMCardOrigin requested=GVMCardOriginFor(width-20,width-80,220,180,scaled,corner);
                        GVMCardOrigin clamped=GVMClampCardOrigin(requested,scaled,7,width-7,7,233);
                        assert(clamped.x>=7 && clamped.y>=7);
                        assert(clamped.x+scaled.width<=width-7+0.00001);
                        assert(clamped.y+scaled.height<=233+0.00001);
                        GVMCardOrigin unchanged=GVMClampCardOrigin(clamped,scaled,7,width-7,7,233);
                        assert(unchanged.x==clamped.x && unchanged.y==clamped.y);
                    }
                }
            }
        }
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
        GVMCardSize portrait=GVMPhoneCardSizeFor(390,844,2);
    GVMCardSize landscape=GVMPhoneCardSizeFor(844,390,2);
    assert(portrait.compact && portrait.height>portrait.width);
    assert(!landscape.compact && landscape.width>landscape.height);
    assert(GVMPhoneCardSizeFor(0,100,0).width==0);
    for (NSUInteger c=0;c<4;c++) {
        NSUInteger corner=9; NSInteger x=0,y=0;
        NSArray *corners=@[@"top-left",@"top-right",@"bottom-left",@"bottom-right"];
        GVMDecodePhonePlacement(GVMEncodePhonePlacement(corners[c],@(-23),@87,@"auto"),&corner,&x,&y,NULL);
        assert(corner==c && x==-23 && y==87);
    }
    NSUInteger fallbackCorner=9; NSInteger fallbackX=99,fallbackY=99;
    GVMDecodePhonePlacement(0,&fallbackCorner,&fallbackX,&fallbackY,NULL);
    assert(fallbackCorner==1 && fallbackX==0 && fallbackY==0);
    assert(GVMOffsetPercent(@999)==100 && GVMOffsetPercent(@(-999))==-100 && GVMOffsetPercent(@(NAN))==0);
    assert(GVMOffsetPercentFromPoints(@100,400)==25);
    assert(GVMOffsetPercentFromPoints(@(-200),800)==-25);
    assert(GVMOffsetPercentFromPoints(@100,0)==0);
    assert(GVMOffsetPercent(@YES)==0);
    for (NSUInteger mode=0;mode<3;mode++) {
        NSUInteger decoded=99;
        GVMDecodePhonePlacement(GVMEncodePhonePlacement(@"bottom-right",@100,@(-100),@[@"auto",@"horizontal",@"vertical"][mode]),NULL,&fallbackX,&fallbackY,&decoded);
        assert(decoded==mode && fallbackX==100 && fallbackY==-100);
    }
    // Legacy point packets must not be interpreted as percentages.
    GVMDecodePhonePlacement(1ULL<<32,NULL,&fallbackX,&fallbackY,NULL);
    assert(fallbackX==0 && fallbackY==0);
    assert(!GVMPhoneCardSizeForLayout(390,844,2,1).compact);
    assert(GVMPhoneCardSizeForLayout(844,390,2,2).compact);
    GVMCardSize forced=GVMPhoneCardSizeForLayout(320,568,2,1);
    assert(forced.width<=320 && forced.height<=568);
    GVMCardSize phoneCard={80,120,YES};
    GVMCardOrigin home=GVMPhoneCardOriginFor(10,380,50,800,phoneCard,GVMCardTopRight,0,0);
    assert(home.x==300 && home.y==50);
    GVMCardOrigin movedUp=GVMPhoneCardOriginFor(10,380,50,800,phoneCard,GVMCardTopRight,0,-50);
    assert(movedUp.y==50); // Only the supplied screen edge limits movement.
    for (NSUInteger corner=0;corner<4;corner++) {
        GVMCardOrigin minEdge=GVMPhoneCardOriginFor(10,380,50,800,phoneCard,corner,-1000,-1000);
        GVMCardOrigin maxEdge=GVMPhoneCardOriginFor(10,380,50,800,phoneCard,corner,1000,1000);
        assert(minEdge.x==10 && minEdge.y==50);
        assert(maxEdge.x==300 && maxEdge.y==680);
    }
    GVMCardOrigin shortScreen=GVMPhoneCardOriginFor(44,800,10,150,phoneCard,GVMCardTopLeft,0,0);
    assert(shortScreen.x==44 && shortScreen.y==10);
    GVMCardOrigin fullScreen=GVMPhoneCardOriginFor(0,390,0,844,phoneCard,GVMCardTopLeft,0,0);
    assert(fullScreen.x==0 && fullScreen.y==0);
    GVMCardOrigin farEdge=GVMPhoneCardOriginFor(0,390,0,844,phoneCard,GVMCardTopLeft,390,844);
    assert(farEdge.x==310 && farEdge.y==724);
    uint64_t sizes=GVMEncodeSizes(@50,@125,@150);
    assert(GVMDecodeSize(sizes,0)==50 && GVMDecodeSize(sizes,1)==125 && GVMDecodeSize(sizes,2)==150);
    assert(GVMDecodeSize(0,0)==100 && GVMDecodeSize(sizes,3)==100);
    assert(GVMSizePercent(@(NAN))==100 && GVMSizePercent(@YES)==100 && GVMSizePercent(@999)==150);
    GVMCardSize doubled=GVMScaleCardSize((GVMCardSize){100,50,NO},150,120,100);
    assert(doubled.width==120 && doubled.height==60);
    GVMCardSize reduced=GVMScaleCardSize((GVMCardSize){100,50,YES},50,300,200);
    assert(reduced.width==50 && reduced.height==25 && reduced.compact);
    puts("speed-presentation tests passed");
    }
}
