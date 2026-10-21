// MaterialMotion v0.2 - Pixel-style (Material 3 / Expressive) app launch motion for SpringBoard.
//
// Layer A: while an app is launching, every CASpringAnimation SpringBoard adds is re-tuned
//          to Material spring values (spatial vs effects picked by key path), and
//          SBFFluidBehaviorSettings is overridden too.
// Layer B: container-transform overlay (icon -> full screen, corner radius morph). ON by default.
//
// Debug log: /var/mobile/Library/Caches/MaterialMotion.log  (open with Filza)

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "MaterialMotion.h"

#define PREFS_DOMAIN "com.example.materialmotion"
static NSString *const kLogPath = @"/var/mobile/Library/Caches/MaterialMotion.log";

static BOOL    gEnabled = YES;
static BOOL    gOverlay = YES;
static int     gScheme  = MMSchemeStandard;
static CGFloat gSpeed   = 1.0;
static CFAbsoluteTime gActiveUntil = 0;
static CFAbsoluteTime gLastTrigger = 0;
static UIWindow *gOverlayWindow = nil;
static int gRewriteLogBudget = 0;
static BOOL gFluidLogged = NO;

// ---------------------------------------------------------------- logging
static void MMLog(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSLog(@"[MaterialMotion] %@", msg);
    NSString *line = [NSString stringWithFormat:@"%@  %@\n", [NSDate date], msg];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:kLogPath];
    if (!fh) {
        [line writeToFile:kLogPath atomically:NO encoding:NSUTF8StringEncoding error:nil];
        return;
    }
    [fh seekToEndOfFile];
    [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [fh closeFile];
}

// ---------------------------------------------------------------- prefs
static void MMLoadPrefs(void) {
    CFPreferencesAppSynchronize(CFSTR(PREFS_DOMAIN));
    NSDictionary *d = (__bridge_transfer NSDictionary *)CFPreferencesCopyMultiple(
        NULL, CFSTR(PREFS_DOMAIN), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    gEnabled = d[@"enabled"] ? [d[@"enabled"] boolValue] : YES;
    gOverlay = d[@"overlay"] ? [d[@"overlay"] boolValue] : YES;
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
    if (!gFluidLogged) { gFluidLogged = YES; MMLog(@"SBFFluidBehaviorSettings override hit"); }
    return MMSpatialDefault((MMScheme)gScheme).damping;
}
- (double)response {
    double orig = %orig;
    if (!MMActive()) return orig;
    return MMResponse(MMScaled(MMSpatialDefault((MMScheme)gScheme), gSpeed));
}
%end

// Catch-all: retune any spring SpringBoard adds during the launch window.
%hook CALayer
- (void)addAnimation:(CAAnimation *)anim forKey:(NSString *)key {
    if (MMActive() && [anim isKindOfClass:[CASpringAnimation class]] && ![key hasPrefix:@"mm."]) {
        CASpringAnimation *sa = (CASpringAnimation *)anim;
        NSString *kp = sa.keyPath ?: @"";
        BOOL effect = [kp isEqualToString:@"opacity"] || [kp hasPrefix:@"backgroundColor"] ||
                      [kp hasPrefix:@"filters"] || [kp hasPrefix:@"backgroundFilters"] ||
                      [kp hasPrefix:@"shadowOpacity"];
        MMSpring s = effect ? MMScaled(MMEffectsDefault(), gSpeed)
                            : MMScaled(MMSpatialDefault((MMScheme)gScheme), gSpeed);
        if (gRewriteLogBudget > 0) {
            gRewriteLogBudget--;
            MMLog(@"retuned spring keyPath=%@ (was k=%.0f c=%.1f)", kp, sa.stiffness, sa.damping);
        }
        sa.mass = 1.0;
        sa.stiffness = s.stiffness;
        sa.damping = 2.0 * s.damping * sqrt(s.stiffness);
        sa.duration = sa.settlingDuration;
    }
    %orig(anim, key);
}
%end

// ---------------------------------------------------------------- Layer B
static CGFloat MMDisplayCornerRadius(void) {
    NSNumber *r = nil;
    @try { r = [UIScreen.mainScreen valueForKey:@"_displayCornerRadius"]; } @catch (id e) {}
    return r ? r.doubleValue : 47.33;
}

static void MMPlayLaunchOverlay(UIView *iconView) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!iconView.window) { MMLog(@"overlay skipped: icon has no window"); return; }

        CGRect start  = [iconView convertRect:iconView.bounds toView:nil];
        CGRect screen = UIScreen.mainScreen.bounds;
        UIView *snap  = [iconView snapshotViewAfterScreenUpdates:NO];
        MMLog(@"overlay start frame=%@", NSStringFromCGRect(start));

        gOverlayWindow = [[UIWindow alloc] initWithFrame:screen];
        gOverlayWindow.windowLevel = UIWindowLevelAlert + 200;
        gOverlayWindow.userInteractionEnabled = NO;
        gOverlayWindow.backgroundColor = UIColor.clearColor;
        gOverlayWindow.hidden = NO;

        UIView *card = [[UIView alloc] initWithFrame:start];
        card.clipsToBounds = YES;
        card.backgroundColor = UIColor.systemBackgroundColor;
        card.layer.cornerCurve = kCACornerCurveContinuous;
        [gOverlayWindow addSubview:card];

        if (snap) {
            snap.frame = CGRectMake((start.size.width  - snap.bounds.size.width)  / 2,
                                    (start.size.height - snap.bounds.size.height) / 2,
                                    snap.bounds.size.width, snap.bounds.size.height);
            [card addSubview:snap];
        }

        MMScheme scheme = (MMScheme)gScheme;
        MMSpring spatial = MMScaled(MMSpatialDefault(scheme), gSpeed);
        MMSpring fxFast  = MMScaled(MMEffectsFast(), gSpeed);
        MMSpring fxDef   = MMScaled(MMEffectsDefault(), gSpeed);

        CGFloat r0 = start.size.width * 0.2237;
        CGFloat r1 = MMDisplayCornerRadius();
        CGRect  endBounds = (CGRect){CGPointZero, screen.size};
        CGPoint startPos  = CGPointMake(CGRectGetMidX(start),  CGRectGetMidY(start));
        CGPoint endPos    = CGPointMake(CGRectGetMidX(screen), CGRectGetMidY(screen));

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

        if (snap) {
            snap.layer.opacity = 0;
            [snap.layer addAnimation:MMSpringAnimation(@"opacity", @1, @0, fxFast) forKey:@"mm.snap"];
        }

        CFTimeInterval delay = b.settlingDuration * 0.45;
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
static BOOL MMLooksLikeAppLaunch(UIView *iconView) {
    if (!iconView) return NO;
    @try {
        if ([iconView respondsToSelector:@selector(isEditing)] &&
            ((BOOL (*)(id, SEL))objc_msgSend)(iconView, @selector(isEditing))) return NO;
        id icon = [iconView valueForKey:@"icon"];
        Class appIcon = NSClassFromString(@"SBApplicationIcon");
        if (icon && appIcon && ![icon isKindOfClass:appIcon]) return NO;   // folders, widgets...
    } @catch (id e) {}
    return YES;
}

static void MMHandleIconTap(UIView *iconView, NSString *source) {
    if (!gEnabled) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - gLastTrigger < 0.5) return;           // debounce overlapping hooks
    if (iconView && !MMLooksLikeAppLaunch(iconView)) return;
    gLastTrigger = now;
    gActiveUntil = now + 1.2;
    gRewriteLogBudget = 8;
    gFluidLogged = NO;
    MMLog(@"TAP detected via %@ (overlay=%d scheme=%d speed=%.2f)", source, gOverlay, gScheme, gSpeed);
    if (gOverlay && iconView) MMPlayLaunchOverlay(iconView);
}

// Find and wrap every "...Tapped..." method with the signature  void m:(id)  on the icon classes.
// This avoids guessing the exact selector name on each iOS 16.x build.
static void MMInstallTapHooks(void) {
    NSArray *names = @[@"SBIconView", @"SBHIconManager", @"SBIconController"];
    int hooked = 0;
    for (NSString *cn in names) {
        Class cls = NSClassFromString(cn);
        if (!cls) { MMLog(@"class %@ NOT FOUND", cn); continue; }
        unsigned int n = 0;
        Method *ms = class_copyMethodList(cls, &n);
        for (unsigned int i = 0; i < n; i++) {
            SEL sel = method_getName(ms[i]);
            NSString *mname = NSStringFromSelector(sel);
            if ([mname.lowercaseString rangeOfString:@"tapped"].location == NSNotFound) continue;
            const char *enc = method_getTypeEncoding(ms[i]);
            MMLog(@"%@ -%@  [%s]", cn, mname, enc ? enc : "?");
            if (!enc || strcmp(enc, "v24@0:8@16") != 0) continue;

            IMP orig = method_getImplementation(ms[i]);
            BOOL selfIsIcon = [cn isEqualToString:@"SBIconView"];
            NSString *label = [NSString stringWithFormat:@"%@ -%@", cn, mname];
            id blk = ^(id slf, id arg) {
                UIView *v = nil;
                if (selfIsIcon) v = [slf isKindOfClass:[UIView class]] ? slf : nil;
                else if ([arg isKindOfClass:[UIView class]]) v = arg;
                MMHandleIconTap(v, label);
                ((void (*)(id, SEL, id))orig)(slf, sel, arg);
            };
            method_setImplementation(ms[i], imp_implementationWithBlock(blk));
            hooked++;
            MMLog(@"  -> hooked");
        }
        free(ms);
    }
    MMLog(@"tap hooks installed: %d", hooked);
}

// ---------------------------------------------------------------- init
%ctor {
    [[NSFileManager defaultManager] removeItemAtPath:kLogPath error:nil];
    MMLoadPrefs();
    MMLog(@"loaded v0.2 in %@ (enabled=%d overlay=%d)", NSProcessInfo.processInfo.processName, gEnabled, gOverlay);
    MMLog(@"SBFFluidBehaviorSettings exists: %d", NSClassFromString(@"SBFFluidBehaviorSettings") != nil);

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        MMPrefsChanged, CFSTR(PREFS_DOMAIN "/ReloadPrefs"), NULL,
        CFNotificationSuspensionBehaviorCoalesce);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ MMInstallTapHooks(); });
}
