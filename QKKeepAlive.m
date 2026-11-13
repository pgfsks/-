#import "QKKeepAlive.h"
#import "QKLog.h"

#import <AVFoundation/AVFoundation.h>

@interface QKKeepAlive ()
@property (nonatomic, strong) AVAudioPlayer *player;
@property (nonatomic) BOOL running;
@end

@implementation QKKeepAlive

+ (instancetype)shared {
    static QKKeepAlive *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [QKKeepAlive new]; });
    return instance;
}

- (BOOL)start {
    if (_running && self.player.isPlaying) return YES;

    NSError *error = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback
              withOptions:AVAudioSessionCategoryOptionMixWithOthers
                    error:&error];
    [session setActive:YES error:&error];
    if (error) QKLog(@"AudioSession 出错：%@", error.localizedDescription);

    // 代码里现造一段 0.5s 的 16bit 单声道 44.1k 静音 WAV，不依赖资源文件
    NSData *wav = [self silentWavDataWithSampleRate:44100 duration:0.5];
    self.player = [[AVAudioPlayer alloc] initWithData:wav error:&error];
    if (!self.player || error) {
        QKLog(@"静音播放器创建失败：%@", error.localizedDescription);
        return NO;
    }
    self.player.numberOfLoops = -1;
    self.player.volume = 0.0;

    BOOL ok = [self.player play];
    _running = ok;
    QKLog(@"后台保活：%@", ok ? @"已启动" : @"启动失败");
    return ok;
}

- (void)stop {
    [self.player stop];
    self.player = nil;
    _running = NO;
}

- (void)ensureRunning {
    if (!_running || !self.player.isPlaying) [self start];
}

#pragma mark - 静音 WAV

- (NSData *)silentWavDataWithSampleRate:(NSUInteger)rate duration:(double)seconds {
    NSUInteger frames = (NSUInteger)(rate * seconds);
    NSUInteger dataBytes = frames * 2;   // 16bit mono

    NSMutableData *data = [NSMutableData dataWithCapacity:44 + dataBytes];

    uint32_t chunkSize = (uint32_t)(36 + dataBytes);
    uint16_t audioFormat = 1, channels = 1, bitsPerSample = 16, blockAlign = 2;
    uint32_t byteRate = (uint32_t)(rate * 2);
    uint32_t subchunk2 = (uint32_t)dataBytes;

    [data appendBytes:"RIFF" length:4];
    [data appendBytes:&chunkSize length:4];
    [data appendBytes:"WAVEfmt " length:8];
    uint32_t fmtSize = 16;
    [data appendBytes:&fmtSize length:4];
    [data appendBytes:&audioFormat length:2];
    [data appendBytes:&channels length:2];
    [data appendBytes:&rate length:4];
    [data appendBytes:&byteRate length:4];
    [data appendBytes:&blockAlign length:2];
    [data appendBytes:&bitsPerSample length:2];
    [data appendBytes:"data" length:4];
    [data appendBytes:&subchunk2 length:4];
    [data appendBytes:calloc(dataBytes, 1) length:dataBytes];   // 全 0 = 静音

    return data;
}

@end
