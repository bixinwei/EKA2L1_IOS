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
    NSArray *raw = [root isKindOfClass:[NSDictionary class]] ? root[@"mappings"] : nil;
    if (![raw isKindOfClass:[NSArray class]]) return @[];

    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    for (id item in raw) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSString *identifier = item[@"id"];
        NSString *type = [item[@"type"] isKindOfClass:[NSString class]] ? item[@"type"] : @"button";
        NSArray *tokens = item[@"tokens"];
        NSNumber *x = item[@"x"], *y = item[@"y"];
        if (![identifier isKindOfClass:[NSString class]] || identifier.length == 0 ||
            ![x isKindOfClass:[NSNumber class]] || ![y isKindOfClass:[NSNumber class]]) continue;
        if (![type isEqualToString:@"button"] && ![type isEqualToString:@"dpad"]) continue;
        if ([type isEqualToString:@"dpad"]) {
            NSNumber *size = item[@"size"];
            [out addObject:@{ @"id": identifier, @"type": type,
                              @"x": @(MAX(0.0, MIN(1.0, x.doubleValue))),
                              @"y": @(MAX(0.0, MIN(1.0, y.doubleValue))),
                              @"size": @(MAX(0.04, MIN(0.30, [size isKindOfClass:[NSNumber class]] ? size.doubleValue : 0.13))) }];
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
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{ @"version": @1, @"mappings": mappings ?: @[] }
                                                   options:NSJSONWritingPrettyPrinted error:&error];
    if (data && !error) [data writeToFile:[self pathForUid:uid] atomically:YES];
}

+ (void)removeMappingsForUid:(uint32_t)uid {
    if (uid != 0) [[NSFileManager defaultManager] removeItemAtPath:[self pathForUid:uid] error:nil];
}

@end
