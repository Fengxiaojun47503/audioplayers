#import <Flutter/Flutter.h>

@protocol AudioplayersPluginDelegate;

@interface AudioplayersPlugin : NSObject<FlutterPlugin>
@property (nonatomic, assign) id<AudioplayersPluginDelegate>delegate;

+ (AudioplayersPlugin*) getAudioplayersPlugin;
//从外部获取相关数据 当前时间数据不保存
- (void) setPlayControllDictionary:(NSMutableDictionary *)info;
@end

@protocol AudioplayersPluginDelegate <NSObject>
- (void)getNovelInfoWithUrl:(NSString*)url;
- (void)saveTime:(double)time isComplete:(BOOL)isComplete;
@end
