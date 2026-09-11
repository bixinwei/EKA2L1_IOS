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
#import "InputManager.h"
#import "KeybindStore.h"
#import "TouchMappingStore.h"
#import <GameController/GameController.h>
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/CADisplayLink.h>
#import <QuartzCore/CAMediaTiming.h>
#include <math.h>

#include <ios/emu_bridge.h>

// Symbian key scancodes (mirror GameControlsView.mm / android Keycode.java).
enum {
    SC_UP = 0x10, SC_DOWN = 0x11, SC_LEFT = 0x0E, SC_RIGHT = 0x0F,
    SC_FIRE = 0xA7, SC_SOFT_LEFT = 0xA4, SC_SOFT_RIGHT = 0xA5,
    SC_PHONE_MENU = 0x94, SC_CLEAR = 0x01,
    // Verified N-Gage action scancodes for the installed N-Gage runtime/game.
    SC_NGAGE_A = 0xE4, SC_NGAGE_B = 0xE5
};

@implementation InputManager {
    NSMutableSet<NSNumber *> *_heldKeys;     // currently-down keyboard GCKeyCodes
    NSMutableSet<NSString *> *_heldCtrl;     // currently-active controller tokens (see readGamepad)
    NSMutableSet<NSNumber *> *_pressed;       // scancodes currently pressed into the guest
    NSSet<NSNumber *> *_prevActive;           // actions active last recompute (edge detection)
    NSArray<NSDictionary *> *_kbBindings;     // { keys:[GCKeyCode], action:EKAAction }
    NSArray<NSDictionary *> *_ctrlBindings;   // { tokens:[NSString], action:EKAAction }
    NSArray<NSDictionary *> *_touchMappings;  // { id, tokens, x, y }, per game only
    CGFloat _leftStickX;
    NSSet<NSString *> *_activeTouchIds;
    NSSet<NSString *> *_activeDirectionIds;
    NSMutableDictionary<NSString *, NSNumber *> *_steeringNeutralSince;
    NSMutableDictionary<NSString *, NSNumber *> *_steeringRenderedAxis;
    NSMutableDictionary<NSString *, NSNumber *> *_steeringLastFrameTime;
    CADisplayLink *_directionDisplayLink;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _heldKeys = [NSMutableSet set];
        _heldCtrl = [NSMutableSet set];
        _pressed = [NSMutableSet set];
        _prevActive = [NSSet set];
        _activeTouchIds = [NSSet set];
        _activeDirectionIds = [NSSet set];
        _steeringNeutralSince = [NSMutableDictionary dictionary];
        _steeringRenderedAxis = [NSMutableDictionary dictionary];
        _steeringLastFrameTime = [NSMutableDictionary dictionary];
        [self reloadBindingsForUid:0];
    }
    return self;
}

// ---- Bindings -------------------------------------------------------------

- (void)reloadBindingsForUid:(uint32_t)uid {
    [self releaseAllMappedTouches];
    _kbBindings = [KeybindStore keyboardBindingsForUid:uid];
    _ctrlBindings = [KeybindStore controllerBindingsForUid:uid];
    _touchMappings = [TouchMappingStore mappingsForUid:uid];
    [self updateDirectionDisplayLinkState];

    // KeybindCaptureViewController temporarily installs its own valueChangedHandler to
    // listen for the button being assigned. GameController exposes only one handler per
    // pad, so reclaim it whenever an edited mapping is saved; otherwise every controller
    // input silently stops reaching the live mapper after the first configuration edit.
    for (GCController *controller in GCController.controllers) {
        [self attachController:controller];
    }
}

- (void)releaseAllMappedTouches {
    [_steeringNeutralSince removeAllObjects];
    [_steeringRenderedAxis removeAllObjects];
    [_steeringLastFrameTime removeAllObjects];
    if (_activeTouchIds.count == 0 && _activeDirectionIds.count == 0) return;
    for (NSDictionary *mapping in _touchMappings) {
        if ([_activeTouchIds containsObject:mapping[@"id"]] || [_activeDirectionIds containsObject:mapping[@"id"]]) {
            [self.delegate inputManagerSetTouchMapping:mapping active:NO];
        }
    }
    _activeTouchIds = [NSSet set];
    _activeDirectionIds = [NSSet set];
}

// Keyboard from the UIKit responder chain. _heldKeys is a plain set, so if GCKeyboard also
// reports the same key the add/remove is idempotent (no double input).
- (BOOL)handleKeyCode:(NSInteger)hidUsage down:(BOOL)down {
    NSNumber *code = @(hidUsage);
    if (down) [_heldKeys addObject:code];
    else      [_heldKeys removeObject:code];
    [self recompute];

    for (NSDictionary *b in _kbBindings) {
        if ([b[@"keys"] containsObject:code]) {
            return YES;
        }
    }
    return NO;
}

static NSArray<NSNumber *> *ScancodesForAction(EKAAction a) {
    switch (a) {
        case EKAActionUp:        return @[@(SC_UP)];
        case EKAActionDown:      return @[@(SC_DOWN)];
        case EKAActionLeft:      return @[@(SC_LEFT)];
        case EKAActionRight:     return @[@(SC_RIGHT)];
        case EKAActionUpLeft:    return @[@(SC_UP), @(SC_LEFT)];
        case EKAActionUpRight:   return @[@(SC_UP), @(SC_RIGHT)];
        case EKAActionDownLeft:  return @[@(SC_DOWN), @(SC_LEFT)];
        case EKAActionDownRight: return @[@(SC_DOWN), @(SC_RIGHT)];
        case EKAActionFire:      return @[@(SC_FIRE)];
        case EKAActionSoftLeft:  return @[@(SC_SOFT_LEFT)];
        case EKAActionSoftRight: return @[@(SC_SOFT_RIGHT)];
        case EKAActionMenu:      return @[];   // UI action, no scancode
        case EKAActionAKey:      return @[@(SC_NGAGE_A)];
        case EKAActionBKey:      return @[@(SC_NGAGE_B)];
        case EKAActionNum0:      return @[@('0')];
        case EKAActionNum1:      return @[@('1')];
        case EKAActionNum2:      return @[@('2')];
        case EKAActionNum3:      return @[@('3')];
        case EKAActionNum4:      return @[@('4')];
        case EKAActionNum5:      return @[@('5')];
        case EKAActionNum6:      return @[@('6')];
        case EKAActionNum7:      return @[@('7')];
        case EKAActionNum8:      return @[@('8')];
        case EKAActionNum9:      return @[@('9')];
        case EKAActionPhoneMenu: return @[@(SC_PHONE_MENU)];
        case EKAActionClear:     return @[@(SC_CLEAR)];
        case EKAActionCount:     return @[];
    }
    return @[];
}

// ---- GameController observation -------------------------------------------

- (void)startObserving {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(onKeyboardConnect:) name:GCKeyboardDidConnectNotification object:nil];
    [nc addObserver:self selector:@selector(onControllerConnect:) name:GCControllerDidConnectNotification object:nil];
    [nc addObserver:self selector:@selector(onControllerDisconnect:) name:GCControllerDidDisconnectNotification object:nil];

    if (GCKeyboard.coalescedKeyboard) {
        [self attachKeyboard:GCKeyboard.coalescedKeyboard];
    }
    for (GCController *c in GCController.controllers) {
        [self attachController:c];
    }

    if (!_directionDisplayLink) {
        _directionDisplayLink = [CADisplayLink displayLinkWithTarget:self
                                                            selector:@selector(onDirectionDisplayLink:)];
        _directionDisplayLink.preferredFramesPerSecond = 60;
        [_directionDisplayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        [self updateDirectionDisplayLinkState];
    }
}

- (void)dealloc {
    [_directionDisplayLink invalidate];
}

- (void)onDirectionDisplayLink:(CADisplayLink *)displayLink {
    (void)displayLink;
    [self updateDirectionTouchesForDisplayFrame];
}

- (BOOL)hasDirectionTouchMapping {
    for (NSDictionary *mapping in _touchMappings) {
        NSString *type = mapping[@"type"];
        if ([type isEqualToString:@"dpad"] || [type isEqualToString:@"steering"]) return YES;
    }
    return NO;
}

- (void)updateDirectionDisplayLinkState {
    _directionDisplayLink.paused = !(self.enabled && !self.menuShown &&
                                     !self.appsListShown && [self hasDirectionTouchMapping]);
}

- (void)onKeyboardConnect:(NSNotification *)note {
    GCKeyboard *kb = note.object;
    if (kb) {
        [self attachKeyboard:kb];
    }
}

- (void)onControllerConnect:(NSNotification *)note {
    GCController *c = note.object;
    if (c) {
        [self attachController:c];
    }
}

- (void)onControllerDisconnect:(NSNotification *)note {
    [_heldCtrl removeAllObjects];
    _leftStickX = 0.0;
    [self releaseAllMappedTouches];
    [self recompute];
}

- (void)attachKeyboard:(GCKeyboard *)keyboard {
    __weak InputManager *weakSelf = self;
    keyboard.keyboardInput.keyChangedHandler = ^(GCKeyboardInput *kbInput, GCControllerButtonInput *key,
                                                 GCKeyCode keyCode, BOOL pressed) {
        InputManager *s = weakSelf;
        if (!s) return;
        NSNumber *code = @((NSInteger)keyCode);
        if (pressed) [s->_heldKeys addObject:code];
        else         [s->_heldKeys removeObject:code];
        [s recompute];
    };
}

- (void)attachController:(GCController *)controller {
    __weak InputManager *weakSelf = self;
    GCExtendedGamepad *pad = controller.extendedGamepad;
    if (!pad) {
        return;
    }
    controller.handlerQueue = dispatch_get_main_queue();
    pad.valueChangedHandler = ^(GCExtendedGamepad *gamepad, GCControllerElement *element) {
        InputManager *s = weakSelf;
        if (!s) return;
        [s readGamepad:gamepad];
        [s recompute];
    };
}

- (void)readGamepad:(GCExtendedGamepad *)gp {
    [_heldCtrl removeAllObjects];
    if (gp.buttonA.isPressed)        [_heldCtrl addObject:@"A"];
    if (gp.buttonB.isPressed)        [_heldCtrl addObject:@"B"];
    if (gp.buttonX.isPressed)        [_heldCtrl addObject:@"X"];
    if (gp.buttonY.isPressed)        [_heldCtrl addObject:@"Y"];
    if (gp.leftShoulder.isPressed)   [_heldCtrl addObject:@"L1"];
    if (gp.rightShoulder.isPressed)  [_heldCtrl addObject:@"R1"];
    if (gp.leftTrigger.isPressed)    [_heldCtrl addObject:@"L2"];
    if (gp.rightTrigger.isPressed)   [_heldCtrl addObject:@"R2"];
    if (gp.buttonMenu.isPressed)     [_heldCtrl addObject:@"MENU"];
    if (gp.buttonOptions && gp.buttonOptions.isPressed) [_heldCtrl addObject:@"MENU"];

    GCControllerDirectionPad *d = gp.dpad;
    if (d.up.isPressed)    [_heldCtrl addObject:@"DP_U"];
    if (d.down.isPressed)  [_heldCtrl addObject:@"DP_D"];
    if (d.left.isPressed)  [_heldCtrl addObject:@"DP_L"];
    if (d.right.isPressed) [_heldCtrl addObject:@"DP_R"];

    const float TH = 0.5f;
    GCControllerDirectionPad *ls = gp.leftThumbstick;
    _leftStickX = MAX(-1.0, MIN(1.0, ls.xAxis.value));
    if (ls.yAxis.value >  TH) [_heldCtrl addObject:@"LS_U"];
    if (ls.yAxis.value < -TH) [_heldCtrl addObject:@"LS_D"];
    if (ls.xAxis.value < -TH) [_heldCtrl addObject:@"LS_L"];
    if (ls.xAxis.value >  TH) [_heldCtrl addObject:@"LS_R"];

    GCControllerDirectionPad *rs = gp.rightThumbstick;
    if (rs.yAxis.value >  TH) [_heldCtrl addObject:@"RS_U"];
    if (rs.yAxis.value < -TH) [_heldCtrl addObject:@"RS_D"];
    if (rs.xAxis.value < -TH) [_heldCtrl addObject:@"RS_L"];
    if (rs.xAxis.value >  TH) [_heldCtrl addObject:@"RS_R"];
}

// ---- Resolve held inputs → actions → guest keys ---------------------------

// All actions currently active given the held keyboard/controller inputs. A binding is
// active when every one of its tokens is held (supports multi-key combos).
- (NSSet<NSNumber *> *)activeActions {
    NSMutableSet<NSNumber *> *active = [NSMutableSet set];

    for (NSDictionary *b in _kbBindings) {
        BOOL all = YES;
        for (NSNumber *k in b[@"keys"]) {
            if (![_heldKeys containsObject:k]) { all = NO; break; }
        }
        if (all && [b[@"keys"] count] > 0) [active addObject:b[@"action"]];
    }
    for (NSDictionary *b in _ctrlBindings) {
        NSArray *tokens = b[@"tokens"];
        // A controller combo assigned to a screen point belongs to touch mapping, not to
        // the legacy phone-key path. This prevents (for example) A from sending both Fire
        // and a virtual touch in a touchscreen game.
        BOOL reservedForTouch = [self controllerBindingIsReservedForTouch:tokens];
        if (reservedForTouch) continue;
        BOOL all = YES;
        for (NSString *t in tokens) {
            if (![_heldCtrl containsObject:t]) { all = NO; break; }
        }
        if (all && tokens.count > 0) [active addObject:b[@"action"]];
    }
    return active;
}

- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled;
    [self recompute];
    [self updateDirectionDisplayLinkState];
}

- (void)setMenuShown:(BOOL)menuShown {
    _menuShown = menuShown;
    [self recompute];
    [self updateDirectionDisplayLinkState];
}

- (void)setAppsListShown:(BOOL)appsListShown {
    _appsListShown = appsListShown;
    [self recompute];
    [self updateDirectionDisplayLinkState];
}

- (BOOL)controllerBindingIsReservedForTouch:(NSArray<NSString *> *)tokens {
    static NSSet<NSString *> *directionTokens;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        directionTokens = [NSSet setWithArray:@[@"DP_U", @"DP_D", @"DP_L", @"DP_R", @"LS_U", @"LS_D", @"LS_L", @"LS_R"]];
    });
    for (NSDictionary *mapping in _touchMappings) {
        if ([mapping[@"type"] isEqualToString:@"dpad"]) {
            for (NSString *token in tokens) if ([directionTokens containsObject:token]) return YES;
        } else if ([mapping[@"type"] isEqualToString:@"steering"]) {
            for (NSString *token in tokens) {
                if ([token isEqualToString:@"LS_L"] || [token isEqualToString:@"LS_R"]) return YES;
            }
        } else if ([mapping[@"tokens"] isEqualToArray:tokens]) {
            return YES;
        }
    }
    return NO;
}

- (NSSet<NSString *> *)activeTouchMappingIds {
    if (!self.enabled || self.menuShown || self.appsListShown) return [NSSet set];
    NSMutableSet<NSString *> *active = [NSMutableSet set];
    for (NSDictionary *mapping in _touchMappings) {
        if ([mapping[@"type"] isEqualToString:@"dpad"]) continue;
        NSArray<NSString *> *tokens = mapping[@"tokens"];
        BOOL all = tokens.count > 0;
        for (NSString *token in tokens) {
            if (![_heldCtrl containsObject:token]) { all = NO; break; }
        }
        if (all) [active addObject:mapping[@"id"]];
    }
    return active;
}

- (CGPoint)directionForHeldController {
    CGFloat x = 0.0, y = 0.0;
    if ([_heldCtrl containsObject:@"DP_L"] || [_heldCtrl containsObject:@"LS_L"]) x -= 1.0;
    if ([_heldCtrl containsObject:@"DP_R"] || [_heldCtrl containsObject:@"LS_R"]) x += 1.0;
    if ([_heldCtrl containsObject:@"DP_U"] || [_heldCtrl containsObject:@"LS_U"]) y -= 1.0;
    if ([_heldCtrl containsObject:@"DP_D"] || [_heldCtrl containsObject:@"LS_D"]) y += 1.0;
    return CGPointMake(MAX(-1.0, MIN(1.0, x)), MAX(-1.0, MIN(1.0, y)));
}

- (NSDictionary *)touchMappingWithId:(NSString *)identifier {
    for (NSDictionary *mapping in _touchMappings) {
        if ([mapping[@"id"] isEqual:identifier]) return mapping;
    }
    return nil;
}

- (void)recomputeMappedButtonTouches {
    NSSet<NSString *> *desired = [self activeTouchMappingIds];
    for (NSString *identifier in desired) {
        if (![_activeTouchIds containsObject:identifier]) {
            NSDictionary *mapping = [self touchMappingWithId:identifier];
            if (mapping) [self.delegate inputManagerSetTouchMapping:mapping active:YES];
        }
    }
    for (NSString *identifier in _activeTouchIds) {
        if (![desired containsObject:identifier]) {
            NSDictionary *mapping = [self touchMappingWithId:identifier];
            if (mapping) [self.delegate inputManagerSetTouchMapping:mapping active:NO];
        }
    }
    _activeTouchIds = desired;
}

- (void)updateDirectionTouchesForDisplayFrame {
    const BOOL canDrive = self.enabled && !self.menuShown && !self.appsListShown;
    const CGPoint direction = canDrive ? [self directionForHeldController] : CGPointZero;
    const CFTimeInterval now = CACurrentMediaTime();
    NSMutableSet<NSString *> *activeDisks = [NSMutableSet set];
    for (NSDictionary *mapping in _touchMappings) {
        NSString *type = mapping[@"type"];
        if ([type isEqualToString:@"steering"]) {
            NSString *identifier = mapping[@"id"];
            const CGFloat deadzone = MAX(0.0, MIN(0.35, [mapping[@"deadzone"] doubleValue]));
            CGFloat targetAxis = canDrive ? _leftStickX : 0.0;
            const BOOL wasActive = [_activeDirectionIds containsObject:identifier];

            if (!canDrive) {
                // Menus, the app list and disabled gameplay must never retain a guest touch.
                [_steeringNeutralSince removeObjectForKey:identifier];
                [_steeringRenderedAxis removeObjectForKey:identifier];
                [_steeringLastFrameTime removeObjectForKey:identifier];
                continue;
            }

            if (fabs(targetAxis) <= deadzone) {
                if (!wasActive) {
                    [_steeringNeutralSince removeObjectForKey:identifier];
                    [_steeringRenderedAxis removeObjectForKey:identifier];
                    [_steeringLastFrameTime removeObjectForKey:identifier];
                    continue;
                }

                // Passing rapidly from full-left to full-right necessarily crosses the
                // stick deadzone. Keep the same guest pointer held at the wheel's neutral
                // point during that crossing; otherwise the game can miss the immediate
                // up/down pair and leave its wheel permanently centred.
                NSNumber *neutralSince = _steeringNeutralSince[identifier];
                if (!neutralSince) {
                    neutralSince = @(now);
                    _steeringNeutralSince[identifier] = neutralSince;
                }
                if (now - neutralSince.doubleValue >= 0.12) {
                    [_steeringNeutralSince removeObjectForKey:identifier];
                    [_steeringRenderedAxis removeObjectForKey:identifier];
                    [_steeringLastFrameTime removeObjectForKey:identifier];
                    continue;
                }
                targetAxis = 0.0;
            } else {
                [_steeringNeutralSince removeObjectForKey:identifier];
                const CGFloat sign = targetAxis < 0.0 ? -1.0 : 1.0;
                const CGFloat magnitude = (fabs(targetAxis) - deadzone) / MAX(0.001, 1.0 - deadzone);
                targetAxis = sign * MAX(0.0, MIN(1.0, magnitude));
            }

            // A real finger does not teleport from neutral to the end of the wheel. Some
            // games consume drag deltas and only apply a fraction of one oversized move,
            // leaving their wheel barely turned even while the stick remains fully held.
            // Approach the requested angle over several display frames so the guest receives
            // the same continuous path as an actual finger sliding along the semicircle.
            CGFloat axis = 0.0;
            NSNumber *renderedValue = _steeringRenderedAxis[identifier];
            NSNumber *lastFrameValue = _steeringLastFrameTime[identifier];
            if (wasActive && renderedValue && lastFrameValue) {
                axis = renderedValue.doubleValue;
                const CFTimeInterval elapsed = MAX(0.0, MIN(1.0 / 30.0, now - lastFrameValue.doubleValue));
                const CGFloat maxStep = 5.0 * elapsed;
                const CGFloat difference = targetAxis - axis;
                if (fabs(difference) <= maxStep) {
                    axis = targetAxis;
                } else {
                    axis += (difference < 0.0 ? -maxStep : maxStep);
                }
            }
            _steeringRenderedAxis[identifier] = @(axis);
            _steeringLastFrameTime[identifier] = @(now);

            if ([mapping[@"radius"] isKindOfClass:[NSNumber class]]) {
                NSMutableDictionary *event = [mapping mutableCopy];
                event[@"steeringAxis"] = @(axis);
                [self.delegate inputManagerSetTouchMapping:event active:YES];
                [activeDisks addObject:identifier];
                continue;
            }

            // Version-3 fallback. Opening the touch editor migrates this record to the
            // centre/radius/orientation representation above.
            const CGFloat t = (axis + 1.0) * 0.5;
            const CGFloat lx = [mapping[@"leftX"] doubleValue], ly = [mapping[@"leftY"] doubleValue];
            const CGFloat cx = [mapping[@"x"] doubleValue], cy = [mapping[@"y"] doubleValue];
            const CGFloat rx = [mapping[@"rightX"] doubleValue], ry = [mapping[@"rightY"] doubleValue];
            // Quadratic Bezier whose midpoint is the calibrated neutral point.
            const CGFloat qx = 2.0 * cx - 0.5 * (lx + rx);
            const CGFloat qy = 2.0 * cy - 0.5 * (ly + ry);
            const CGFloat omt = 1.0 - t;
            NSMutableDictionary *event = [mapping mutableCopy];
            event[@"centerX"] = mapping[@"x"];
            event[@"centerY"] = mapping[@"y"];
            event[@"x"] = @(MAX(0.0, MIN(1.0, omt * omt * lx + 2.0 * omt * t * qx + t * t * rx)));
            event[@"y"] = @(MAX(0.0, MIN(1.0, omt * omt * ly + 2.0 * omt * t * qy + t * t * ry)));
            [self.delegate inputManagerSetTouchMapping:event active:YES];
            [activeDisks addObject:identifier];
            continue;
        }
        if (![type isEqualToString:@"dpad"]) continue;
        if (direction.x == 0.0 && direction.y == 0.0) continue;
        NSMutableDictionary *event = [mapping mutableCopy];
        const CGFloat radius = [mapping[@"size"] doubleValue];
        // Keep the original centre as well as the moved target. Touch-screen joysticks need
        // their first down event at the centre before a move reaches a direction.
        event[@"centerX"] = mapping[@"x"];
        event[@"centerY"] = mapping[@"y"];
        event[@"x"] = @(MAX(0.0, MIN(1.0, [mapping[@"x"] doubleValue] + direction.x * radius)));
        event[@"y"] = @(MAX(0.0, MIN(1.0, [mapping[@"y"] doubleValue] + direction.y * radius)));
        [self.delegate inputManagerSetTouchMapping:event active:YES];
        [activeDisks addObject:mapping[@"id"]];
    }
    for (NSString *identifier in _activeDirectionIds) {
        if (![activeDisks containsObject:identifier]) {
            NSDictionary *mapping = [self touchMappingWithId:identifier];
            if (mapping) [self.delegate inputManagerSetTouchMapping:mapping active:NO];
        }
    }
    _activeDirectionIds = activeDisks;
}

- (void)setScreenRotation:(NSInteger)screenRotation {
    NSInteger normalized = (screenRotation == 90 || screenRotation == 180 || screenRotation == 270) ? screenRotation : 0;
    if (_screenRotation == normalized) return;
    // Drop held hardware input while the presentation rotates. GameController
    // directions are already screen-relative and must not be rotated again.
    [self releaseAll];
    _screenRotation = normalized;
    [self recompute];
}

- (BOOL)action:(EKAAction)a newlyActiveIn:(NSSet<NSNumber *> *)now {
    return [now containsObject:@(a)] && ![_prevActive containsObject:@(a)];
}

- (void)recompute {
    BOOL uiNav = self.menuShown || self.appsListShown;
    NSSet<NSNumber *> *active = (self.enabled || uiNav) ? [self activeActions] : [NSSet set];

    [self recomputeMappedButtonTouches];
    if (!self.enabled || self.menuShown || self.appsListShown) {
        // Do not leave a synthetic finger held until the next display refresh when gameplay
        // stops or a menu takes ownership of the controller.
        [self updateDirectionTouchesForDisplayFrame];
    }

    if (uiNav) {
        // While a menu or the homescreen apps list is up, directions navigate it (move the
        // selection) and Fire confirms, instead of reaching the guest.
        [self releaseAll];
        if ([self action:EKAActionUp newlyActiveIn:active])    [self.delegate inputManagerDidNavigate:-1];
        if ([self action:EKAActionDown newlyActiveIn:active])  [self.delegate inputManagerDidNavigate:+1];
        if ([self action:EKAActionFire newlyActiveIn:active])  [self.delegate inputManagerDidNavigate:0];
        _prevActive = active;
        return;
    }

    // MENU action: open the in-game menu on the rising edge.
    if ([self action:EKAActionMenu newlyActiveIn:active]) {
        [self.delegate inputManagerDidRequestMenu];
    }

    // Desired scancodes = union of every active (non-menu) action's scancodes.
    NSMutableSet<NSNumber *> *desired = [NSMutableSet set];
    for (NSNumber *actNum in active) {
        for (NSNumber *sc in ScancodesForAction((EKAAction)actNum.integerValue)) {
            [desired addObject:sc];
        }
    }


    // Press newly-desired scancodes, release no-longer-desired ones.
    for (NSNumber *sc in desired) {
        if (![_pressed containsObject:sc]) {
            eka2l1::ios::bridge::key(sc.intValue, true);
        }
    }
    for (NSNumber *sc in [_pressed allObjects]) {
        if (![desired containsObject:sc]) {
            eka2l1::ios::bridge::key(sc.intValue, false);
        }
    }
    _pressed = [desired mutableCopy];
    _prevActive = active;
}

- (void)releaseAll {
    for (NSNumber *sc in [_pressed allObjects]) {
        eka2l1::ios::bridge::key(sc.intValue, false);
    }
    [_pressed removeAllObjects];
}

@end
