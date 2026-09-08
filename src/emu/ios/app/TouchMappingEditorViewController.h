/* Controller-to-touch editor, modelled after mobile controller overlay mappers. */
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TouchMappingEditorViewController : UIViewController
- (instancetype)initWithUid:(uint32_t)uid
                        name:(NSString *)name
                    gameView:(UIView *)gameView
              mappingsChanged:(void (^)(void))mappingsChanged
               editingChanged:(void (^)(BOOL editing))editingChanged;
@end

NS_ASSUME_NONNULL_END
