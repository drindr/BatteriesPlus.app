#import <Foundation/Foundation.h>

@interface BPSystemBridge : NSObject
+ (NSArray<NSDictionary *> *)systemDevices;
+ (int32_t)publish:(NSDictionary *)details identifier:(NSString *)identifier;
+ (void)remove:(NSString *)identifier;
@end
