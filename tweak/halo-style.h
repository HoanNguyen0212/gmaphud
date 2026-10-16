#import <UIKit/UIKit.h>

// Halo identity tokens shared by the bubble and the settings menu.
enum {
    GVMHaloInk950=0x07090C, GVMHaloInk900=0x0D1117, GVMHaloInk800=0x151B23, GVMHaloInk700=0x1F2732,
    GVMHaloInk600=0x2A3340, GVMHaloInk400=0x7C8797, GVMHaloInk200=0xB7C0CC, GVMHaloInk050=0xF2F5F9,
    GVMHaloIce=0xDCE4EE, GVMHaloAmber=0xFFB938, GVMHaloSignal=0xFF4D4F, GVMHaloSignRed=0xE2231A
};
UIColor *GVMHaloColor(uint32_t rgb, CGFloat alpha);
uint32_t GVMHaloSourceColor(NSUInteger sourceID);
NSString *GVMHaloSourceTag(NSUInteger sourceID);

// Saira Condensed Bold for numbers, Saira for labels; both ship under /usr/share/gmaphud/fonts.
void GVMHaloRegisterFonts(void);
UIFont *GVMHaloNumberFont(CGFloat size);
UIFont *GVMHaloFont(CGFloat size, UIFontWeight weight);
NSAttributedString *GVMHaloText(NSString *text, UIFont *font, UIColor *color, CGFloat tracking);
// Sign artwork is a sticker image in /usr/share/gmaphud/gmaphud (nil when the type has none).
UIImage *GVMHaloSignArtwork(NSUInteger type, NSNumber *value);
// Draws sticker artwork so the sign, not the whole image, spans `diameter` around `centre`; the image
// reaches a little beyond that circle for its shadow.
void GVMHaloDrawSticker(UIImage *image, CGPoint centre, CGFloat diameter);
// A road sign of `diameter` around `centre`: its sticker, or a dark disc with a camera or warning
// symbol when the type has no artwork.
void GVMHaloDrawSign(NSUInteger type, NSNumber *value, CGPoint centre, CGFloat diameter);
// The distance tag under a sign or the lane strip: an 18-point pill centred on `centreX` from `top`,
// filled left to right by `progress`. Draws nothing when there is no distance.
void GVMHaloDrawDistanceTag(CGFloat centreX, CGFloat top, id meters, CGFloat progress);
