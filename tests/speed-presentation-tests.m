#import <Foundation/Foundation.h>
#import "speed-presentation.h"
#import "placement-state.h"
#include <assert.h>
#include <math.h>
int main(void) {
    @autoreleasepool {
    NSDictionary *overspeed=@{@"speed":@{@"value":@61,@"receivedAt":@100},@"speedLimit":@{@"value":@60,@"receivedAt":@100}};
    uint64_t lease=GVMEncodeOverspeedLease(overspeed,100);
    assert((lease&3)==1);
    for (NSNumber *excess in @[@4,@5,@9,@10,@30]) {
        NSDictionary *sample=@{@"speed":@{@"value":@(60+excess.integerValue),@"receivedAt":@100},@"speedLimit":overspeed[@"speedLimit"]};
        assert((GVMEncodeOverspeedLease(sample,100)&3)==(excess.integerValue<5 ? 1 : excess.integerValue<10 ? 2 : 3));
    }
    assert(GVMOverspeedLeaseActive(lease,100.9)); assert(!GVMOverspeedLeaseActive(lease,101));
    assert(!GVMOverspeedLeaseActive(lease,99));
    assert(!GVMEncodeOverspeedLease(overspeed,105));
    assert(!GVMEncodeOverspeedLease(@{@"speed":@{@"value":@60,@"receivedAt":@100},@"speedLimit":overspeed[@"speedLimit"]},100));
    assert(!GVMEncodeOverspeedLease(@{@"speed":overspeed[@"speed"],@"speedLimit":@{@"value":@0,@"receivedAt":@100}},100));
    assert(!GVMEncodeOverspeedLease(@{},100));
    assert(!GVMEncodeOverspeedLease(@{@"speed":@{@"value":@YES,@"receivedAt":@100},@"speedLimit":overspeed[@"speedLimit"]},100));
    assert(!GVMEncodeOverspeedLease(overspeed,99));
    assert(!GVMEncodeOverspeedLease(overspeed,NAN));
    uint64_t almostExpired=GVMEncodeOverspeedLease(overspeed,104.8);
    assert(GVMOverspeedLeaseActive(almostExpired,104.9) && !GVMOverspeedLeaseActive(almostExpired,105));
        for (NSUInteger mask=0;mask<16;mask++) {
            BOOL master=(mask&1)!=0;
            uint64_t state=GVMEncodeBubbleVisibility(@(master),@((mask&2)!=0),@((mask&4)!=0),@((mask&8)!=0));
            for (NSUInteger surface=0;surface<3;surface++)
                assert(GVMDecodeBubbleVisibility(state,surface)==(master && (mask&(1UL<<(surface+1)))));
            // Turning the master back on preserves the individual screen choices.
            uint64_t resumed=GVMEncodeBubbleVisibility(@YES,@((mask&2)!=0),@((mask&4)!=0),@((mask&8)!=0));
            for (NSUInteger surface=0;surface<3;surface++)
                assert(GVMDecodeBubbleVisibility(resumed,surface)==((mask&(1UL<<(surface+1)))!=0));
        }
        for (NSUInteger surface=0;surface<3;surface++) {
            assert(GVMDecodeBubbleVisibility(0,surface));
            assert(GVMDecodeBubbleVisibility(UINT64_MAX,surface));
            assert(GVMDecodeBubbleVisibility(GVMEncodeBubbleVisibility(nil,nil,nil,nil),surface));
            assert(GVMDecodeBubbleVisibility(GVMEncodeBubbleVisibility(@"invalid",NSNull.null,@[],@{}),surface));
            assert(GVMDecodeBubbleVisibility((1ULL<<8)|0x10,surface));
        }
        assert(!GVMDecodeBubbleVisibility(GVMEncodeBubbleVisibility(nil,nil,nil,nil),3));
        NSArray *permutations=@[@[@"speed",@"limit",@"alerts"],@[@"speed",@"alerts",@"limit"],@[@"limit",@"speed",@"alerts"],@[@"limit",@"alerts",@"speed"],@[@"alerts",@"speed",@"limit"],@[@"alerts",@"limit",@"speed"]];
        for (NSArray *order in permutations) for (NSUInteger vertical=0;vertical<2;vertical++) for (NSUInteger alerts=0;alerts<3;alerts++) {
            GVMCardSize canvas=GVMCardCanvasSize(alerts,vertical);
            GVMModuleRect cells[4]={GVMModuleFrame(order,@"speed",vertical,alerts,0),
                GVMModuleFrame(order,@"limit",vertical,alerts,0)};
            for (NSUInteger i=0;i<alerts;i++) cells[2+i]=GVMModuleFrame(order,@"alerts",vertical,alerts,i);
            double area=0,minEdge=INFINITY,maxEdge=0;
            for (NSUInteger i=0;i<2+alerts;i++) {
                GVMModuleRect cell=cells[i];
                assert(cell.width==cells[0].width && cell.height==cells[0].height);
                assert(cell.width==88 && cell.height==88);
                assert(cell.x>=0 && cell.y>=0 && cell.x+cell.width<=canvas.width && cell.y+cell.height<=canvas.height);
                assert(vertical ? cell.x+cell.width/2==canvas.width/2 : cell.y+cell.height/2==canvas.height/2);
                area+=cell.width*cell.height;
                double start=vertical ? cell.y : cell.x;
                minEdge=MIN(minEdge,start); maxEdge=MAX(maxEdge,start+88);
                for (NSUInteger j=0;j<i;j++) {
                    GVMModuleRect other=cells[j];
                    assert(cell.x+cell.width<=other.x || other.x+other.width<=cell.x ||
                        cell.y+cell.height<=other.y || other.y+other.height<=cell.y);
                }
            }
            assert(minEdge==4 && maxEdge-minEdge==(2+alerts)*88);
            assert(area==(2+alerts)*88*88); // Every cell is accounted for; no gaps or reserved empty alert slot.
            if (alerts==2) assert(vertical ? cells[3].y-cells[2].y==88 : cells[3].x-cells[2].x==88);
            assert(GVMModuleFrame(order,@"alerts",vertical,alerts,alerts).width==0);
            assert(GVMModuleFrame(order,@"unknown",vertical,alerts,0).width==0);
        }
        for (NSUInteger vertical=0;vertical<2;vertical++) {
            GVMCardSize capped=GVMCardCanvasSize(99,vertical),two=GVMCardCanvasSize(2,vertical);
            assert(capped.width==two.width && capped.height==two.height);
            GVMModuleRect fallback=GVMModuleFrame(@[@"invalid"],@"speed",vertical,0,0);
            GVMModuleRect standard=GVMModuleFrame(nil,@"speed",vertical,0,0);
            assert(fallback.x==standard.x && fallback.y==standard.y);
        }
        for (NSArray *order in permutations) for (NSString *mode in @[@"auto",@"horizontal",@"vertical"]) {
            uint64_t state=GVMEncodeBubbleConfiguration(@[mode,mode,mode],@[order,order,order]);
            for (NSUInteger surface=0;surface<3;surface++) {
                assert([GVMDecodeModuleOrder(state,surface,YES) isEqual:order]);
                assert(GVMDecodeBubbleLayout(state,surface)==([mode isEqual:@"horizontal"] ? 1 : [mode isEqual:@"vertical"] ? 2 : 0));
            }
        }
        uint64_t invalid=GVMEncodeBubbleConfiguration(@[],@[@[@"speed",@"speed",@"alerts"]]);
        assert([GVMDecodeModuleOrder(invalid,0,NO) isEqual:permutations[0]]);
        assert([GVMDecodeModuleOrder(0,1,YES) isEqual:permutations[2]]);
        assert(GVMDecodeBubbleLayout(UINT64_MAX,0)==0);
        for (NSUInteger dashboard=0;dashboard<2;dashboard++) for (NSUInteger mode=0;mode<3;mode++) for (NSUInteger alerts=0;alerts<3;alerts++) {
            double width=dashboard ? 165 : 355;
            GVMCardSize size=GVMCarPlayCardSizeForLayout(width,226,400,240,alerts,dashboard,mode,100);
            assert(size.compact==(mode==2 || (mode==0 && dashboard)));
            assert(size.width>0 && size.height>0 && size.width<=width && size.height<=226);
            GVMCardSize scaled=GVMCarPlayCardSizeForLayout(width,226,400,240,alerts,dashboard,mode,150);
            for (NSUInteger corner=0;corner<4;corner++) {
                GVMCardOrigin origin=GVMCardOriginFor(0,width,0,226,scaled,(GVMCardPlacement)corner);
                assert(origin.x>=0 && origin.y>=0 && origin.x+scaled.width<=width+.001 && origin.y+scaled.height<=226+.001);
            }
        }
        // Same Dashboard modules retain their scale when rearranged, even on narrow tiles.
        const double tiles[][4]={{165,226,400,240},{105,120,240,160},{278,200,640,240},{120,90,400,240}};
        for (NSUInteger t=0;t<sizeof(tiles)/sizeof(tiles[0]);t++) for (NSUInteger alerts=0;alerts<3;alerts++) {
            double width=tiles[t][0],height=tiles[t][1];
            GVMCardSize hc=GVMCardCanvasSize(alerts,NO),vc=GVMCardCanvasSize(alerts,YES);
            for (NSUInteger percent=50;percent<=150;percent+=25) {
                GVMCardSize h=GVMCarPlayCardSizeForLayout(width,height,tiles[t][2],tiles[t][3],alerts,YES,1,percent);
                GVMCardSize v=GVMCarPlayCardSizeForLayout(width,height,tiles[t][2],tiles[t][3],alerts,YES,2,percent);
                GVMCardSize emptyCanvas=GVMCardCanvasSize(0,NO);
                GVMCardSize empty=GVMCarPlayCardSizeForLayout(width,height,tiles[t][2],tiles[t][3],0,YES,1,percent);
                // Incoming alerts may extend the group, but cannot resize existing modules.
                assert(fabs(h.width/hc.width-empty.width/emptyCanvas.width)<0.00001);
                assert(fabs(h.width/hc.width-v.width/vc.width)<0.00001);
                assert(fabs(h.width/hc.width-h.height/hc.height)<0.00001);
                assert(fabs(v.width/vc.width-v.height/vc.height)<0.00001);
                assert(h.width<=width+.00001 && h.height<=height+.00001);
                assert(v.width<=width+.00001 && v.height<=height+.00001);
                GVMCardSize automatic=GVMCarPlayCardSizeForLayout(width,height,tiles[t][2],tiles[t][3],alerts,YES,0,percent);
                assert(automatic.compact && automatic.width==v.width && automatic.height==v.height);
                for (NSUInteger corner=0;corner<2;corner++) for (NSUInteger direction=0;direction<2;direction++) {
                    GVMCardSize size=direction ? v : h;
                    GVMCardOrigin origin=GVMCardOriginFor(0,width,0,height,size,corner);
                    assert(origin.x>=0 && origin.y>=0 && origin.x+size.width<=width+.00001 && origin.y+size.height<=height+.00001);
                }
            }
        }
        // No viewport-fraction shrink as alerts arrive while the full group still fits.
        for (NSUInteger alerts=0;alerts<3;alerts++) for (NSUInteger mode=1;mode<=2;mode++) {
            GVMCardSize canvas=GVMCardCanvasSize(alerts,mode==2);
            GVMCardSize size=GVMCarPlayCardSizeForLayout(180,226,400,240,alerts,YES,mode,100);
            GVMCardSize larger=GVMCarPlayCardSizeForLayout(180,226,400,240,alerts,YES,mode,150);
            assert(fabs(size.width/canvas.width-30.0/96)<0.00001);
            assert(fabs(larger.width/size.width-1.5)<0.00001);
        }
        assert(!GVMCarPlayCardSizeForLayout(0,226,400,240,0,YES,1,100).width);
        assert(!GVMCarPlayCardSizeForLayout(NAN,226,400,240,0,YES,2,100).width);
        GVMCardSize defaultPercent=GVMCarPlayCardSizeForLayout(180,226,400,240,2,YES,1,NAN);
        assert(defaultPercent.width==GVMCarPlayCardSizeForLayout(180,226,400,240,2,YES,1,100).width);
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
                    double canvasWidth = dashboard ? 96 : 184+88*camera;
                    double canvasHeight = dashboard ? 184+88*camera : 96;
                    assert(fabs(size.width / size.height - canvasWidth / canvasHeight) < 0.00001);
                }
            }
        }
        // A full-map guidance panel reduces available space, not the presentation mode.
        for (NSUInteger alerts=0;alerts<3;alerts++) {
            GVMCardSize guided=GVMCarPlayCardSizeForView(190,189,355,400,240,alerts);
            assert(!guided.compact);
            double canvasWidth=184+88*alerts;
            assert(fabs(guided.width/guided.height-canvasWidth/96)<0.00001);
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
