#import "BatteryBridge.h"
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/IOKitLib.h>
#include <dlfcn.h>

typedef IOReturn (*BPCreateSource)(void **);
typedef IOReturn (*BPUpdateSource)(void *, CFDictionaryRef);
typedef IOReturn (*BPReleaseSource)(void *);

@implementation BPSystemBridge

+ (NSArray<NSDictionary *> *)systemDevices {
    CFTypeRef (*copyAll)(int) = dlsym(RTLD_DEFAULT, "IOPSCopyPowerSourcesByType");
    CFTypeRef info = copyAll ? copyAll(0) : IOPSCopyPowerSourcesInfo();
    if (!info) return @[];
    CFArrayRef sources = IOPSCopyPowerSourcesList(info);
    NSMutableArray *devices = [NSMutableArray array];
    for (id source in (__bridge NSArray *)sources) {
        CFDictionaryRef description = IOPSGetPowerSourceDescription(info, (__bridge CFTypeRef)source);
        if (description) [devices addObject:[(__bridge NSDictionary *)description copy]];
    }
    if (sources) CFRelease(sources);
    CFRelease(info);
    return devices;
}

+ (NSMutableDictionary<NSString *, NSValue *> *)publishedSources {
    static NSMutableDictionary *sources;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ sources = [NSMutableDictionary dictionary]; });
    return sources;
}

+ (int32_t)publish:(NSDictionary *)details identifier:(NSString *)identifier {
    BPCreateSource create = dlsym(RTLD_DEFAULT, "IOPSCreatePowerSource");
    BPUpdateSource update = dlsym(RTLD_DEFAULT, "IOPSSetPowerSourceDetails");
    BPReleaseSource release = dlsym(RTLD_DEFAULT, "IOPSReleasePowerSource");
    if (!create || !update || !release) return kIOReturnUnsupported;
    @synchronized(self) {
        NSMutableDictionary *sources = [self publishedSources];
        void *source = [sources[identifier] pointerValue];
        BOOL created = source == NULL;
        if (created) {
            IOReturn result = create(&source);
            if (result != kIOReturnSuccess) return result;
            if (!source) return kIOReturnError;
        }
        IOReturn result = update(source, (__bridge CFDictionaryRef)details);
        if (result == kIOReturnSuccess) sources[identifier] = [NSValue valueWithPointer:source];
        else if (created) release(source);
        return result;
    }
}

+ (void)remove:(NSString *)identifier {
    BPReleaseSource release = dlsym(RTLD_DEFAULT, "IOPSReleasePowerSource");
    @synchronized(self) {
        NSMutableDictionary *sources = [self publishedSources];
        void *source = [sources[identifier] pointerValue];
        if (source && release) release(source);
        [sources removeObjectForKey:identifier];
    }
}
@end
