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
#import "KeybindStore.h"
#import <GameController/GameController.h>

NSString *EKAActionName(EKAAction action) {
    switch (action) {
        case EKAActionUp:        return @"Up";
        case EKAActionDown:      return @"Down";
        case EKAActionLeft:      return @"Left";
        case EKAActionRight:     return @"Right";
        case EKAActionUpLeft:    return @"Up-Left";
        case EKAActionUpRight:   return @"Up-Right";
        case EKAActionDownLeft:  return @"Down-Left";
        case EKAActionDownRight: return @"Down-Right";
        case EKAActionFire:      return @"Fire";
        case EKAActionSoftLeft:  return @"Left Softkey (L)";
        case EKAActionSoftRight: return @"Right Softkey (R)";
        case EKAActionMenu:      return @"Open Menu";
        case EKAActionAKey:      return @"# — N-Gage Remap";
        case EKAActionBKey:      return @"* — N-Gage Remap";
        default:                 return @"?";
    }
}

static NSDictionary *Entry(NSArray *kb, NSArray *ctrl) {
    return @{ @"kb": kb, @"ctrl": ctrl };
}

// Keep phone mappings in named profiles rather than a single anonymous dictionary. The
// legacy `phone` dictionary is migrated in memory and written back the next time a profile
// is edited, so existing users do not lose mappings.
static NSMutableDictionary *EKAEnsurePhoneProfiles(NSMutableDictionary *model) {
    NSMutableDictionary *profiles = [model[@"phoneKeyProfiles"] isKindOfClass:[NSDictionary class]]
        ? [model[@"phoneKeyProfiles"] mutableCopy] : nil;
    if (!profiles) {
        NSDictionary *legacy = [model[@"phone"] isKindOfClass:[NSDictionary class]] ? model[@"phone"] : @{};
        profiles = [@{ @"Default": [legacy mutableCopy] } mutableCopy];
        [model removeObjectForKey:@"phone"];
    }
    if (!profiles.count) profiles[@"Default"] = [NSMutableDictionary dictionary];
    for (NSString *name in [profiles allKeys]) {
        if (![profiles[name] isKindOfClass:[NSDictionary class]]) profiles[name] = [NSMutableDictionary dictionary];
        else profiles[name] = [profiles[name] mutableCopy];
    }
    NSString *active = [model[@"activePhoneKeyProfile"] isKindOfClass:[NSString class]]
        ? model[@"activePhoneKeyProfile"] : nil;
    if (!active.length || !profiles[active]) {
        active = [[profiles.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)] firstObject] ?: @"Default";
    }
    model[@"phoneKeyProfiles"] = profiles;
    model[@"activePhoneKeyProfile"] = active;
    return profiles;
}

static NSInteger EKAPhoneCodeForStoredKey(NSString *key) {
    if ([key isEqualToString:@"menu"]) return 0x94;
    if ([key isEqualToString:@"clear"]) return 0x01;
    if (key.length == 1) {
        unichar c = [key characterAtIndex:0];
        if ((c >= '0' && c <= '9') || c == '*' || c == '#') return c == '#' ? 0x7F : c;
    }
    return key.integerValue;
}

@implementation KeybindStore

+ (NSInteger)maxKeyboardSlots { return 2; }
+ (NSInteger)maxControllerSlots { return 3; }

// ---- Paths / IO -----------------------------------------------------------

+ (NSString *)docs {
    return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
}
+ (NSString *)globalPath {
    return [[self docs] stringByAppendingPathComponent:@"keybinds.json"];
}
+ (NSString *)gamePathForUid:(uint32_t)uid {
    NSString *dir = [[self docs] stringByAppendingPathComponent:@"game_settings"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%08X_keybinds.json", uid]];
}

+ (NSMutableDictionary *)loadModelAtPath:(NSString *)path {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) {
        return nil;
    }
    id obj = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
    if (![obj isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSMutableDictionary *model = obj;
    [self migrateModelIfNeeded:model];
    return model;
}

+ (void)migrateModelIfNeeded:(NSMutableDictionary *)model {
    NSString *actionKey = @(EKAActionAKey).stringValue;
    NSMutableDictionary *entry = model[actionKey];
    if (![entry isKindOfClass:[NSDictionary class]]) {
        return;
    }

    NSMutableArray *kb = entry[@"kb"];
    NSArray *ctrl = entry[@"ctrl"];
    if (![kb isKindOfClass:[NSArray class]] || kb.count != 2 || ![ctrl isKindOfClass:[NSArray class]]) {
        return;
    }

    NSArray *spaceSlot = kb[0];
    NSArray *oldZeroSlot = kb[1];
    BOOL isOldDefault =
        [spaceSlot isEqualToArray:@[@((NSInteger)GCKeyCodeSpacebar)]] &&
        [oldZeroSlot isEqualToArray:@[@((NSInteger)GCKeyCodeZero)]] &&
        [ctrl isEqualToArray:@[@[@"X"]]];

    if (isOldDefault) {
        kb[1] = @[@((NSInteger)GCKeyCodeLeftShift), @((NSInteger)GCKeyCodeThree)];
    }
}

+ (void)writeModel:(NSDictionary *)model toPath:(NSString *)path {
    NSData *data = [NSJSONSerialization dataWithJSONObject:model options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToFile:path atomically:YES];
}

+ (NSMutableDictionary *)mutableCopyOf:(NSDictionary *)model {
    NSData *data = [NSJSONSerialization dataWithJSONObject:model options:0 error:nil];
    return [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
}

// ---- Models ---------------------------------------------------------------

+ (NSMutableDictionary *)defaultModel {
    NSMutableDictionary *m = [NSMutableDictionary dictionary];
#define KC(x) @((NSInteger)(x))
    m[@(EKAActionUp).stringValue]    = Entry(@[@[KC(GCKeyCodeKeyW)], @[KC(GCKeyCodeUpArrow)]],    @[@[@"DP_U"],@[@"LS_U"],@[@"RS_U"]]);
    m[@(EKAActionDown).stringValue]  = Entry(@[@[KC(GCKeyCodeKeyS)], @[KC(GCKeyCodeDownArrow)]],  @[@[@"DP_D"],@[@"LS_D"],@[@"RS_D"]]);
    m[@(EKAActionLeft).stringValue]  = Entry(@[@[KC(GCKeyCodeKeyA)], @[KC(GCKeyCodeLeftArrow)]],  @[@[@"DP_L"],@[@"LS_L"],@[@"RS_L"]]);
    m[@(EKAActionRight).stringValue] = Entry(@[@[KC(GCKeyCodeKeyD)], @[KC(GCKeyCodeRightArrow)]], @[@[@"DP_R"],@[@"LS_R"],@[@"RS_R"]]);
    m[@(EKAActionUpLeft).stringValue]    = Entry(@[], @[]);
    m[@(EKAActionUpRight).stringValue]   = Entry(@[], @[]);
    m[@(EKAActionDownLeft).stringValue]  = Entry(@[], @[]);
    m[@(EKAActionDownRight).stringValue] = Entry(@[], @[]);
    m[@(EKAActionFire).stringValue]      = Entry(@[@[KC(GCKeyCodeReturnOrEnter)]], @[@[@"A"]]);
    m[@(EKAActionSoftLeft).stringValue]  = Entry(@[@[KC(GCKeyCodeKeyF)]], @[@[@"L1"]]);
    m[@(EKAActionSoftRight).stringValue] = Entry(@[@[KC(GCKeyCodeKeyJ)]], @[@[@"R1"]]);
    m[@(EKAActionMenu).stringValue]      = Entry(@[@[KC(GCKeyCodeEscape)]], @[@[@"MENU"]]);
    // N-Gage helper #: keyboard Space + # (Shift+3), controller X (keeps Fire on A).
    m[@(EKAActionAKey).stringValue]      = Entry(@[@[KC(GCKeyCodeSpacebar)], @[KC(GCKeyCodeLeftShift), KC(GCKeyCodeThree)]], @[@[@"X"]]);
    // N-Gage helper *: same scancode as Android's keypad * overlay, keyboard keypad-* + X,
    // controller B.
    m[@(EKAActionBKey).stringValue]      = Entry(@[@[KC(GCKeyCodeKeypadAsterisk)], @[KC(GCKeyCodeKeyX)]], @[@[@"B"]]);
#undef KC
    return m;
}

+ (NSMutableDictionary *)globalModel {
    return [self loadModelAtPath:[self globalPath]] ?: [self defaultModel];
}

+ (BOOL)hasGameOverrideForUid:(uint32_t)uid {
    return uid != 0 && [[NSFileManager defaultManager] fileExistsAtPath:[self gamePathForUid:uid]];
}

+ (NSMutableDictionary *)effectiveModelForUid:(uint32_t)uid {
    if ([self hasGameOverrideForUid:uid]) {
        NSMutableDictionary *g = [self loadModelAtPath:[self gamePathForUid:uid]];
        if (g) return g;
    }
    return [self globalModel];
}

+ (NSMutableDictionary *)editingModelForUid:(uint32_t)uid {
    if ([self hasGameOverrideForUid:uid]) {
        NSMutableDictionary *g = [self loadModelAtPath:[self gamePathForUid:uid]];
        if (g) return g;
    }
    return [self mutableCopyOf:[self globalModel]];
}

+ (void)saveModel:(NSDictionary *)model forUid:(uint32_t)uid {
    [self writeModel:model toPath:(uid == 0 ? [self globalPath] : [self gamePathForUid:uid])];
}

+ (void)resetForUid:(uint32_t)uid {
    [[NSFileManager defaultManager] removeItemAtPath:(uid == 0 ? [self globalPath] : [self gamePathForUid:uid]) error:nil];
}

// ---- Flatten for InputManager ---------------------------------------------

+ (NSArray<NSDictionary *> *)flatten:(NSString *)slotKey out:(NSString *)outKey forUid:(uint32_t)uid {
    NSDictionary *model = [self effectiveModelForUid:uid];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *actKey in model) {
        NSDictionary *entry = [model[actKey] isKindOfClass:[NSDictionary class]] ? model[actKey] : nil;
        NSArray *slots = [entry[slotKey] isKindOfClass:[NSArray class]] ? entry[slotKey] : nil;
        if (!slots) continue;
        EKAAction act = (EKAAction)actKey.integerValue;
        if (act < EKAActionUp || act >= EKAActionCount) continue;
        for (NSArray *slot in slots) {
            if ([slot count] > 0) {
                [out addObject:@{ outKey: slot, @"action": @(act) }];
            }
        }
    }
    return out;
}

+ (NSArray<NSDictionary *> *)keyboardBindingsForUid:(uint32_t)uid {
    return [self flatten:@"kb" out:@"keys" forUid:uid];
}
+ (NSArray<NSDictionary *> *)controllerBindingsForUid:(uint32_t)uid {
    return [self flatten:@"ctrl" out:@"tokens" forUid:uid];
}

+ (NSArray<NSDictionary *> *)phoneBindingsForUid:(uint32_t)uid {
    NSDictionary *phone = [self phoneBindingMapForUid:uid profileName:nil];
    NSMutableArray *out = [NSMutableArray array];
    [phone enumerateKeysAndObjectsUsingBlock:^(NSString *code, id value, BOOL *stop) {
        if ([value isKindOfClass:[NSArray class]] && [value count]) {
            [out addObject:@{ @"code": @(EKAPhoneCodeForStoredKey(code)), @"tokens": value }];
        }
    }];
    return out;
}

+ (NSArray<NSString *> *)phoneKeyProfileNamesForUid:(uint32_t)uid {
    NSMutableDictionary *model = [self effectiveModelForUid:uid];
    return [[EKAEnsurePhoneProfiles(model).allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)] copy];
}

+ (NSString *)activePhoneKeyProfileForUid:(uint32_t)uid {
    NSMutableDictionary *model = [self effectiveModelForUid:uid];
    EKAEnsurePhoneProfiles(model);
    return model[@"activePhoneKeyProfile"];
}

+ (void)setActivePhoneKeyProfile:(NSString *)name forUid:(uint32_t)uid {
    NSMutableDictionary *model = [self editingModelForUid:uid];
    NSMutableDictionary *profiles = EKAEnsurePhoneProfiles(model);
    if (name.length && profiles[name]) {
        model[@"activePhoneKeyProfile"] = name;
        [self saveModel:model forUid:uid];
    }
}

+ (NSMutableDictionary *)phoneBindingMapForUid:(uint32_t)uid profileName:(NSString *)name {
    NSMutableDictionary *model = [self effectiveModelForUid:uid];
    NSMutableDictionary *profiles = EKAEnsurePhoneProfiles(model);
    NSString *selected = name.length && profiles[name] ? name : model[@"activePhoneKeyProfile"];
    return [profiles[selected] mutableCopy] ?: [NSMutableDictionary dictionary];
}

+ (void)savePhoneBindingMap:(NSDictionary *)bindings profileName:(NSString *)name forUid:(uint32_t)uid {
    if (!name.length || ![bindings isKindOfClass:[NSDictionary class]]) return;
    NSMutableDictionary *model = [self editingModelForUid:uid];
    NSMutableDictionary *profiles = EKAEnsurePhoneProfiles(model);
    profiles[name] = [bindings mutableCopy];
    model[@"phoneKeyProfiles"] = profiles;
    if (!model[@"activePhoneKeyProfile"]) model[@"activePhoneKeyProfile"] = name;
    [self saveModel:model forUid:uid];
}

+ (BOOL)createPhoneKeyProfile:(NSString *)name copyingProfile:(NSString *)sourceName forUid:(uint32_t)uid {
    NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!trimmed.length) return NO;
    NSMutableDictionary *model = [self editingModelForUid:uid];
    NSMutableDictionary *profiles = EKAEnsurePhoneProfiles(model);
    if (profiles[trimmed]) return NO;
    NSString *source = sourceName.length && profiles[sourceName] ? sourceName : model[@"activePhoneKeyProfile"];
    profiles[trimmed] = [profiles[source] mutableCopy] ?: [NSMutableDictionary dictionary];
    model[@"phoneKeyProfiles"] = profiles;
    model[@"activePhoneKeyProfile"] = trimmed;
    [self saveModel:model forUid:uid];
    return YES;
}

+ (BOOL)deletePhoneKeyProfile:(NSString *)name forUid:(uint32_t)uid {
    NSMutableDictionary *model = [self editingModelForUid:uid];
    NSMutableDictionary *profiles = EKAEnsurePhoneProfiles(model);
    if (!profiles[name] || profiles.count <= 1) return NO;
    [profiles removeObjectForKey:name];
    if ([model[@"activePhoneKeyProfile"] isEqualToString:name]) {
        model[@"activePhoneKeyProfile"] = [[profiles.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)] firstObject];
    }
    model[@"phoneKeyProfiles"] = profiles;
    [self saveModel:model forUid:uid];
    return YES;
}

// ---- Display names --------------------------------------------------------

+ (NSString *)keyNameForCode:(NSInteger)c {
    if (c >= 0x04 && c <= 0x1D) return [NSString stringWithFormat:@"%c", (char)('A' + (c - 0x04))];
    if (c >= 0x1E && c <= 0x26) return [NSString stringWithFormat:@"%c", (char)('1' + (c - 0x1E))];
    switch (c) {
        case 0x27: return @"0";
        case 0x28: return @"Enter";
        case 0x29: return @"Esc";
        case 0x2A: return @"Backspace";
        case 0x2B: return @"Tab";
        case 0x2C: return @"Space";
        case 0x55: return @"Keypad *";
        case 0x4F: return @"→";
        case 0x50: return @"←";
        case 0x51: return @"↓";
        case 0x52: return @"↑";
        case 0xE0: return @"L-Ctrl";  case 0xE4: return @"R-Ctrl";
        case 0xE1: return @"Shift";   case 0xE5: return @"R-Shift";
        case 0xE2: return @"Alt";     case 0xE6: return @"R-Alt";
        case 0xE3: return @"Cmd";     case 0xE7: return @"R-Cmd";
        default:   return [NSString stringWithFormat:@"Key 0x%lX", (long)c];
    }
}

+ (NSString *)controllerNameForToken:(NSString *)t {
    static NSDictionary *names = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @{ @"A": @"A / ✕", @"B": @"B / ◯", @"X": @"X / ▢", @"Y": @"Y / △",
                   @"L1": @"L1 / LB", @"R1": @"R1 / RB", @"L2": @"L2 / LT", @"R2": @"R2 / RT",
                   @"MENU": @"Options / Start",
                   @"DP_U": @"D-pad ↑", @"DP_D": @"D-pad ↓", @"DP_L": @"D-pad ←", @"DP_R": @"D-pad →",
                   @"LS_U": @"L-stick ↑", @"LS_D": @"L-stick ↓", @"LS_L": @"L-stick ←", @"LS_R": @"L-stick →",
                   @"RS_U": @"R-stick ↑", @"RS_D": @"R-stick ↓", @"RS_L": @"R-stick ←", @"RS_R": @"R-stick →" };
    });
    return names[t] ?: t;
}

+ (NSString *)keyComboName:(NSArray<NSNumber *> *)codes {
    NSMutableArray *parts = [NSMutableArray array];
    for (NSNumber *c in codes) [parts addObject:[self keyNameForCode:c.integerValue]];
    return [parts componentsJoinedByString:@"+"];
}

+ (NSString *)controllerComboName:(NSArray<NSString *> *)tokens {
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *t in tokens) [parts addObject:[self controllerNameForToken:t]];
    return [parts componentsJoinedByString:@"+"];
}

@end
