/*
 * Per-game controller-to-touch mappings. A mapping reserves a controller token
 * (or a token combo) and turns it into a touch at a normalized game-screen point.
 */
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TouchMappingStore : NSObject

// Button mapping: { id, type:"button", tokens:[controller token], x:0..1, y:0..1 }.
// Direction disk:  { id, type:"dpad", x:0..1, y:0..1, size:0.06..0.45 }.
// Steering wheel: { id, type:"steering", x/y neutral, leftX/leftY full-left,
//                   rightX/rightY full-right, deadzone:0..0.35 }.
+ (NSArray<NSDictionary *> *)mappingsForUid:(uint32_t)uid;
+ (void)saveMappings:(NSArray<NSDictionary *> *)mappings forUid:(uint32_t)uid;
+ (void)removeMappingsForUid:(uint32_t)uid;

@end

NS_ASSUME_NONNULL_END
