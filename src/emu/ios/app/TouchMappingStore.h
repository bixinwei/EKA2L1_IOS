/*
 * Per-game controller-to-touch mappings. A mapping reserves a controller token
 * (or a token combo) and turns it into a touch at a normalized game-screen point.
 */
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TouchMappingStore : NSObject

// Each mapping is { id: UUID string, tokens: [controller token], x: 0..1, y: 0..1 }.
+ (NSArray<NSDictionary *> *)mappingsForUid:(uint32_t)uid;
+ (void)saveMappings:(NSArray<NSDictionary *> *)mappings forUid:(uint32_t)uid;
+ (void)removeMappingsForUid:(uint32_t)uid;

@end

NS_ASSUME_NONNULL_END
