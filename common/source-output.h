#import <Foundation/Foundation.h>
#include <stdint.h>

// IDs and enum values are wire contracts; append new values rather than reorder.
enum { GVMOutputSchemaVersion=1, GVMSourceVietMap=1, GVMMaximumSourceID=7 };
typedef NS_ENUM(NSUInteger, GVMRoadAlertType) {
    GVMRoadAlertCameraAI=1, GVMRoadAlertRestArea=2,
    GVMRoadAlertResidentialStart=3, GVMRoadAlertSpeedLimit=4,
    GVMRoadAlertNoEntry=5, GVMRoadAlertNoEntryLeft=6,
    GVMRoadAlertNoEntryRight=7, GVMRoadAlertNoLeft=8,
    GVMRoadAlertNoLeftRight=9, GVMRoadAlertNoLeftUTurn=10,
    GVMRoadAlertNoRight=11, GVMRoadAlertNoRightUTurn=12,
    GVMRoadAlertNoUTurnLeft=13, GVMRoadAlertNoUTurnRight=14,
    GVMRoadAlertNoPassingStart=15, GVMRoadAlertNoPassingEnd=16,
    GVMRoadAlertPenaltyCamera=17, GVMRoadAlertRailway=18,
    GVMRoadAlertResidentialEnd=19, GVMRoadAlertRestriction=20,
    GVMRoadAlertMandatoryRight=21, GVMRoadAlertSlowDown=22,
    GVMRoadAlertSpeedCamera=23, GVMRoadAlertStopLane=24,
    GVMRoadAlertMandatoryStraight=25, GVMRoadAlertMandatoryStraightLeft=26,
    GVMRoadAlertMandatoryStraightRight=27, GVMRoadAlertToll=28,
    GVMRoadAlertTollETC=29, GVMRoadAlertTrafficCamera=30,
    GVMRoadAlertTunnel=31, GVMRoadAlertMandatoryLeftRight=32,
    GVMRoadAlertMandatoryLeft=33
};

// Only these documented fields leave an adapter. No coordinates or raw payloads.
// speed/speedLimit: {value: integer km/h, receivedAt: monotonic seconds}.
// alerts: {type, value: limit or null, distance: metres or null,
//          artworkID: optional source-local decoration, receivedAt}.
NSDictionary *GVMNormalizeSourceOutput(id output, NSTimeInterval now);
NSDictionary *GVMSourceOutput(NSUInteger sourceID, NSDictionary *samples,
    NSArray<NSDictionary *> *alerts, NSTimeInterval now);
BOOL GVMSourceIDValid(NSUInteger sourceID);
NSString *GVMSourceDisplayName(NSUInteger sourceID);
NSString *GVMRoadAlertName(NSUInteger type);

enum { GVMOutputWordCount=6 };
typedef struct { uint64_t words[GVMOutputWordCount]; } GVMOutputWords;
BOOL GVMEncodeSourceOutput(NSDictionary *output, NSTimeInterval now, GVMOutputWords *words);
NSDictionary *GVMDecodeSourceOutput(NSUInteger sourceID, GVMOutputWords words, NSTimeInterval now);
NSUInteger GVMSourceIDForSelection(uint64_t selection);
BOOL GVMOutputFrameReadable(uint64_t before, uint64_t after,
    uint64_t selectionBefore, uint64_t selectionAfter, uint64_t frameSelection,
    NSUInteger sourceID);
