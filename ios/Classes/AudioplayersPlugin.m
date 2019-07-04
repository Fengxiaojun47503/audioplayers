#import "AudioplayersPlugin.h"
#import <UIKit/UIKit.h>
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

#define STATE_PAUSE -1
#define STATE_PLAY -2
#define STATE_STOP -3

static NSString *const CHANNEL_NAME = @"xyz.luan/audioplayers";

// 播放的id 用来保存配置
static NSString *const PLAY_ID = @"ios_play_id";

static NSMutableDictionary * players;




@interface AudioplayersPlugin()
-(void) pause: (NSString *) playerId;
-(void) stop: (NSString *) playerId;
-(void) seek: (NSString *) playerId time: (CMTime) time;
-(void) onSoundComplete: (NSString *) playerId;
-(void) updateDuration: (NSString *) playerId;
-(void) onTimeInterval: (NSString *) playerId time: (CMTime) time;
@end

static AudioplayersPlugin* instance;

@implementation AudioplayersPlugin {
    FlutterResult _result;
    id _playTargetId;
    id _pauseTargetId;
    id _seekTargetId;
    // 用来保存控制器数据内容
    NSMutableDictionary *_dictPlayInfo;
    double _startTime;
    double _lastSaveTime;
    int _state;
}

typedef void (^VoidCallback)(NSString * playerId);

NSMutableSet *timeobservers;
FlutterMethodChannel *_channel_audioplayer;

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    FlutterMethodChannel* channel = [FlutterMethodChannel
                                     methodChannelWithName:CHANNEL_NAME
                                     binaryMessenger:[registrar messenger]];
    instance = [[AudioplayersPlugin alloc] init];
    [registrar addMethodCallDelegate:instance channel:channel];
    _channel_audioplayer = channel;
}

+ (AudioplayersPlugin *) getAudioplayersPlugin{
    return instance;
}

- (id)init {
    self = [super init];
    if (self) {
        players = [[NSMutableDictionary alloc] init];
    }
    return self;
}


- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    NSString * playerId = PLAY_ID;
    NSLog(@"iOS => call %@, playerId %@", call.method, playerId);
    
    typedef void (^CaseBlock)(void);
    
    // Squint and this looks like a proper switch!
    NSDictionary *methods = @{
                              @"fetchExistPlayer":
                                  ^{
                                      result(PLAY_ID);
                                  },
                              @"deleteNotification":
                                  ^{
                                      // 删除通知
                                      if (_playTargetId) {
                                          _dictPlayInfo = nil;
                                          MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
                                          MPRemoteCommand *play = [commandCenter playCommand];
                                          [play setEnabled:NO];
                                          [play removeTarget:_playTargetId];
                                          _playTargetId = nil;
                                          
                                          MPRemoteCommand *pause = [commandCenter pauseCommand];
                                          [pause setEnabled:NO];
                                          [pause removeTarget:_pauseTargetId];
                                          _pauseTargetId = nil;
                                          
                                          MPChangePlaybackPositionCommand *seek = [commandCenter changePlaybackPositionCommand];
                                          //                                          [seek setEnabled:NO];
                                          [seek removeTarget:_seekTargetId];
                                          _seekTargetId = nil;
                                          
                                          //                                          [[UIApplication sharedApplication] endReceivingRemoteControlEvents];
                                          [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:nil];
                                      }
                                      
                                      result(nil);
                                  },
                              @"play":
                                  ^{
                                      NSLog(@"play!");
                                      NSString *url = call.arguments[@"url"];
                                      if (url == nil)
                                          result(0);
                                      if (call.arguments[@"isLocal"]==nil)
                                          result(0);
                                      if (call.arguments[@"volume"]==nil)
                                          result(0);
                                      if (call.arguments[@"position"]==nil)
                                          result(0);
                                      int isLocal = [call.arguments[@"isLocal"]intValue] ;
                                      float volume = (float)[call.arguments[@"volume"] doubleValue] ;
                                      double seconds = call.arguments[@"position"] == [NSNull null] ? 0.0 : [call.arguments[@"position"] doubleValue] ;
                                      CMTime time = CMTimeMakeWithSeconds(seconds,1);
                                      NSLog(@"isLocal: %d %@",isLocal, call.arguments[@"isLocal"] );
                                      NSLog(@"volume: %f %@",volume, call.arguments[@"volume"] );
                                      NSLog(@"position: %f %@", seconds, call.arguments[@"positions"] );
                                      _startTime = seconds;
                                      _lastSaveTime = _startTime;
                                      [self play:playerId url:url isLocal:isLocal volume:volume time:time];
                                      
                                  },
                              @"pause":
                                  ^{
                                      NSLog(@"pause");
                                      [self pause:playerId];
                                  },
                              @"resume":
                                  ^{
                                      NSLog(@"resume");
                                      [self resume:playerId];
                                  },
                              @"stop":
                                  ^{
                                      NSLog(@"stop");
                                      [self stop:playerId];
                                  },
                              @"release":
                                  ^{
                                      NSLog(@"release");
                                      [self stop:playerId];
                                  },
                              @"seek":
                                  ^{
                                      NSLog(@"seek");
                                      if (!call.arguments[@"position"]) {
                                          result(0);
                                      } else {
                                          double seconds = [call.arguments[@"position"] doubleValue];
                                          NSLog(@"Seeking to: %f seconds", seconds);
                                          [self seek:playerId time:CMTimeMakeWithSeconds(seconds,1)];
                                      }
                                  },
                              @"setUrl":
                                  ^{
                                      NSLog(@"setUrl");
                                      NSString *url = call.arguments[@"url"];
                                      int isLocal = [call.arguments[@"isLocal"]intValue];
                                      [ self setUrl:url
                                            isLocal:isLocal
                                           playerId:playerId
                                            onReady:^(NSString * playerId) {
                                                result(@(1));
                                            }
                                       ];
                                  },
                              @"setVolume":
                                  ^{
                                      NSLog(@"setVolume");
                                      float volume = (float)[call.arguments[@"volume"] doubleValue];
                                      [self setVolume:volume playerId:playerId];
                                  },
                              @"setReleaseMode":
                                  ^{
                                      NSLog(@"setReleaseMode");
                                      NSString *releaseMode = call.arguments[@"releaseMode"];
                                      bool looping = [releaseMode hasSuffix:@"LOOP"];
                                      [self setLooping:looping playerId:playerId];
                                  }
                              };
    
    [ self initPlayerInfo:playerId ];
    CaseBlock c = methods[call.method];
    if (c) c(); else {
        NSLog(@"not implemented");
        result(FlutterMethodNotImplemented);
    }
    if(![call.method isEqualToString:@"setUrl"]) {
        result(@(1));
    }
}

-(void) initPlayerInfo: (NSString *) playerId {
    NSMutableDictionary * playerInfo = players[playerId];
    if (!playerInfo) {
        players[playerId] = [@{@"isPlaying": @false, @"volume": @(1.0), @"looping": @(false)} mutableCopy];
    }
}

-(void) setUrl: (NSString*) url
       isLocal: (bool) isLocal
      playerId: (NSString*) playerId
       onReady:(VoidCallback)onReady
{
    NSMutableDictionary * playerInfo = players[playerId];
    AVPlayer *player = playerInfo[@"player"];
    NSMutableSet *observers = playerInfo[@"observers"];
    AVPlayerItem *playerItem;
    
    NSLog(@"setUrl %@", url);
    
    if (!playerInfo || ![url isEqualToString:playerInfo[@"url"]]) {
        if (isLocal) {
            playerItem = [ [ AVPlayerItem alloc ] initWithURL:[ NSURL fileURLWithPath:url ]];
        } else {
            playerItem = [ [ AVPlayerItem alloc ] initWithURL:[ NSURL URLWithString:url ]];
        }
        
        if (playerInfo[@"url"]) {
            [[player currentItem] removeObserver:self forKeyPath:@"player.currentItem.status" ];
            
            [ playerInfo setObject:url forKey:@"url" ];
            
            for (id ob in observers) {
                [ [ NSNotificationCenter defaultCenter ] removeObserver:ob ];
            }
            [ observers removeAllObjects ];
            [ player replaceCurrentItemWithPlayerItem: playerItem ];
        } else {
            player = [[ AVPlayer alloc ] initWithPlayerItem: playerItem ];
            observers = [[NSMutableSet alloc] init];
            
            [ playerInfo setObject:player forKey:@"player" ];
            [ playerInfo setObject:url forKey:@"url" ];
            [ playerInfo setObject:observers forKey:@"observers" ];
            
            // playerInfo = [@{@"player": player, @"url": url, @"isPlaying": @false, @"observers": observers, @"volume": @(1.0), @"looping": @(false)} mutableCopy];
            // players[playerId] = playerInfo;
            
            // stream player position
            CMTime interval = CMTimeMakeWithSeconds(1, NSEC_PER_SEC);
            id timeObserver = [ player  addPeriodicTimeObserverForInterval: interval queue: nil usingBlock:^(CMTime time){
                [self onTimeInterval:playerId time:time];
            }];
            [timeobservers addObject:@{@"player":player, @"observer":timeObserver}];
        }
        
        id anobserver = [[ NSNotificationCenter defaultCenter ] addObserverForName: AVPlayerItemDidPlayToEndTimeNotification
                                                                            object: playerItem
                                                                             queue: nil
                                                                        usingBlock:^(NSNotification* note){
                                                                            [self onSoundComplete:playerId];
                                                                        }];
        [observers addObject:anobserver];
        
        // is sound ready
        [playerInfo setObject:onReady forKey:@"onReady"];
        [playerItem addObserver:self
                     forKeyPath:@"player.currentItem.status"
                        options:0
                        context:(void*)playerId];
        
    } else {
        if ([[player currentItem] status ] == AVPlayerItemStatusReadyToPlay) {
            onReady(playerId);
        }
    }
}

-(void) play: (NSString*) playerId
         url: (NSString*) url
     isLocal: (int) isLocal
      volume: (float) volume
        time: (CMTime) time
{
    NSError *error = nil;
    BOOL success = [[AVAudioSession sharedInstance]
                    setCategory:AVAudioSessionCategoryPlayback
                    error:&error];
    if (!success) {
        NSLog(@"Error setting speaker: %@", error);
    }
    [[AVAudioSession sharedInstance] setActive:YES error:&error];
    
    [ self setUrl:url
          isLocal:isLocal
         playerId:playerId
          onReady:^(NSString * playerId) {
              NSMutableDictionary * playerInfo = players[playerId];
              AVPlayer *player = playerInfo[@"player"];
              [ player setVolume:volume ];
              [ player seekToTime:time ];
              [ player play];
              [ playerInfo setObject:@true forKey:@"isPlaying" ];
              _state = STATE_PLAY;
              [_channel_audioplayer invokeMethod:@"audio.onDuration" arguments:@{@"playerId": playerId, @"value": @(_state)}];
              
              if ([_delegate respondsToSelector:@selector(getNovelInfoWithUrl:)]) {
                  [_delegate getNovelInfoWithUrl:url];
              }
          }
     ];
}

-(void) updateDuration: (NSString *) playerId
{
    NSMutableDictionary * playerInfo = players[playerId];
    AVPlayer *player = playerInfo[@"player"];
    
    CMTime duration = [[[player currentItem]  asset] duration];
    NSLog(@"ios -> updateDuration...%f", CMTimeGetSeconds(duration));
    if(CMTimeGetSeconds(duration)>0){
        NSLog(@"ios -> invokechannel");
        int mseconds= CMTimeGetSeconds(duration)*1000;
        [_channel_audioplayer invokeMethod:@"audio.onDuration" arguments:@{@"playerId": playerId, @"value": @(mseconds)}];
       
    }
}

// No need to spam the logs with every time interval update
-(void) onTimeInterval: (NSString *) playerId
                  time: (CMTime) time {
    
    int mseconds =  CMTimeGetSeconds(time)*1000;
    _startTime = CMTimeGetSeconds(time);
    NSLog(@"ios -> onTimeInterval... starTime : %fd lastTime : %fd", _startTime, _lastSaveTime);
    if (_startTime - _lastSaveTime >= 5) {
        _lastSaveTime = _startTime;
        if ([_delegate respondsToSelector:@selector(saveTime:isComplete:)]) {
            [_delegate saveTime:_startTime isComplete:false];
        }
    }
    // NSLog(@"asdff %@ - %d", playerId, mseconds);
    [_channel_audioplayer invokeMethod:@"audio.onCurrentPosition" arguments:@{@"playerId": playerId, @"value": @(mseconds)}];
//    [_channel_audioplayer invokeMethod:@"audio.onDuration" arguments:@{@"playerId": playerId, @"value": @(_state)}];
    //    NSLog(@"asdff end");
}

-(void) pause: (NSString *) playerId {
    NSMutableDictionary * playerInfo = players[playerId];
    AVPlayer *player = playerInfo[@"player"];
    
    _startTime = player.currentTime.value / player.currentTime.timescale;
    if(_dictPlayInfo) {
        [_dictPlayInfo setObject:[NSNumber numberWithDouble:_startTime] forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
        [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:_dictPlayInfo];
    }
    [ player pause ];
    [playerInfo setObject:@false forKey:@"isPlaying"];
    _state = STATE_PAUSE;
    [_channel_audioplayer invokeMethod:@"audio.onDuration" arguments:@{@"playerId": playerId, @"value": @(_state)}];
}

-(void) resume: (NSString *) playerId {
    NSMutableDictionary * playerInfo = players[playerId];
    AVPlayer *player = playerInfo[@"player"];
    [player play];
    [playerInfo setObject:@true forKey:@"isPlaying"];
    _startTime = player.currentTime.value / player.currentTime.timescale;
    if(_dictPlayInfo) {
        [_dictPlayInfo setObject:[NSNumber numberWithDouble:_startTime] forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
        [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:_dictPlayInfo];
    }
    _state = STATE_PLAY;
    [_channel_audioplayer invokeMethod:@"audio.onDuration" arguments:@{@"playerId": playerId, @"value": @(_state)}];
}

-(void) setVolume: (float) volume 
         playerId:  (NSString *) playerId {
    NSMutableDictionary *playerInfo = players[playerId];
    AVPlayer *player = playerInfo[@"player"];
    playerInfo[@"volume"] = @(volume);
    [ player setVolume:volume ];
}

-(void) setLooping: (bool) looping
          playerId:  (NSString *) playerId {
    NSMutableDictionary *playerInfo = players[playerId];
    [playerInfo setObject:@(looping) forKey:@"looping"];
}

-(void) stop: (NSString *) playerId {
    NSMutableDictionary * playerInfo = players[playerId];
    
    if ([playerInfo[@"isPlaying"] boolValue]) {
        [ self pause:playerId ];
        [ self seek:playerId time:CMTimeMake(0, 1) ];
        [playerInfo setObject:@false forKey:@"isPlaying"];
        _state = STATE_STOP;
        [_channel_audioplayer invokeMethod:@"audio.onDuration" arguments:@{@"playerId": playerId, @"value": @(_state)}];
    }
}

-(void) seek: (NSString *) playerId
        time: (CMTime) time {
    NSMutableDictionary * playerInfo = players[playerId];
    AVPlayer *player = playerInfo[@"player"];
    [[player currentItem] seekToTime:time];
    [ _channel_audioplayer invokeMethod:@"audio.onSeekComplete" arguments:@{@"playerId": playerId, @"value": @(time.value / time.timescale * 1000)}];
    
}

-(void) onSoundComplete: (NSString *) playerId {
    NSLog(@"ios -> onSoundComplete...");
    NSMutableDictionary * playerInfo = players[playerId];
    if ([_delegate respondsToSelector:@selector(saveTime:isComplete:)]) {
        [_delegate saveTime:_startTime isComplete:true];
    }
    if (![playerInfo[@"isPlaying"] boolValue]) {
        return;
    }
    
    [ self pause:playerId ];
    [ self seek:playerId time:CMTimeMakeWithSeconds(0,1) ];
    
    if ([ playerInfo[@"looping"] boolValue]) {
        [ self resume:playerId ];
    }
    
    [ _channel_audioplayer invokeMethod:@"audio.onComplete" arguments:@{@"playerId": playerId}];
}

-(void)observeValueForKeyPath:(NSString *)keyPath
                     ofObject:(id)object
                       change:(NSDictionary *)change
                      context:(void *)context {
    if ([keyPath isEqualToString: @"player.currentItem.status"]) {
        NSString *playerId = (__bridge NSString*)context;
        NSMutableDictionary * playerInfo = players[playerId];
        AVPlayer *player = playerInfo[@"player"];
        
        NSLog(@"player status: %ld",(long)[[player currentItem] status ]);
        
        // Do something with the status…
        if ([[player currentItem] status ] == AVPlayerItemStatusReadyToPlay) {
            [self updateDuration:playerId];
            
            VoidCallback onReady = playerInfo[@"onReady"];
            if (onReady != nil) {
                [playerInfo removeObjectForKey:@"onReady"];
                onReady(playerId);
            }
        } else if ([[player currentItem] status ] == AVPlayerItemStatusFailed) {
            [_channel_audioplayer invokeMethod:@"audio.onError" arguments:@{@"playerId": playerId, @"value": @"AVPlayerItemStatus.failed"}];
        }
    } else {
        // Any unrecognized context must belong to super
        [super observeValueForKeyPath:keyPath
                             ofObject:object
                               change:change
                              context:context];
    }
}

- (void)dealloc {
    for (id value in timeobservers)
        [value[@"player"] removeTimeObserver:value[@"observer"]];
    timeobservers = nil;
    
    for (NSString* playerId in players) {
        NSMutableDictionary * playerInfo = players[playerId];
        NSMutableSet * observers = playerInfo[@"observers"];
        for (id ob in observers)
            [[NSNotificationCenter defaultCenter] removeObserver:ob];
    }
    players = nil;
}

- (void)setPlayControllDictionary:(NSMutableDictionary *)info {
    _dictPlayInfo = info;
    
    //设置已经播放时长
    [_dictPlayInfo setObject:[NSNumber numberWithDouble:_startTime] forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
    
    [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:_dictPlayInfo];
    [self setMPRemoteCommandCenter];
}

- (void)setMPRemoteCommandCenter {
    if (!_playTargetId) {
        
        MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
        
        MPRemoteCommand *play = [commandCenter playCommand];
        [play setEnabled:YES];
        _playTargetId = [play addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
            [self resume: PLAY_ID];
            return MPRemoteCommandHandlerStatusSuccess;
        }];
        
        MPRemoteCommand *pause = [commandCenter pauseCommand];
        [pause setEnabled:YES];
        _pauseTargetId = [pause addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
            [self pause: PLAY_ID];
            return MPRemoteCommandHandlerStatusSuccess;
        }];
        
        
        MPChangePlaybackPositionCommand *seek = [commandCenter changePlaybackPositionCommand];
        [seek setEnabled:YES];
        _seekTargetId = [seek addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
            MPChangePlaybackPositionCommandEvent *events = (MPChangePlaybackPositionCommandEvent *)event;
            [self seek:PLAY_ID time: CMTimeMakeWithSeconds([events positionTime],1)] ;
            return MPRemoteCommandHandlerStatusSuccess;
        }];
        
    }
    
}
@end

