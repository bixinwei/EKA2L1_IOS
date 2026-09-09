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
#import <UIKit/UIKit.h>

// A CAEAGLLayer-backed view that the OpenGL ES driver renders the emulated screen
// into. It reports its drawable (pixel) size to the bridge and forwards touches.
@interface EmulatorView : UIView

// The CAEAGLLayer pointer passed to the emulator graphics driver.
- (void *)glLayer;

// Drawable size in pixels (bounds * contentScaleFactor).
- (int)drawableWidth;
- (int)drawableHeight;

// Set the render scale (drawable pixels per point). 0 = Native (the screen's own scale); otherwise
// clamped to 1.0..3.0. Resizes the GL drawable. Driven by the per-game "Render Resolution" setting.
- (void)setRenderScale:(CGFloat)scale;

// Controller-to-touch mappings share the same guest pointer pool as real UIKit fingers, so a
// mapped press never collides with a physical multi-touch pointer number.
- (void)setVirtualTouch:(NSString *)identifier normalizedX:(CGFloat)x normalizedY:(CGFloat)y active:(BOOL)active;
// A touch-screen game's on-screen joystick must be grabbed at its centre before the finger
// travels outward. This sends that down-then-move sequence using one guest pointer slot.
- (void)setVirtualDirectionTouch:(NSString *)identifier
                         centerX:(CGFloat)centerX centerY:(CGFloat)centerY
                         targetX:(CGFloat)targetX targetY:(CGFloat)targetY;
- (void)releaseAllVirtualTouches;

@end
