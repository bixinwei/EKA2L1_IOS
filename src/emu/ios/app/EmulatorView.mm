/*
 * Copyright (c) 2024 EKA2L1 Team.
 *
 * This file is part of EKA2L1 project.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */
#import "EmulatorView.h"
#import <QuartzCore/CAEAGLLayer.h>

#include <ios/emu_bridge.h>

@implementation EmulatorView {
    int _lastWidth;
    int _lastHeight;

    // Maps each active UITouch to a small, contiguous pointer index (0, 1, 2…). Symbian's
    // advanced pointer events carry a PointerNumber that the guest validates against the
    // (small) number of pointers a window enabled; a window that enabled only the primary
    // pointer rejects any event whose PointerNumber != 0 with KErrArgument. Passing the raw
    // UITouch address (its low byte) as the id therefore made touch work only when that byte
    // happened to be 0 — the intermittent "touch is dead until I rotate a few times" bug.
    NSMapTable<UITouch *, NSNumber *> *_touchSlots;
    NSMutableDictionary<NSString *, NSNumber *> *_virtualTouchSlots;
    NSMutableDictionary<NSString *, NSValue *> *_virtualTouchPositions;
}

+ (Class)layerClass {
    return [CAEAGLLayer class];
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        const CGFloat scale = [UIScreen mainScreen].scale;
        self.contentScaleFactor = scale;
        self.multipleTouchEnabled = YES;
        self.opaque = YES;

        // Configure the CAEAGLLayer here, on the main thread, before the GL driver's
        // background thread binds a renderbuffer to it. Configuring the layer from the
        // render thread can leave Core Animation without a valid drawable to composite.
        CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.layer;
        eaglLayer.opaque = YES;
        eaglLayer.contentsScale = scale;
        eaglLayer.drawableProperties = @{
            kEAGLDrawablePropertyRetainedBacking : @(NO),
            kEAGLDrawablePropertyColorFormat : kEAGLColorFormatRGBA8
        };

        _lastWidth = 0;
        _lastHeight = 0;
        _touchSlots = [NSMapTable weakToStrongObjectsMapTable];
        _virtualTouchSlots = [NSMutableDictionary dictionary];
        _virtualTouchPositions = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void *)glLayer {
    return (__bridge void *)self.layer;
}

- (int)drawableWidth {
    return (int)(self.bounds.size.width * self.contentScaleFactor);
}

- (int)drawableHeight {
    return (int)(self.bounds.size.height * self.contentScaleFactor);
}

- (void)setRenderScale:(CGFloat)scale {
    // 0 (or negative) means "Native" — match the screen's own scale; otherwise clamp to 1x..3x.
    const CGFloat native = [UIScreen mainScreen].scale;
    const CGFloat s = (scale <= 0.0) ? native : MAX(0.5, MIN(3.0, scale));
    if (s == self.contentScaleFactor) {
        return;
    }
    // contentScaleFactor drives drawableWidth/Height AND the touch-coord mapping, and contentsScale
    // sizes the EAGL renderbuffer — keep them equal so everything stays consistent. setNeedsLayout
    // makes layoutSubviews re-run, which notices the new drawable size and calls surface_changed
    // (the GL driver re-acquires the renderbuffer at the new size — the same path rotation uses).
    self.contentScaleFactor = s;
    ((CAEAGLLayer *)self.layer).contentsScale = s;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    const int w = [self drawableWidth];
    const int h = [self drawableHeight];

    if ((w != _lastWidth) || (h != _lastHeight)) {
        _lastWidth = w;
        _lastHeight = h;

        if (eka2l1::ios::bridge::is_running()) {
            eka2l1::ios::bridge::surface_changed([self glLayer], w, h);
        }
    }
}

// ---- Touch handling -------------------------------------------------------
// Convert a UIKit touch into the emulator's framebuffer pixel coordinate space
// (the launcher draws the guest screen into the full drawable).

// Assign the lowest free pointer index to a new touch. Guests reject events whose
// PointerNumber exceeds the number of pointers they enabled (see _touchSlots above), so the
// primary touch must be 0 and extra concurrent touches must be small contiguous values.
- (int)allocateSlotForTouch:(UITouch *)touch {
    NSNumber *existing = [_touchSlots objectForKey:touch];
    if (existing) {
        return existing.intValue;
    }
    NSMutableIndexSet *used = [NSMutableIndexSet indexSet];
    for (UITouch *t in _touchSlots) {
        [used addIndex:[[_touchSlots objectForKey:t] unsignedIntegerValue]];
    }
    for (NSNumber *slot in _virtualTouchSlots.allValues) {
        [used addIndex:slot.unsignedIntegerValue];
    }
    int slot = 0;
    while ([used containsIndex:(NSUInteger)slot]) {
        slot++;
    }
    [_touchSlots setObject:@(slot) forKey:touch];
    return slot;
}

- (int)allocateSlotForVirtualTouch:(NSString *)identifier {
    NSNumber *existing = _virtualTouchSlots[identifier];
    if (existing) return existing.intValue;
    NSMutableIndexSet *used = [NSMutableIndexSet indexSet];
    for (UITouch *touch in _touchSlots) [used addIndex:[[_touchSlots objectForKey:touch] unsignedIntegerValue]];
    for (NSNumber *slot in _virtualTouchSlots.allValues) [used addIndex:slot.unsignedIntegerValue];
    NSUInteger slot = 0;
    while ([used containsIndex:slot]) slot++;
    _virtualTouchSlots[identifier] = @(slot);
    return (int)slot;
}

- (void)setVirtualTouch:(NSString *)identifier normalizedX:(CGFloat)x normalizedY:(CGFloat)y active:(BOOL)active {
    if (identifier.length == 0 || !eka2l1::ios::bridge::is_running()) return;
    NSNumber *existing = _virtualTouchSlots[identifier];
    if (!active && !existing) return;
    const BOOL wasActive = (existing != nil);
    const int pointerId = active ? [self allocateSlotForVirtualTouch:identifier] : existing.intValue;
    const CGFloat scale = self.contentScaleFactor;
    int px = (int)(MAX(0.0, MIN(1.0, x)) * self.bounds.size.width * scale);
    int py = (int)(MAX(0.0, MIN(1.0, y)) * self.bounds.size.height * scale);
    if (!active) {
        NSValue *lastPosition = _virtualTouchPositions[identifier];
        if (lastPosition) {
            const CGPoint point = lastPosition.CGPointValue;
            px = (int)point.x;
            py = (int)point.y;
        }
    }
    const eka2l1::ios::bridge::touch_action action = !active ? eka2l1::ios::bridge::touch_action_up
        : (wasActive ? eka2l1::ios::bridge::touch_action_move : eka2l1::ios::bridge::touch_action_down);
    eka2l1::ios::bridge::touch(px, py, action, pointerId);
    if (active) {
        _virtualTouchPositions[identifier] = [NSValue valueWithCGPoint:CGPointMake(px, py)];
    } else {
        [_virtualTouchSlots removeObjectForKey:identifier];
        [_virtualTouchPositions removeObjectForKey:identifier];
    }
}

- (void)setVirtualDirectionTouch:(NSString *)identifier
                         centerX:(CGFloat)centerX centerY:(CGFloat)centerY
                         targetX:(CGFloat)targetX targetY:(CGFloat)targetY {
    if (identifier.length == 0 || !eka2l1::ios::bridge::is_running()) return;

    NSNumber *existing = _virtualTouchSlots[identifier];
    const int pointerId = [self allocateSlotForVirtualTouch:identifier];
    const CGFloat scale = self.contentScaleFactor;
    const CGFloat width = self.bounds.size.width * scale;
    const CGFloat height = self.bounds.size.height * scale;
    const int centerPX = (int)(MAX(0.0, MIN(1.0, centerX)) * width);
    const int centerPY = (int)(MAX(0.0, MIN(1.0, centerY)) * height);
    const int targetPX = (int)(MAX(0.0, MIN(1.0, targetX)) * width);
    const int targetPY = (int)(MAX(0.0, MIN(1.0, targetY)) * height);
    // Mirror GameControlsView's real-finger joystick: capture the game's joystick at its
    // centre first, then move that same pointer on the following display frame. InputManager
    // deliberately calls this method from a display-linked state machine, so a new pointer's
    // down and move can never be collapsed into one controller callback.
    if (!existing) {
        eka2l1::ios::bridge::touch(centerPX, centerPY, eka2l1::ios::bridge::touch_action_down, pointerId);
        _virtualTouchPositions[identifier] = [NSValue valueWithCGPoint:CGPointMake(centerPX, centerPY)];
        return;
    }

    const CGPoint lastPosition = [_virtualTouchPositions[identifier] CGPointValue];
    if ((int)lastPosition.x == targetPX && (int)lastPosition.y == targetPY) return;
    eka2l1::ios::bridge::touch(targetPX, targetPY, eka2l1::ios::bridge::touch_action_move, pointerId);
    _virtualTouchPositions[identifier] = [NSValue valueWithCGPoint:CGPointMake(targetPX, targetPY)];
}

- (void)releaseAllVirtualTouches {
    for (NSString *identifier in _virtualTouchSlots.allKeys.copy) {
        NSNumber *slot = _virtualTouchSlots[identifier];
        const CGPoint point = [_virtualTouchPositions[identifier] CGPointValue];
        eka2l1::ios::bridge::touch((int)point.x, (int)point.y,
                                   eka2l1::ios::bridge::touch_action_up, slot.intValue);
    }
    [_virtualTouchSlots removeAllObjects];
    [_virtualTouchPositions removeAllObjects];
}

- (void)dispatchTouches:(NSSet<UITouch *> *)touches action:(eka2l1::ios::bridge::touch_action)action {
    const CGFloat scale = self.contentScaleFactor;
    const BOOL isEnd = (action == eka2l1::ios::bridge::touch_action_up);
    for (UITouch *touch in touches) {
        CGPoint p = [touch locationInView:self];
        int x = (int)(p.x * scale);
        int y = (int)(p.y * scale);
        int pointerId = [self allocateSlotForTouch:touch];
        eka2l1::ios::bridge::touch(x, y, action, pointerId);
        if (isEnd) {
            [_touchSlots removeObjectForKey:touch];
        }
    }
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self dispatchTouches:touches action:eka2l1::ios::bridge::touch_action_down];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self dispatchTouches:touches action:eka2l1::ios::bridge::touch_action_move];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self dispatchTouches:touches action:eka2l1::ios::bridge::touch_action_up];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self dispatchTouches:touches action:eka2l1::ios::bridge::touch_action_up];
}

@end
