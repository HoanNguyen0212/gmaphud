#import "carplay-nav-hook.h"
#import "cmu-hud-relay.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#include <substrate.h>
#include <math.h>

// ── Vietnamese Diacritics Stripper for Mazda CMU HUD ────────────────────────

NSString *GVMStripVietnameseDiacritics(NSString *str) {
    if (!str || [str length] == 0) return @"";
    NSMutableString *ms = [str mutableCopy];
    // Replace đ / Đ explicitly first
    [ms replaceOccurrencesOfString:@"đ" withString:@"d" options:NSCaseInsensitiveSearch range:NSMakeRange(0, [ms length])];
    [ms replaceOccurrencesOfString:@"Đ" withString:@"D" options:NSCaseInsensitiveSearch range:NSMakeRange(0, [ms length])];
    // Transliterate to Latin (turns composed characters like 'ễ' into base + combining)
    CFStringTransform((__bridge CFMutableStringRef)ms, NULL, kCFStringTransformToLatin, NO);
    // Strip all combining accent marks
    CFStringTransform((__bridge CFMutableStringRef)ms, NULL, kCFStringTransformStripCombiningMarks, NO);
    
    // Convert to 7-bit ASCII to guarantee 100% clean HUD display
    NSData *asciiData = [ms dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
    NSString *clean = [[NSString alloc] initWithData:asciiData encoding:NSASCIIStringEncoding];
    if (!clean) clean = ms;
    
    // Normalize newlines, carriage returns, and tabs to spaces
    NSMutableString *res = [clean mutableCopy];
    [res replaceOccurrencesOfString:@"\n" withString:@" " options:NSLiteralSearch range:NSMakeRange(0, [res length])];
    [res replaceOccurrencesOfString:@"\r" withString:@" " options:NSLiteralSearch range:NSMakeRange(0, [res length])];
    [res replaceOccurrencesOfString:@"\t" withString:@" " options:NSLiteralSearch range:NSMakeRange(0, [res length])];
    
    // Collapse consecutive whitespaces
    NSArray *parts = [res componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSMutableArray *nonEmpty = [NSMutableArray array];
    for (NSString *p in parts) {
        if ([p length] > 0) [nonEmpty addObject:p];
    }
    return [[nonEmpty componentsJoinedByString:@" "] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

// ── Clean Road Name Extractor for Mazda CX-5 HUD ─────────────────────────────

NSString *GVMExtractRoadName(NSString *instruction) {
    NSString *clean = GVMStripVietnameseDiacritics(instruction);
    if (!clean || [clean length] == 0) return @"";
    
    NSString *lower = [clean lowercaseString];
    NSArray *prefixes = @[
        @"re sang phai vao ", @"re sang trai vao ",
        @"re phai vao ", @"re trai vao ",
        @"queo sang phai vao ", @"queo sang trai vao ",
        @"queo phai vao ", @"queo trai vao ",
        @"chech sang phai vao ", @"chech sang trai vao ",
        @"chech phai vao ", @"chech trai vao ",
        @"ngoat sang phai vao ", @"ngoat sang trai vao ",
        @"ngoat phai vao ", @"ngoat trai vao ",
        @"nhap vao ", @"nhap lan vao ", @"di vao ",
        @"di tiep tren ", @"tiep tuc tren ", @"di theo ",
        @"di ve phia ", @"ve phia ", @"huong ve phia ", @"di ve huong ", @"ve huong ",
        @"re sang phai ", @"re sang trai ",
        @"re phai ", @"re trai ",
        @"queo phai ", @"queo trai ",
        @"chech sang phai ", @"chech sang trai ",
        @"chech phai ", @"chech trai ",
        @"turn right on ", @"turn left on ", @"turn right onto ", @"turn left onto ",
        @"keep right onto ", @"keep left onto "
    ];
    for (NSString *p in prefixes) {
        if ([lower hasPrefix:p]) {
            clean = [clean substringFromIndex:[p length]];
            break;
        }
    }
    
    // Mazda CX-5 HUD text field safe limit: 28 characters
    if ([clean length] > 28) {
        clean = [clean substringToIndex:28];
    }
    return [clean stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

// ── Apple CarPlay CPManeuverType to Mazda CMU HUD Icon Mapping ───────────────

uint16_t GVMMapInstructionTextToMazdaHUD(NSString *instruction) {
    if (!instruction || instruction.length == 0) return 0;
    NSString *clean = GVMStripVietnameseDiacritics(instruction).lowercaseString;
    if ([clean containsString:@"quay dau"] || [clean containsString:@"u-turn"]) {
        return 13; // HUD_U_TURN_LEFT
    }
    if ([clean containsString:@"vong xuyen"] || [clean containsString:@"bung binh"] || [clean containsString:@"roundabout"]) {
        return 37; // HUD_ROUNDABOUT
    }
    if ([clean containsString:@"gat sang trai"] || [clean containsString:@"gat trai"] || [clean containsString:@"sharp left"]) {
        return 11; // HUD_SHARP_LEFT
    }
    if ([clean containsString:@"gat sang phai"] || [clean containsString:@"gat phai"] || [clean containsString:@"sharp right"]) {
        return 9; // HUD_SHARP_RIGHT
    }
    if ([clean containsString:@"chech sang trai"] || [clean containsString:@"chech trai"] || [clean containsString:@"slight left"]) {
        return 4; // HUD_SLIGHT_LEFT
    }
    if ([clean containsString:@"chech sang phai"] || [clean containsString:@"chech phai"] || [clean containsString:@"slight right"]) {
        return 5; // HUD_SLIGHT_RIGHT
    }
    if ([clean containsString:@"re sang trai"] || [clean containsString:@"re trai"] ||
        [clean containsString:@"queo sang trai"] || [clean containsString:@"queo trai"] ||
        [clean containsString:@"ngoat sang trai"] || [clean containsString:@"ngoat trai"] ||
        [clean containsString:@"sang trai"] || [clean containsString:@"qua trai"] ||
        [clean containsString:@"giu ben trai"] || [clean containsString:@"turn left"] ||
        [clean containsString:@"keep left"]) {
        return 2; // HUD_LEFT
    }
    if ([clean containsString:@"re sang phai"] || [clean containsString:@"re phai"] ||
        [clean containsString:@"queo sang phai"] || [clean containsString:@"queo phai"] ||
        [clean containsString:@"ngoat sang phai"] || [clean containsString:@"ngoat phai"] ||
        [clean containsString:@"sang phai"] || [clean containsString:@"qua phai"] ||
        [clean containsString:@"giu ben phai"] || [clean containsString:@"turn right"] ||
        [clean containsString:@"keep right"]) {
        return 3; // HUD_RIGHT
    }
    if ([clean containsString:@"loi ra"] || [clean containsString:@"exit"] || [clean containsString:@"off-ramp"]) {
        return 7; // HUD_OFF_RAMP_RIGHT
    }
    if ([clean containsString:@"nhap lan"] || [clean containsString:@"nhap vao"] || [clean containsString:@"merge"]) {
        return 16; // HUD_MERGE_LEFT
    }
    if ([clean containsString:@"den noi"] || [clean containsString:@"diem den"] || [clean containsString:@"arrive"] || [clean containsString:@"destination"]) {
        return 8; // HUD_DESTINATION
    }
    if ([clean containsString:@"di thang"] || [clean containsString:@"tiep tuc"] || [clean containsString:@"straight"] || [clean containsString:@"follow"]) {
        return 1; // HUD_STRAIGHT
    }
    return 0;
}

uint16_t GVMMapCarPlayManeuverToMazdaHUD(NSUInteger type) {
    switch (type) {
        case 0:  return 0;  // No turn / clear
        case 1:  return 2;  // LeftTurn -> HUD 2
        case 2:  return 3;  // RightTurn -> HUD 3
        case 3:  return 1;  // StraightAhead -> HUD 1
        case 4:             // UTurn
        case 18:            // StartRouteWithUTurn
        case 19:            // UTurnAtRoundabout
        case 26: return 13; // UTurnWhenPossible -> HUD 13
        case 5:  return 1;  // FollowRoad -> HUD 1
        case 6:             // EnterRoundabout generic
        case 7:  return 37; // ExitRoundabout generic -> HUD 37
        case 8:  return 7;  // OffRamp (Right exit in RHT) -> HUD 7
        case 9:  return 16; // OnRamp (Merge left in RHT) -> HUD 16
        case 10:            // ArriveEndOfNavigation
        case 12:            // ArriveAtDestination
        case 24:            // ArriveAtDestinationLeft
        case 25:            // ArriveAtDestinationRight
        case 27: return 8;  // ArriveEndOfDirections -> HUD 8
        case 11: return 1;  // StartRoute -> HUD 1
        case 13: return 15; // KeepLeft -> HUD 15 (HUD_FORK_LEFT)
        case 14: return 14; // KeepRight -> HUD 14 (HUD_FORK_RIGHT)
        case 15: case 16: case 17: return 1; // Ferry -> HUD 1
        case 20: return 31; // LeftTurnAtEnd (T-junction left) -> HUD 31
        case 21: return 32; // RightTurnAtEnd (T-junction right) -> HUD 32
        case 22: return 30; // HighwayOffRampLeft -> HUD 30
        case 23: return 7;  // HighwayOffRampRight -> HUD 7
        case 47: return 11; // SharpLeftTurn -> HUD 11
        case 48: return 9;  // SharpRightTurn -> HUD 9
        case 49: return 4;  // SlightLeftTurn -> HUD 4
        case 50: return 5;  // SlightRightTurn -> HUD 5
        case 51: return 1;  // ChangeHighway -> HUD 1
        case 52: return 15; // ChangeHighwayLeft -> HUD 15
        case 53: return 14; // ChangeHighwayRight -> HUD 14
        default:
            // Roundabout exits 1 through 19 (types 28..46 map to HUD 37..55)
            if (type >= 28 && type <= 46) {
                return (uint16_t)(37 + (type - 28));
            }
            return (type > 0) ? 1 : 0;
    }
}

// ── Maneuver Extraction & UDP Relay Dispatcher ──────────────────────────────

static NSString *GVMGetManeuverInstructionText(id maneuver) {
    if (!maneuver) return @"";
    NSString *road = @"";
    if ([maneuver respondsToSelector:@selector(attributedInstructionVariants)]) {
        NSArray *attrVariants = ((id (*)(id, SEL))objc_msgSend)(maneuver, @selector(attributedInstructionVariants));
        if ([attrVariants isKindOfClass:[NSArray class]] && [attrVariants count] > 0) {
            id firstAttr = [attrVariants firstObject];
            if ([firstAttr respondsToSelector:@selector(string)]) {
                road = [firstAttr string];
            } else if ([firstAttr isKindOfClass:[NSString class]]) {
                road = (NSString *)firstAttr;
            }
        }
    }
    if ((!road || road.length == 0) && [maneuver respondsToSelector:@selector(instructionVariants)]) {
        NSArray *variants = ((id (*)(id, SEL))objc_msgSend)(maneuver, @selector(instructionVariants));
        if ([variants isKindOfClass:[NSArray class]] && [variants count] > 0) {
            id firstVar = [variants firstObject];
            if ([firstVar isKindOfClass:[NSString class]]) {
                road = (NSString *)firstVar;
            }
        }
    }
    return road ?: @"";
}

static uint16_t GVMGetManeuverHUDIcon(id maneuver, NSString **outText) {
    if (!maneuver) return 0;
    NSString *text = GVMGetManeuverInstructionText(maneuver);
    if (outText) *outText = text;

    uint16_t icon = GVMMapInstructionTextToMazdaHUD(text);
    if (icon == 0 && [maneuver respondsToSelector:@selector(maneuverType)]) {
        NSUInteger mType = ((NSUInteger (*)(id, SEL))objc_msgSend)(maneuver, @selector(maneuverType));
        if (mType != 255) {
            icon = GVMMapCarPlayManeuverToMazdaHUD(mType);
        }
    }
    return icon;
}

static void ProcessManeuverAndEstimates(id maneuver, id estimates) {
    if (!maneuver) {
        GVMCMURelaySetNav(0, 0, @"");
        return;
    }

    NSUInteger mType = 0;
    if ([maneuver respondsToSelector:@selector(maneuverType)]) {
        mType = ((NSUInteger (*)(id, SEL))objc_msgSend)(maneuver, @selector(maneuverType));
    }

    double distMeters = 0.0;
    if (estimates && [estimates respondsToSelector:@selector(distanceRemaining)]) {
        id distObj = ((id (*)(id, SEL))objc_msgSend)(estimates, @selector(distanceRemaining));
        if ([distObj isKindOfClass:[NSMeasurement class]]) {
            NSMeasurement *meas = (NSMeasurement *)distObj;
            Class unitClass = NSClassFromString(@"NSUnitLength");
            if (unitClass && [unitClass respondsToSelector:@selector(meters)]) {
                NSUnit *metersUnit = [unitClass performSelector:@selector(meters)];
                if ([meas canBeConvertedToUnit:(NSUnitLength *)metersUnit]) {
                    NSMeasurement *inMeters = [meas measurementByConvertingToUnit:(NSUnitLength *)metersUnit];
                    distMeters = [inMeters doubleValue];
                } else {
                    distMeters = [meas doubleValue];
                }
            } else {
                distMeters = [meas doubleValue];
            }
        } else if ([distObj respondsToSelector:@selector(doubleValue)]) {
            distMeters = [distObj doubleValue];
        }
    } else if ([maneuver respondsToSelector:@selector(initialTravelEstimates)]) {
        id initEst = ((id (*)(id, SEL))objc_msgSend)(maneuver, @selector(initialTravelEstimates));
        if (initEst && [initEst respondsToSelector:@selector(distanceRemaining)]) {
            id distObj = ((id (*)(id, SEL))objc_msgSend)(initEst, @selector(distanceRemaining));
            if ([distObj isKindOfClass:[NSMeasurement class]]) {
                NSMeasurement *meas = (NSMeasurement *)distObj;
                Class unitClass = NSClassFromString(@"NSUnitLength");
                if (unitClass && [unitClass respondsToSelector:@selector(meters)]) {
                    NSUnit *metersUnit = [unitClass performSelector:@selector(meters)];
                    if ([meas canBeConvertedToUnit:(NSUnitLength *)metersUnit]) {
                        NSMeasurement *inMeters = [meas measurementByConvertingToUnit:(NSUnitLength *)metersUnit];
                        distMeters = [inMeters doubleValue];
                    } else {
                        distMeters = [meas doubleValue];
                    }
                } else {
                    distMeters = [meas doubleValue];
                }
            } else if ([distObj respondsToSelector:@selector(doubleValue)]) {
                distMeters = [distObj doubleValue];
            }
        }
    }

    NSString *road = GVMGetManeuverInstructionText(maneuver);
    uint16_t hudIcon = GVMGetManeuverHUDIcon(maneuver, NULL);

    NSUInteger finalDist = (NSUInteger)fmax(0.0, round(distMeters));

    // Fallback to Straight (1) when navigating with valid distance so HUD is never blank
    if (hudIcon == 0 && finalDist > 0) {
        hudIcon = 1; // HUD_STRAIGHT
    }

    NSString *cleanRoad = GVMExtractRoadName(road);
    if (!cleanRoad || [cleanRoad length] == 0) {
        cleanRoad = GVMStripVietnameseDiacritics(road);
    }

    char navLog[512];
    time_t now = time(NULL);
    struct tm *tm_info = localtime(&now);
    char timeStr[32];
    strftime(timeStr, sizeof(timeStr), "%H:%M:%S", tm_info);
    snprintf(navLog, sizeof(navLog), "[%s] [NAV_INTERCEPT] mType=%lu hudIcon=%u dist=%lu road=\"%s\"\n",
             timeStr, (unsigned long)mType, (unsigned int)hudIcon, (unsigned long)finalDist, cleanRoad.UTF8String ?: "");
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"gmaphud-relay.log"];
    FILE *f = fopen(path.UTF8String, "a");
    if (f) {
        fputs(navLog, f);
        fclose(f);
    }

    GVMCMURelaySetNav(hudIcon, finalDist, cleanRoad);
}

// ── Hook Implementations for CPNavigationSession ────────────────────────────

static void (*orig_updateTravelEstimates)(id self, SEL _cmd, id estimates, id maneuver) = NULL;
static void hook_updateTravelEstimates(id self, SEL _cmd, id estimates, id maneuver) {
    if (orig_updateTravelEstimates) {
        orig_updateTravelEstimates(self, _cmd, estimates, maneuver);
    }
    @try {
        id targetManeuver = maneuver;
        NSString *curText = nil;
        uint16_t curIcon = GVMGetManeuverHUDIcon(maneuver, &curText);

        // If current maneuver is just heading/depart (icon <= 1), look into upcomingManeuvers
        // to display the approaching actionable turn (left/right/roundabout) to the driver!
        if (curIcon <= 1 && [self respondsToSelector:@selector(upcomingManeuvers)]) {
            NSArray *upcoming = ((id (*)(id, SEL))objc_msgSend)(self, @selector(upcomingManeuvers));
            if ([upcoming isKindOfClass:[NSArray class]] && [upcoming count] > 0) {
                for (id m in upcoming) {
                    NSString *mText = nil;
                    uint16_t mIcon = GVMGetManeuverHUDIcon(m, &mText);
                    if (mIcon >= 2) {
                        targetManeuver = m;
                        break;
                    }
                }
            }
        }
        ProcessManeuverAndEstimates(targetManeuver, estimates);
    } @catch (__unused NSException *e) {
        // Safe fail-safe: never disrupt CarPlay host application
    }
}

static void (*orig_setManeuvers)(id self, SEL _cmd, id maneuvers) = NULL;
static void hook_setManeuvers(id self, SEL _cmd, id maneuvers) {
    if (orig_setManeuvers) {
        orig_setManeuvers(self, _cmd, maneuvers);
    }
    @try {
        if ([maneuvers isKindOfClass:[NSArray class]] && [(NSArray *)maneuvers count] > 0) {
            NSArray *arr = (NSArray *)maneuvers;
            id chosenManeuver = [arr firstObject];
            NSString *firstText = nil;
            uint16_t firstIcon = GVMGetManeuverHUDIcon(chosenManeuver, &firstText);

            // If the first item has no actionable turn (e.g. "Đi về phía...", mType=255/11/5, icon <= 1),
            // look ahead for the first real actionable turn in the maneuvers window!
            if (firstIcon <= 1) {
                for (NSUInteger i = 1; i < [arr count]; i++) {
                    id m = arr[i];
                    NSString *mText = nil;
                    uint16_t mIcon = GVMGetManeuverHUDIcon(m, &mText);
                    if (mIcon >= 2) {
                        chosenManeuver = m;
                        break;
                    }
                }
            }
            ProcessManeuverAndEstimates(chosenManeuver, nil);
        }
    } @catch (__unused NSException *e) {}
}

static void (*orig_pauseTrip)(id self, SEL _cmd, NSUInteger reason, id description) = NULL;
static void hook_pauseTrip(id self, SEL _cmd, NSUInteger reason, id description) {
    if (orig_pauseTrip) {
        orig_pauseTrip(self, _cmd, reason, description);
    }
    GVMCMURelaySetNav(0, 0, @"");
}

static void (*orig_finishTrip)(id self, SEL _cmd) = NULL;
static void hook_finishTrip(id self, SEL _cmd) {
    if (orig_finishTrip) {
        orig_finishTrip(self, _cmd);
    }
    GVMCMURelaySetNav(0, 0, @"");
}

static void (*orig_cancelTrip)(id self, SEL _cmd) = NULL;
static void hook_cancelTrip(id self, SEL _cmd) {
    if (orig_cancelTrip) {
        orig_cancelTrip(self, _cmd);
    }
    GVMCMURelaySetNav(0, 0, @"");
}

// ── Public Installer ────────────────────────────────────────────────────────

void GVMInstallCarPlayNavHook(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Ensure CarPlay framework is loaded into Google Maps process
        dlopen("/System/Library/Frameworks/CarPlay.framework/CarPlay", RTLD_NOW);

        Class navSession = NSClassFromString(@"CPNavigationSession");
        if (navSession) {
            // Hook maneuver & estimates update
            SEL selUpdate = NSSelectorFromString(@"updateTravelEstimates:forManeuver:");
            if (class_getInstanceMethod(navSession, selUpdate)) {
                MSHookMessageEx(navSession, selUpdate, (IMP)hook_updateTravelEstimates, (IMP *)&orig_updateTravelEstimates);
            }

            // Hook upcoming maneuvers list (both setUpcomingManeuvers: and setManeuvers:)
            SEL selUpcoming = NSSelectorFromString(@"setUpcomingManeuvers:");
            if (class_getInstanceMethod(navSession, selUpcoming)) {
                MSHookMessageEx(navSession, selUpcoming, (IMP)hook_setManeuvers, (IMP *)&orig_setManeuvers);
            }
            SEL selManeuvers = NSSelectorFromString(@"setManeuvers:");
            if (class_getInstanceMethod(navSession, selManeuvers)) {
                MSHookMessageEx(navSession, selManeuvers, (IMP)hook_setManeuvers, (IMP *)&orig_setManeuvers);
            }

            // Hook trip pause, finish, and cancel
            SEL selPause = NSSelectorFromString(@"pauseTripForReason:description:");
            if (class_getInstanceMethod(navSession, selPause)) {
                MSHookMessageEx(navSession, selPause, (IMP)hook_pauseTrip, (IMP *)&orig_pauseTrip);
            }

            SEL selFinish = NSSelectorFromString(@"finishTrip");
            if (class_getInstanceMethod(navSession, selFinish)) {
                MSHookMessageEx(navSession, selFinish, (IMP)hook_finishTrip, (IMP *)&orig_finishTrip);
            }

            SEL selCancel = NSSelectorFromString(@"cancelTrip");
            if (class_getInstanceMethod(navSession, selCancel)) {
                MSHookMessageEx(navSession, selCancel, (IMP)hook_cancelTrip, (IMP *)&orig_cancelTrip);
            }
        }
    });
}
