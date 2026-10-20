// MaterialMotion - Pixel-style (Material 3 / Expressive) app launch motion for SpringBoard.
//
// Layer A: re-tunes SpringBoard's own fluid springs during an app launch so the
//          system animation uses Material damping/stiffness.
// Layer B: (optional, experimental) a "container transform" overlay: icon -> full
//          screen, with corner radius morphing from icon radius to display radius,
//          like the Pixel launcher.
//
// NOTE: SpringBoard classes are private and change between iOS versions.
// Verify every hooked class/selector on your target version with FLEX / class-dump.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "MaterialMotion.h"

#define PREFS_DOMAIN @"com.example.materialmotion"

static BOOL   gEnabled = YES;
static BOOL   gOverlay = NO;
static int    gScheme  = MMSchemeStandard;
static CGFloat gSpeed  = 1.0;                 // 0.5x - 2.0x
static CFAbsoluteTime gActiveUntil = 0;       // spring override only active for a short window after a tap
static UIWindow *gOverlayWindow = nil;

// ---------------------------------------------------------------- prefs
static void MMLoadPrefs(void) {
    CFPreferencesAppSynchronize(CFSTR(PREFS_DOMAIN));
    NSDictionary *d = (__bridge_transfer NSDictionary *)CFPreferencesCopyMultiple(
        NULL, CFSTR(PREFS_DOMAIN), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    gEnabled = d[@"enabled"] ? [d[@"enabled"] boolValue] : YES;
    gOverlay = d[@"overlay"] ? [d[@"overlay"] boolValue] : NO;
    gScheme  = d[@"scheme"]  ? [d[@"scheme"] intValue]   : MMSchemeStandard;
    CGFloat sp = d[@"speed"] ? [d[@"speed"] doubleValue] : 1.0;
    gSpeed = MAX(0.5, MIN(2.0, sp));
}

static void MMPrefsChanged(CFNotificationCenterRef c, void *o, CFStringRef n, const void *obj, CFDictionaryRef u) {
    MMLoadPrefs();
}

static inline BOOL MMActive(void) {
    return gEnabled && CFAbsoluteTimeGetCurrent() < gActiveUntil;
}

// ---------------------------------------------------------------- Layer A
@interface SBFFluidBehaviorSettings : NSObject
@property (nonatomic) double dampingRatio;
@property (nonatomic) double response;
@end

%hook SBFFluidBehaviorSettings
- (double)dampingRatio {
    double orig = %orig;
    if (!MMActive()) return orig;
    return MMSpatialDefault((MMScheme)gScheme).damping;
}
- (double)response {
    double orig = %orig;
    if (!MMActive()) return orig;
    MMSpring s = MMScaled(MMSpatialDefault((MMScheme)gScheme), gSpeed);
    return MMResponse(s);
}
%end

// ---------------------------------------------------------------- Layer B
static CGFloat MMDisplayCornerRadius(void) {
    NSNumber *r = [UIScreen.mainScreen valueForKey:@"_displayCornerRadius"];
    return r ? r.doubleValue : 47.33;
}

static void MMPlayLaunchOverlay(UIView *iconView) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!iconView.window) return;

        CGRect start  = [iconView convertRect:iconView.bounds toView:nil];
        CGRect screen = UIScreen.mainScreen.bounds;
        UIView *snap  = [iconView snapshotViewAfterScreenUpdates:NO];

        gOverlayWindow = [[UIWindow alloc] initWithFrame:screen];
        gOverlayWindow.windowLevel = UIWindowLevelAlert + 200;
        gOverlayWindow.userInteractionEnabled = NO;
        gOverlayWindow.backgroundColor = UIColor.clearColor;
        gOverlayWindow.hidden = NO;

        UIView *card = [[UIView alloc] initWithFrame:start];
        card.clipsToBounds = YES;
        card.backgroundColor = UIColor.systemBackgroundColor;   // M3 "surface"
        card.layer.cornerCurve = kCACornerCurveContinuous;
        [gOverlayWindow addSubview:card];

        snap.frame = CGRectMake((start.size.width  - snap.bounds.size.width)  / 2,
                                (start.size.height - snap.bounds.size.height) / 2,
                                snap.bounds.size.width, snap.bounds.size.height);
        [card addSubview:snap];

        MMScheme scheme = (MMScheme)gScheme;
        MMSpring spatial = MMScaled(MMSpatialDefault(scheme), gSpeed);
        MMSpring fxFast  = MMScaled(MMEffectsFast(), gSpeed);
        MMSpring fxDef   = MMScaled(MMEffectsDefault(), gSpeed);

        CGFloat r0 = start.size.width * 0.2237;     // iOS icon continuous-corner approximation
        CGFloat r1 = MMDisplayCornerRadius();
        CGRect  endBounds = (CGRect){CGPointZero, screen.size};
        CGPoint startPos  = CGPointMake(CGRectGetMidX(start),  CGRectGetMidY(start));
        CGPoint endPos    = CGPointMake(CGRectGetMidX(screen), CGRectGetMidY(screen));

        // Model values = final state, explicit animations provide the motion.
        card.layer.cornerRadius = r1;
        card.layer.bounds       = endBounds;
        card.layer.position     = endPos;

        CASpringAnimation *b = MMSpringAnimation(@"bounds",
            [NSValue valueWithCGRect:(CGRect){CGPointZero, start.size}],
            [NSValue valueWithCGRect:endBounds], spatial);
        CASpringAnimation *p = MMSpringAnimation(@"position",
            [NSValue valueWithCGPoint:startPos], [NSValue valueWithCGPoint:endPos], spatial);
        CASpringAnimation *c = MMSpringAnimation(@"cornerRadius", @(r0), @(r1), spatial);
        [card.layer addAnimation:b forKey:@"mm.bounds"];
        [card.layer addAnimation:p forKey:@"mm.position"];
        [card.layer addAnimation:c forKey:@"mm.radius"];

        // Icon glyph fades out fast (effects spring, no overshoot)
        snap.layer.opacity = 0;
        [snap.layer addAnimation:MMSpringAnimation(@"opacity", @1, @0, fxFast) forKey:@"mm.snap"];

        // Whole card fades once the app window has had time to appear (~45% of settle)
        CFTimeInterval delay = spatial.stiffness > 0 ? b.settlingDuration * 0.45 : 0.2;
        CASpringAnimation *fade = MMSpringAnimation(@"opacity", @1, @0, fxDef);
        fade.beginTime = CACurrentMediaTime() + delay;
        card.layer.opacity = 0;
        [card.layer addAnimation:fade forKey:@"mm.fade"];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                       (int64_t)((delay + fade.duration + 0.1) * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            gOverlayWindow.hidden = YES;
            gOverlayWindow = nil;
        });
    });
}

// ---------------------------------------------------------------- trigger
@interface SBHIconManager : NSObject
@end
@interface SBIconController : NSObject
@end
@interface SBIconView : UIView
@end

static CFAbsoluteTime gLastTrigger = 0;

// Called from every tap hook; debounced so overlapping hooks can't double-fire.
static void MMHandleIconTap(UIView *iconView) {
    if (!gEnabled) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    gActiveUntil = now + 1.2;
    if (now - gLastTrigger < 0.5) return;
    gLastTrigger = now;
    if (gOverlay && [iconView isKindOfClass:UIView.class]) MMPlayLaunchOverlay(iconView);
}

// iOS 16 has moved these around between point releases, so we hook the known
// candidates. Hooking a selector that doesn't exist is a harmless no-op.
%hook SBIconView
- (void)_delegateTapped:(id)arg {
    MMHandleIconTap((UIView *)self);
    %orig;
}
%end

%hook SBHIconManager
- (void)iconTapped:(id)iconView {
    MMHandleIconTap((UIView *)iconView);
    %orig;
}
%end

%hook SBIconController
- (void)iconTapped:(id)iconView {
    MMHandleIconTap((UIView *)iconView);
    %orig;
}
%end

// ---------------------------------------------------------------- init
%ctor {
    MMLoadPrefs();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        MMPrefsChanged, CFSTR(PREFS_DOMAIN "/ReloadPrefs"), NULL,
        CFNotificationSuspensionBehaviorCoalesce);
}
