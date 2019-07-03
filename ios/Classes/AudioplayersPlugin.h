#import <Flutter/Flutter.h>

@protocol AudioplayersPluginDelegate;

@interface AudioplayersPlugin : NSObject<FlutterPlugin>
@property (nonatomic, assign) id<AudioplayersPluginDelegate>delegate;

+ (AudioplayersPlugin*) getAudioplayersPlugin;
- (void) setMPRemoteCommandCenter;
@end

@protocol AudioplayersPluginDelegate <NSObject>
-(void)getNovelInfoWithUrl:(NSString*)url;
@end
