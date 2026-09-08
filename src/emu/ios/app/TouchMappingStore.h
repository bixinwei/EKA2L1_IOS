/*
 * Per-game controller-to-touch mappings. A mapping reserves a controller token
 * (or a token combo) and turns it into a touch at a normalized game-screen point.
 */
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TouchMappingStore : NSObject

// Button mapping: { id, type:"button", tokens:[controller token], x:0..1, y:0..1 }.
// Direction disk:  { id, type:"dpad", x:0..1, y:0..1, size:0.04..0.30 }.
+ (NSArray<NSDictionary *> *)mappingsForUid:(uint32_t)uid;
+ (void)saveMappings:(NSArray<NSDictionary *> *)mappings forUid:(uint32_t)uid;
+ (void)removeMappingsForUid:(uint32_t)uid;

@end

NS_ASSUME_NONNULL_END
