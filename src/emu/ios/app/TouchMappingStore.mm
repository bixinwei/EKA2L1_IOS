/*
 * Copyright (c) 2026 EKA2L1 Team.
 * This file is part of EKA2L1 project and is licensed under GPL-3.0-or-later.
 */
#import "TouchMappingStore.h"

@implementation TouchMappingStore

+ (NSString *)pathForUid:(uint32_t)uid {
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *dir = [docs stringByAppendingPathComponent:@"game_settings"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%08X_touch_maps.json", uid]];
}

+ (NSArray<NSDictionary *> *)mappingsForUid:(uint32_t)uid {
    if (uid == 0) return @[];
    NSData *data = [NSData dataWithContentsOfFile:[self pathForUid:uid]];
    if (!data) return @[];
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSDictionary *document = [root isKindOfClass:[NSDictionary class]] ? root : nil;
    const NSInteger version = [document[@"version"] integerValue];
    NSArray *raw = document[@"mappings"];
    if (![raw isKindOfClass:[NSArray class]]) return @[];

    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    for (id item in raw) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSString *identifier = item[@"id"];
        NSString *type = [item[@"type"] isKindOfClass:[NSString class]] ? item[@"type"] : @"button";
        NSArray *tokens = item[@"tokens"];
        NSNumber *x = item[@"x"], *y = item[@"y"];
        if (![identifier isKindOfClass:[NSString class]] || identifier.length == 0) continue;
        if (![type isEqualToString:@"button"] && ![type isEqualToString:@"dpad"] && ![type isEqualToString:@"steering"]) continue;
        if ([type isEqualToString:@"steering"]) {
            NSNumber *centerX = item[@"centerX"], *centerY = item[@"centerY"];
            NSNumber *radius = item[@"radius"], *angle = item[@"angle"];
            if ([centerX isKindOfClass:[NSNumber class]] && [centerY isKindOfClass:[NSNumber class]] &&
                [radius isKindOfClass:[NSNumber class]] && [angle isKindOfClass:[NSNumber class]]) {
                NSInteger sweep = [item[@"sweep"] integerValue] >= 0 ? 1 : -1;
                double deadzone = [item[@"deadzone"] isKindOfClass:[NSNumber class]] ? [item[@"deadzone"] doubleValue] : 0.08;
                [out addObject:@{ @"id": identifier, @"type": type,
                                  @"centerX": @(MAX(0.0, MIN(1.0, centerX.doubleValue))),
                                  @"centerY": @(MAX(0.0, MIN(1.0, centerY.doubleValue))),
                                  @"radius": @(MAX(0.04, MIN(0.65, radius.doubleValue))),
                                  @"angle": angle, @"sweep": @(sweep),
                                  @"deadzone": @(MAX(0.0, MIN(0.35, deadzone))) }];
                continue;
            }

            // Keep version-3 steering records intact until the editor knows the actual game
            // view aspect ratio and can migrate their three points into a true screen-space
            // semicircle. Runtime retains the old path until that one-time migration occurs.
            NSNumber *leftX = item[@"leftX"], *leftY = item[@"leftY"];
            NSNumber *rightX = item[@"rightX"], *rightY = item[@"rightY"];
            if (![leftX isKindOfClass:[NSNumber class]] || ![leftY isKindOfClass:[NSNumber class]] ||
                ![rightX isKindOfClass:[NSNumber class]] || ![rightY isKindOfClass:[NSNumber class]]) continue;
            double deadzone = [item[@"deadzone"] isKindOfClass:[NSNumber class]] ? [item[@"deadzone"] doubleValue] : 0.08;
            [out addObject:@{ @"id": identifier, @"type": type,
                              @"x": @(MAX(0.0, MIN(1.0, x.doubleValue))),
                              @"y": @(MAX(0.0, MIN(1.0, y.doubleValue))),
                              @"leftX": @(MAX(0.0, MIN(1.0, leftX.doubleValue))),
                              @"leftY": @(MAX(0.0, MIN(1.0, leftY.doubleValue))),
                              @"rightX": @(MAX(0.0, MIN(1.0, rightX.doubleValue))),
                              @"rightY": @(MAX(0.0, MIN(1.0, rightY.doubleValue))),
                              @"deadzone": @(MAX(0.0, MIN(0.35, deadzone))) }];
            continue;
        }
        if (![x isKindOfClass:[NSNumber class]] || ![y isKindOfClass:[NSNumber class]]) continue;
        if ([type isEqualToString:@"dpad"]) {
            NSNumber *size = item[@"size"];
            double requestedSize = [size isKindOfClass:[NSNumber class]] ? size.doubleValue : 0.20;
            // Version 1 shipped with a 13% radius. It is too short for many Symbian
            // touchscreen D-pads, so upgrade untouched disks to the responsive 20% default.
            if (version < 2 && requestedSize < 0.20) requestedSize = 0.20;
            [out addObject:@{ @"id": identifier, @"type": type,
                              @"x": @(MAX(0.0, MIN(1.0, x.doubleValue))),
                              @"y": @(MAX(0.0, MIN(1.0, y.doubleValue))),
                              @"size": @(MAX(0.06, MIN(0.45, requestedSize))) }];
            continue;
        }
        if (![tokens isKindOfClass:[NSArray class]] || tokens.count == 0) continue;
        NSMutableArray<NSString *> *cleanTokens = [NSMutableArray array];
        for (id token in tokens) if ([token isKindOfClass:[NSString class]] && [token length]) [cleanTokens addObject:token];
        if (cleanTokens.count == 0) continue;
        [out addObject:@{ @"id": identifier, @"type": @"button", @"tokens": cleanTokens,
                          @"x": @(MAX(0.0, MIN(1.0, x.doubleValue))),
                          @"y": @(MAX(0.0, MIN(1.0, y.doubleValue))) }];
    }
    return out;
}

+ (void)saveMappings:(NSArray<NSDictionary *> *)mappings forUid:(uint32_t)uid {
    if (uid == 0) return;
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{ @"version": @4, @"mappings": mappings ?: @[] }
                                                   options:NSJSONWritingPrettyPrinted error:&error];
    if (data && !error) [data writeToFile:[self pathForUid:uid] atomically:YES];
}

+ (void)removeMappingsForUid:(uint32_t)uid {
    if (uid != 0) [[NSFileManager defaultManager] removeItemAtPath:[self pathForUid:uid] error:nil];
}

@end
