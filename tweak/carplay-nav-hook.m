#import "carplay-nav-hook.h"
#import "cmu-hud-relay.h"
#import <UIKit/UIKit.h>
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

// ── Vietnamese Normalizer for Mazda CMU HUD (keeps 2-byte: â, ê, ô, ă, ư, ơ, đ) ────────

NSString *GVMNormalizeVietnameseForHUD(NSString *src) {
    if (!src || src.length == 0) return @"";
    NSMutableString *s = [src mutableCopy];
    
    // Lowercase tone mark normalizations
    [s replaceOccurrencesOfString:@"á" withString:@"a" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"à" withString:@"a" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ả" withString:@"a" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ã" withString:@"a" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ạ" withString:@"a" options:0 range:NSMakeRange(0, s.length)];

    [s replaceOccurrencesOfString:@"ấ" withString:@"â" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ầ" withString:@"â" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ẩ" withString:@"â" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ẫ" withString:@"â" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ậ" withString:@"â" options:0 range:NSMakeRange(0, s.length)];

    [s replaceOccurrencesOfString:@"ắ" withString:@"ă" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ằ" withString:@"ă" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ẳ" withString:@"ă" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ẵ" withString:@"ă" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ặ" withString:@"ă" options:0 range:NSMakeRange(0, s.length)];

    [s replaceOccurrencesOfString:@"é" withString:@"e" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"è" withString:@"e" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ẻ" withString:@"e" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ẽ" withString:@"e" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ẹ" withString:@"e" options:0 range:NSMakeRange(0, s.length)];

    [s replaceOccurrencesOfString:@"ế" withString:@"ê" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ề" withString:@"ê" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ể" withString:@"ê" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ễ" withString:@"ê" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ệ" withString:@"ê" options:0 range:NSMakeRange(0, s.length)];

    [s replaceOccurrencesOfString:@"í" withString:@"i" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ì" withString:@"i" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ỉ" withString:@"i" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ĩ" withString:@"i" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ị" withString:@"i" options:0 range:NSMakeRange(0, s.length)];

    [s replaceOccurrencesOfString:@"ó" withString:@"o" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ò" withString:@"o" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ỏ" withString:@"o" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"õ" withString:@"o" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ọ" withString:@"o" options:0 range:NSMakeRange(0, s.length)];

    [s replaceOccurrencesOfString:@"ố" withString:@"ô" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ồ" withString:@"ô" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ổ" withString:@"ô" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ỗ" withString:@"ô" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ộ" withString:@"ô" options:0 range:NSMakeRange(0, s.length)];

    [s replaceOccurrencesOfString:@"ớ" withString:@"ơ" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ờ" withString:@"ơ" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ở" withString:@"ơ" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ỡ" withString:@"ơ" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ợ" withString:@"ơ" options:0 range:NSMakeRange(0, s.length)];

    [s replaceOccurrencesOfString:@"ú" withString:@"u" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ù" withString:@"u" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ủ" withString:@"u" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ũ" withString:@"u" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ụ" withString:@"u" options:0 range:NSMakeRange(0, s.length)];

    [s replaceOccurrencesOfString:@"ứ" withString:@"ư" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ừ" withString:@"ư" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ử" withString:@"ư" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ữ" withString:@"ư" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ự" withString:@"ư" options:0 range:NSMakeRange(0, s.length)];

    [s replaceOccurrencesOfString:@"ý" withString:@"y" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ỳ" withString:@"y" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ỷ" withString:@"y" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ỹ" withString:@"y" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"ỵ" withString:@"y" options:0 range:NSMakeRange(0, s.length)];

    // Uppercase tone mark normalizations
    [s replaceOccurrencesOfString:@"Á" withString:@"A" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"À" withString:@"A" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ả" withString:@"A" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ã" withString:@"A" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ạ" withString:@"A" options:0 range:NSMakeRange(0, s.length)];

    [s replaceOccurrencesOfString:@"Ấ" withString:@"Â" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ầ" withString:@"Â" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ẩ" withString:@"Â" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ẫ" withString:@"Â" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ậ" withString:@"Â" options:0 range:NSMakeRange(0, s.length)];

    [s replaceOccurrencesOfString:@"Ắ" withString:@"Ă" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ằ" withString:@"Ă" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ẳ" withString:@"Ă" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ẵ" withString:@"Ă" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ặ" withString:@"Ă" options:0 range:NSMakeRange(0, s.length)];

    [s replaceOccurrencesOfString:@"É" withString:@"E" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"È" withString:@"E" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ẻ" withString:@"E" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ẽ" withString:@"E" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ẹ" withString:@"E" options:0 range:NSMakeRange(0, s.length)];

    [s replaceOccurrencesOfString:@"Ế" withString:@"Ê" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ề" withString:@"Ê" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ể" withString:@"Ê" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ễ" withString:@"Ê" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ệ" withString:@"Ê" options:0 range:NSMakeRange(0, s.length)];

    [s replaceOccurrencesOfString:@"Í" withString:@"I" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ì" withString:@"I" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ỉ" withString:@"I" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ĩ" withString:@"I" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ị" withString:@"I" options:0 range:NSMakeRange(0, s.length)];

    [s replaceOccurrencesOfString:@"Ó" withString:@"O" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ò" withString:@"O" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ỏ" withString:@"O" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Õ" withString:@"O" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ọ" withString:@"O" options:0 range:NSMakeRange(0, s.length)];

    [s replaceOccurrencesOfString:@"Ố" withString:@"Ô" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ồ" withString:@"Ô" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ổ" withString:@"Ô" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ỗ" withString:@"Ô" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ộ" withString:@"Ô" options:0 range:NSMakeRange(0, s.length)];

    [s replaceOccurrencesOfString:@"Ớ" withString:@"Ơ" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ờ" withString:@"Ơ" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ở" withString:@"Ơ" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ỡ" withString:@"Ơ" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ợ" withString:@"Ơ" options:0 range:NSMakeRange(0, s.length)];

    [s replaceOccurrencesOfString:@"Ú" withString:@"U" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ù" withString:@"U" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ủ" withString:@"U" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ũ" withString:@"U" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ụ" withString:@"U" options:0 range:NSMakeRange(0, s.length)];

    [s replaceOccurrencesOfString:@"Ứ" withString:@"Ư" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ừ" withString:@"Ư" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ử" withString:@"Ư" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ữ" withString:@"Ư" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ự" withString:@"Ư" options:0 range:NSMakeRange(0, s.length)];

    [s replaceOccurrencesOfString:@"Ý" withString:@"Y" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ỳ" withString:@"Y" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ỷ" withString:@"Y" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ỹ" withString:@"Y" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Ỵ" withString:@"Y" options:0 range:NSMakeRange(0, s.length)];

    return s;
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
    
    // 0. Direct Unicode arrow checks
    if ([instruction containsString:@"⬅"] || [instruction containsString:@"←"] ||
        [instruction containsString:@"↖"] || [instruction containsString:@"↙"] ||
        [instruction containsString:@"↰"] || [instruction containsString:@"↲"] ||
        [instruction containsString:@"↩"] || [instruction containsString:@"⇐"]) {
        return 2; // HUD_LEFT
    }
    if ([instruction containsString:@"➡"] || [instruction containsString:@"→"] ||
        [instruction containsString:@"↗"] || [instruction containsString:@"↘"] ||
        [instruction containsString:@"↱"] || [instruction containsString:@"↳"] ||
        [instruction containsString:@"↪"] || [instruction containsString:@"⇒"]) {
        return 3; // HUD_RIGHT
    }
    if ([instruction containsString:@"⬆"] || [instruction containsString:@"↑"] ||
        [instruction containsString:@"⇑"]) {
        return 1; // HUD_STRAIGHT
    }

    NSString *clean = GVMStripVietnameseDiacritics(instruction).lowercaseString;
    if ([clean containsString:@"quay dau"] || [clean containsString:@"u-turn"] || [clean containsString:@"uturn"] || [clean containsString:@"arrow.uturn"]) {
        return 13; // HUD_U_TURN_LEFT
    }
    if ([clean containsString:@"vong xuyen"] || [clean containsString:@"bung binh"] || [clean containsString:@"roundabout"]) {
        return 37; // HUD_ROUNDABOUT
    }
    if ([clean containsString:@"gat sang trai"] || [clean containsString:@"gat trai"] || [clean containsString:@"sharp left"] || [clean containsString:@"sharp_left"]) {
        return 11; // HUD_SHARP_LEFT
    }
    if ([clean containsString:@"gat sang phai"] || [clean containsString:@"gat phai"] || [clean containsString:@"sharp right"] || [clean containsString:@"sharp_right"]) {
        return 9; // HUD_SHARP_RIGHT
    }
    if ([clean containsString:@"chech sang trai"] || [clean containsString:@"chech trai"] || [clean containsString:@"slight left"] || [clean containsString:@"slight_left"]) {
        return 4; // HUD_SLIGHT_LEFT
    }
    if ([clean containsString:@"chech sang phai"] || [clean containsString:@"chech phai"] || [clean containsString:@"slight right"] || [clean containsString:@"slight_right"]) {
        return 5; // HUD_SLIGHT_RIGHT
    }
    if ([clean containsString:@"re sang trai"] || [clean containsString:@"re trai"] ||
        [clean containsString:@"queo sang trai"] || [clean containsString:@"queo trai"] ||
        [clean containsString:@"ngoat sang trai"] || [clean containsString:@"ngoat trai"] ||
        [clean containsString:@"sang trai"] || [clean containsString:@"qua trai"] ||
        [clean containsString:@"ben trai"] || [clean containsString:@"phia trai"] ||
        [clean containsString:@"giu ben trai"] || [clean containsString:@"turn left"] ||
        [clean containsString:@"turn_left"] || [clean containsString:@"turn-left"] ||
        [clean containsString:@"left_turn"] || [clean containsString:@"left-turn"] ||
        [clean containsString:@"arrow_left"] || [clean containsString:@"arrow-left"] ||
        [clean containsString:@"arrow.turn.up.left"] || [clean containsString:@"arrow.left"] ||
        [clean containsString:@"keep left"] || [clean containsString:@"keep_left"]) {
        return 2; // HUD_LEFT
    }
    if ([clean containsString:@"re sang phai"] || [clean containsString:@"re phai"] ||
        [clean containsString:@"queo sang phai"] || [clean containsString:@"queo phai"] ||
        [clean containsString:@"ngoat sang phai"] || [clean containsString:@"ngoat phai"] ||
        [clean containsString:@"sang phai"] || [clean containsString:@"qua phai"] ||
        [clean containsString:@"ben phai"] || [clean containsString:@"phia phai"] ||
        [clean containsString:@"giu ben phai"] || [clean containsString:@"turn right"] ||
        [clean containsString:@"turn_right"] || [clean containsString:@"turn-right"] ||
        [clean containsString:@"right_turn"] || [clean containsString:@"right-turn"] ||
        [clean containsString:@"arrow_right"] || [clean containsString:@"arrow-right"] ||
        [clean containsString:@"arrow.turn.up.right"] || [clean containsString:@"arrow.right"] ||
        [clean containsString:@"keep right"] || [clean containsString:@"keep_right"]) {
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
    if ([clean containsString:@"di thang"] || [clean containsString:@"tiep tuc"] || [clean containsString:@"straight"] || [clean containsString:@"follow"] || [clean containsString:@"arrow.up"]) {
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

static UIImage *GVMExtractUIImage(id obj) {
    if (!obj) return nil;
    if ([obj isKindOfClass:[UIImage class]]) return (UIImage *)obj;
    if ([obj respondsToSelector:@selector(lightImage)]) {
        id img = ((id (*)(id, SEL))objc_msgSend)(obj, @selector(lightImage));
        if ([img isKindOfClass:[UIImage class]]) return (UIImage *)img;
    }
    if ([obj respondsToSelector:@selector(darkImage)]) {
        id img = ((id (*)(id, SEL))objc_msgSend)(obj, @selector(darkImage));
        if ([img isKindOfClass:[UIImage class]]) return (UIImage *)img;
    }
    if ([obj respondsToSelector:@selector(image)]) {
        id img = ((id (*)(id, SEL))objc_msgSend)(obj, @selector(image));
        if ([img isKindOfClass:[UIImage class]]) return (UIImage *)img;
    }
    return nil;
}

static uint16_t GVMDetectIconFromImage(id imageObj) {
    if (!imageObj) return 0;
    if (![NSThread isMainThread]) {
        __block uint16_t bgRes = 0;
        dispatch_sync(dispatch_get_main_queue(), ^{
            bgRes = GVMDetectIconFromImage(imageObj);
        });
        return bgRes;
    }
    @autoreleasepool {
    UIImage *image = GVMExtractUIImage(imageObj);
    
    // Check accessibility identifier / label / asset name / description
    NSMutableArray *identStrings = [NSMutableArray new];
    if ([imageObj respondsToSelector:@selector(accessibilityIdentifier)]) {
        NSString *s = [imageObj accessibilityIdentifier];
        if (s && s.length > 0) [identStrings addObject:s];
    }
    if ([imageObj respondsToSelector:@selector(accessibilityLabel)]) {
        NSString *s = [imageObj accessibilityLabel];
        if (s && s.length > 0) [identStrings addObject:s];
    }
    if (image && [image respondsToSelector:@selector(accessibilityIdentifier)]) {
        NSString *s = [image accessibilityIdentifier];
        if (s && s.length > 0) [identStrings addObject:s];
    }
    if (image && [image respondsToSelector:@selector(accessibilityLabel)]) {
        NSString *s = [image accessibilityLabel];
        if (s && s.length > 0) [identStrings addObject:s];
    }
    if (image && [image respondsToSelector:@selector(imageAsset)]) {
        id asset = [image performSelector:@selector(imageAsset)];
        if (asset && [asset respondsToSelector:@selector(assetName)]) {
            NSString *s = [asset performSelector:@selector(assetName)];
            if (s && s.length > 0) [identStrings addObject:s];
        }
    }
    NSString *descObj = [imageObj description];
    if (descObj && descObj.length > 0) [identStrings addObject:descObj];
    if (image) {
        NSString *descImg = [image description];
        if (descImg && descImg.length > 0) [identStrings addObject:descImg];
    }
    
    for (NSString *str in identStrings) {
        uint16_t mapped = GVMMapInstructionTextToMazdaHUD(str);
        if (mapped > 0) return mapped;
    }
    
    if (!image) return 0;
    
    // Pixel/bitmap inspection using UIKit thumbnail rendering
    CGSize thumbSize = CGSizeMake(16, 16);
    UIGraphicsBeginImageContextWithOptions(thumbSize, NO, 1.0);
    [image drawInRect:CGRectMake(0, 0, 16, 16)];
    UIImage *thumb = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    CGImageRef cgImage = thumb.CGImage;
    if (!cgImage) cgImage = image.CGImage;
    if (!cgImage) return 0;
    
    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);
    if (width < 8 || height < 8) return 0;
    
    uint32_t rgbaBuffer[256] = {0}; // 16x16 RGBA thumbnail
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(rgbaBuffer, 16, 16, 8, 16 * 4, colorSpace, (CGBitmapInfo)(kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big));
    CGColorSpaceRelease(colorSpace);
    if (!ctx) return 0;
    
    CGContextDrawImage(ctx, CGRectMake(0, 0, 16, 16), cgImage);
    CGContextRelease(ctx);
    
    // Check if image uses transparency or is opaque
    BOOL hasTransparency = NO;
    for (int i = 0; i < 256; i++) {
        uint8_t a = rgbaBuffer[i] & 0xFF;
        if (a < 50) {
            hasTransparency = YES;
            break;
        }
    }
    
    // Determine background luminance if opaque
    float cornerLumSum = 0;
    int corners[4] = {0, 15, 240, 255};
    for (int i = 0; i < 4; i++) {
        uint32_t px = rgbaBuffer[corners[i]];
        float r = (float)((px >> 24) & 0xFF);
        float g = (float)((px >> 16) & 0xFF);
        float b = (float)((px >> 8) & 0xFF);
        cornerLumSum += 0.299f * r + 0.587f * g + 0.114f * b;
    }
    float bgLum = cornerLumSum / 4.0f;
    BOOL isWhiteBg = (bgLum > 128.0f);
    
    float topSumX = 0, topMass = 0;
    float botSumX = 0, botMass = 0;
    float leftMass = 0, rightMass = 0;
    float totalWeight = 0;
    
    for (int y = 0; y < 16; y++) {
        for (int x = 0; x < 16; x++) {
            uint32_t px = rgbaBuffer[y * 16 + x];
            float r = (float)((px >> 24) & 0xFF);
            float g = (float)((px >> 16) & 0xFF);
            float b = (float)((px >> 8) & 0xFF);
            uint8_t a = px & 0xFF;
            
            float w = 0;
            if (hasTransparency) {
                w = (a > 30) ? (float)a : 0;
            } else {
                float lum = 0.299f * r + 0.587f * g + 0.114f * b;
                w = isWhiteBg ? fmaxf(0.0f, 255.0f - lum) : lum;
                if (w < 40.0f) w = 0;
            }
            
            if (w > 30.0f) {
                totalWeight += w;
                if (x < 8) leftMass += w;
                else rightMass += w;
                
                if (y < 8) { // Top half: arrow head and bend direction
                    topSumX += (float)x * w;
                    topMass += w;
                } else {     // Bottom half: arrow stalk
                    botSumX += (float)x * w;
                    botMass += w;
                }
            }
        }
    }
    
    if (totalWeight < 50.0f) return 0;
    
    // Centroid Vector Analysis (Top Centroid vs Bottom Centroid)
    if (topMass > 0 && botMass > 0) {
        float cxTop = topSumX / topMass;
        float cxBot = botSumX / botMass;
        float deltaX = cxTop - cxBot; // Head position relative to stalk
        
        // Negative deltaX = Top bends LEFT relative to stalk
        if (deltaX < -1.5f) return 2; // HUD_LEFT
        if (deltaX < -0.7f) return 4; // HUD_SLIGHT_LEFT
        
        // Positive deltaX = Top bends RIGHT relative to stalk
        if (deltaX > 1.5f) return 3;  // HUD_RIGHT
        if (deltaX > 0.7f) return 5;  // HUD_SLIGHT_RIGHT
        
        return 1; // HUD_STRAIGHT
    } else {
        // Fallback for single-mass or compact symbols: compare left vs right mass
        float diff = (leftMass - rightMass) / totalWeight;
        if (diff > 0.18f) return 2; // HUD_LEFT
        if (diff < -0.18f) return 3; // HUD_RIGHT
        return 1; // HUD_STRAIGHT
    }
    }
}

static uint16_t GVMGetManeuverHUDIcon(id maneuver, NSString **outText) {
    if (!maneuver) return 0;
    NSString *road = GVMGetManeuverInstructionText(maneuver);
    if (outText) *outText = road;

    // 1. Gather all potential text sources
    NSMutableArray *candidates = [NSMutableArray new];
    if (road && road.length > 0) [candidates addObject:road];

    if ([maneuver respondsToSelector:@selector(instructionVariants)]) {
        NSArray *iVars = ((id (*)(id, SEL))objc_msgSend)(maneuver, @selector(instructionVariants));
        if ([iVars isKindOfClass:[NSArray class]]) {
            for (id v in iVars) {
                if ([v isKindOfClass:[NSString class]]) [candidates addObject:v];
            }
        }
    }
    if ([maneuver respondsToSelector:@selector(dashboardInstructionVariants)]) {
        NSArray *dVars = ((id (*)(id, SEL))objc_msgSend)(maneuver, @selector(dashboardInstructionVariants));
        if ([dVars isKindOfClass:[NSArray class]]) {
            for (id v in dVars) {
                if ([v isKindOfClass:[NSString class]]) [candidates addObject:v];
            }
        }
    }
    if ([maneuver respondsToSelector:@selector(notificationInstructionVariants)]) {
        NSArray *nVars = ((id (*)(id, SEL))objc_msgSend)(maneuver, @selector(notificationInstructionVariants));
        if ([nVars isKindOfClass:[NSArray class]]) {
            for (id v in nVars) {
                if ([v isKindOfClass:[NSString class]]) [candidates addObject:v];
            }
        }
    }
    if ([maneuver respondsToSelector:@selector(attributedInstructionVariants)]) {
        NSArray *aVars = ((id (*)(id, SEL))objc_msgSend)(maneuver, @selector(attributedInstructionVariants));
        if ([aVars isKindOfClass:[NSArray class]]) {
            for (id item in aVars) {
                if ([item respondsToSelector:@selector(string)]) {
                    NSString *s = [item performSelector:@selector(string)];
                    if (s && s.length > 0) [candidates addObject:s];
                }
            }
        }
    }
    if ([maneuver respondsToSelector:@selector(dashboardAttributedInstructionVariants)]) {
        NSArray *aVars = ((id (*)(id, SEL))objc_msgSend)(maneuver, @selector(dashboardAttributedInstructionVariants));
        if ([aVars isKindOfClass:[NSArray class]]) {
            for (id item in aVars) {
                if ([item respondsToSelector:@selector(string)]) {
                    NSString *s = [item performSelector:@selector(string)];
                    if (s && s.length > 0) [candidates addObject:s];
                }
            }
        }
    }
    if ([maneuver respondsToSelector:@selector(userInfo)]) {
        id uInfo = ((id (*)(id, SEL))objc_msgSend)(maneuver, @selector(userInfo));
        if ([uInfo isKindOfClass:[NSDictionary class]]) {
            for (id key in [(NSDictionary *)uInfo allKeys]) {
                if ([key isKindOfClass:[NSString class]]) [candidates addObject:key];
            }
            for (id val in [(NSDictionary *)uInfo allValues]) {
                if ([val isKindOfClass:[NSString class]]) [candidates addObject:val];
            }
        } else if (uInfo) {
            // Google Maps ManeuverUserInfo / GMSNavigationStepInfo
            @try {
                id stepInfo = nil;
                if ([uInfo respondsToSelector:@selector(stepInfo)]) {
                    stepInfo = ((id (*)(id, SEL))objc_msgSend)(uInfo, @selector(stepInfo));
                }
                if (stepInfo && [stepInfo respondsToSelector:@selector(maneuver)]) {
                    NSUInteger gmsManeuver = ((NSUInteger (*)(id, SEL))objc_msgSend)(stepInfo, @selector(maneuver));
                    switch (gmsManeuver) {
                        case 5: return 1; // HUD_STRAIGHT
                        case 6: case 12: case 17: case 19: return 2; // HUD_LEFT
                        case 7: case 13: case 18: case 20: return 3; // HUD_RIGHT
                        case 8: case 10: return 4; // HUD_SLIGHT_LEFT
                        case 9: case 11: return 5; // HUD_SLIGHT_RIGHT
                        case 14: case 15: return 6; // HUD_UTURN
                        default: break;
                    }
                }
                NSString *uDesc = [uInfo description];
                if (uDesc && uDesc.length > 0) [candidates addObject:uDesc];
            } @catch (__unused NSException *e) {}
        }
    }

    // Check all candidates for keywords
    for (NSString *cand in candidates) {
        uint16_t icon = GVMMapInstructionTextToMazdaHUD(cand);
        if (icon > 0) return icon;
    }

    // 2. Check Apple CarPlay maneuverType enum
    if ([maneuver respondsToSelector:@selector(maneuverType)]) {
        NSUInteger mType = ((NSUInteger (*)(id, SEL))objc_msgSend)(maneuver, @selector(maneuverType));
        if (mType != 255 && mType != 0) {
            uint16_t icon = GVMMapCarPlayManeuverToMazdaHUD(mType);
            if (icon > 0) return icon;
        }
    }

    // 3. Check symbolSet, dashboardSymbolImageSet, notificationSymbolImageSet, junctionImageSet, symbolImage, etc.
    NSArray *imageProps = @[
        @"symbolSet", @"dashboardSymbolImageSet", @"notificationSymbolImageSet", @"junctionImageSet",
        @"symbolImage", @"dashboardSymbolImage", @"notificationSymbolImage"
    ];
    for (NSString *prop in imageProps) {
        SEL sel = NSSelectorFromString(prop);
        if ([maneuver respondsToSelector:sel]) {
            id rawImg = ((id (*)(id, SEL))objc_msgSend)(maneuver, sel);
            uint16_t icon = GVMDetectIconFromImage(rawImg);
            if (icon > 0) return icon;
        }
    }

    // 4. Check attributedInstructionVariants text attachments
    if ([maneuver respondsToSelector:@selector(attributedInstructionVariants)]) {
        NSArray *attrVariants = ((id (*)(id, SEL))objc_msgSend)(maneuver, @selector(attributedInstructionVariants));
        if ([attrVariants isKindOfClass:[NSArray class]]) {
            for (id item in attrVariants) {
                if ([item isKindOfClass:[NSAttributedString class]]) {
                    NSAttributedString *as = (NSAttributedString *)item;
                    __block uint16_t attIcon = 0;
                    [as enumerateAttributesInRange:NSMakeRange(0, as.length) options:0 usingBlock:^(NSDictionary *attrs, __unused NSRange range, BOOL *stop) {
                        id att = attrs[@"NSAttachment"];
                        if (att && [att respondsToSelector:@selector(image)]) {
                            id attImg = [att performSelector:@selector(image)];
                            uint16_t found = GVMDetectIconFromImage(attImg);
                            if (found > 0) {
                                attIcon = found;
                                *stop = YES;
                            }
                        }
                    }];
                    if (attIcon > 0) return attIcon;
                }
            }
        }
    }

    return 0;
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

    NSString *cleanRoad = GVMExtractRoadName(road);
    if (!cleanRoad || [cleanRoad length] == 0) {
        cleanRoad = road;
    }
    cleanRoad = GVMNormalizeVietnameseForHUD(cleanRoad);

    // State Memory Hysteresis (Drop-frame protection without false straight arrows):
    static uint16_t sLastActiveTurnIcon = 0;
    static NSUInteger sLastTurnDist = 0;
    static time_t sLastTurnTime = 0;
    static char sLastTurnRoad[128] = {0};

    time_t now = time(NULL);

    if (hudIcon >= 2) {
        // Active actionable turn (Left, Right, Roundabout, U-turn)
        sLastActiveTurnIcon = hudIcon;
        sLastTurnDist = finalDist;
        sLastTurnTime = now;
        strncpy(sLastTurnRoad, cleanRoad.UTF8String ?: "", sizeof(sLastTurnRoad) - 1);
        sLastTurnRoad[sizeof(sLastTurnRoad) - 1] = '\0';
    } else if (hudIcon == 0 && finalDist > 0) {
        // If a single frame dropped the icon but vehicle is approaching the turn (< 15s, dist decreasing),
        // preserve the true turn icon rather than showing 0 or lying with Straight (1)!
        if (sLastActiveTurnIcon >= 2 && (now - sLastTurnTime <= 15) &&
            (finalDist <= sLastTurnDist + 50) &&
            (sLastTurnRoad[0] == '\0' || strcmp(sLastTurnRoad, cleanRoad.UTF8String ?: "") == 0)) {
            hudIcon = sLastActiveTurnIcon;
        } else {
            // Never force Straight (1)! Leave as 0 so HUD shows distance and street without misleading arrow.
            hudIcon = 0;
        }
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
