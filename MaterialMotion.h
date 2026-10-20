// MaterialMotion.h
// Material 3 / Material 3 Expressive motion tokens, converted for iOS.
//
// Android springs are (dampingRatio, stiffness) with mass = 1.
// CASpringAnimation takes (mass, stiffness, damping COEFFICIENT), so:
//     damping coefficient c = 2 * zeta * sqrt(k * m)
// iOS "response" (period of the undamped oscillation) is:
//     response = 2*pi / sqrt(k / m)

#import <QuartzCore/QuartzCore.h>
#import <math.h>

typedef struct {
    CGFloat damping;    // damping ratio (zeta)
    CGFloat stiffness;  // N/m, mass = 1
} MMSpring;

typedef NS_ENUM(NSInteger, MMScheme) {
    MMSchemeStandard   = 0,  // low overshoot, safest for full-screen window growth
    MMSchemeExpressive = 1,  // bouncier, Pixel "Expressive" feel
};

// ---- Spatial springs (position, size, corner radius) ----
static inline MMSpring MMSpatialFast(MMScheme s)    { return s == MMSchemeExpressive ? (MMSpring){0.6, 800}  : (MMSpring){0.9, 1400}; }
static inline MMSpring MMSpatialDefault(MMScheme s) { return s == MMSchemeExpressive ? (MMSpring){0.8, 380}  : (MMSpring){0.9, 700};  }
static inline MMSpring MMSpatialSlow(MMScheme s)    { return s == MMSchemeExpressive ? (MMSpring){0.8, 200}  : (MMSpring){0.9, 300};  }

// ---- Effects springs (opacity, color, blur) - always critically damped ----
static inline MMSpring MMEffectsFast(void)    { return (MMSpring){1.0, 3800}; }
static inline MMSpring MMEffectsDefault(void) { return (MMSpring){1.0, 1600}; }
static inline MMSpring MMEffectsSlow(void)    { return (MMSpring){1.0, 800};  }

static inline MMSpring MMScaled(MMSpring s, CGFloat speed) {
    // Scaling stiffness by speed^2 scales the time axis by 1/speed
    // while keeping the damping ratio (the "feel") identical.
    return (MMSpring){ s.damping, s.stiffness * speed * speed };
}

static inline CGFloat MMResponse(MMSpring s) {
    return (CGFloat)(2.0 * M_PI / sqrt((double)s.stiffness));
}

static inline CASpringAnimation *MMSpringAnimation(NSString *keyPath, id from, id to, MMSpring s) {
    CASpringAnimation *a = [CASpringAnimation animationWithKeyPath:keyPath];
    a.mass = 1.0;
    a.stiffness = s.stiffness;
    a.damping = 2.0 * s.damping * sqrt(s.stiffness);
    a.initialVelocity = 0;
    a.fromValue = from;
    a.toValue = to;
    a.duration = a.settlingDuration;
    a.fillMode = kCAFillModeBoth;
    a.removedOnCompletion = YES;
    return a;
}
