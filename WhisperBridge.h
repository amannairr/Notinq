#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WhisperBridge : NSObject

- (nullable instancetype)initWithModelPath:(NSString *)modelPath threads:(NSInteger)threads;
- (nullable NSString *)transcribePCMData:(NSData *)pcmData;
- (BOOL)isReady;
- (NSNumber *)readyValue;
- (void)resetTimings;
- (void)shutdown;

@end

NS_ASSUME_NONNULL_END
