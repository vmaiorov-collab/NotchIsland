#import <Foundation/Foundation.h>
#include <dlfcn.h>
typedef void (^Cb)(NSDictionary *);
typedef void (*GetInfo)(dispatch_queue_t, Cb);
void np_get(void *interp, void *cv) {
    @autoreleasepool {
        void *h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
        GetInfo f = (GetInfo)dlsym(h, "MRMediaRemoteGetNowPlayingInfo");
        dispatch_semaphore_t s = dispatch_semaphore_create(0);
        __block NSDictionary *d = nil;
        f(dispatch_get_global_queue(0, 0), ^(NSDictionary *i) { d = i; dispatch_semaphore_signal(s); });
        dispatch_semaphore_wait(s, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
        if (!d || !d[@"kMRMediaRemoteNowPlayingInfoTitle"]) { printf("\n"); fflush(stdout); return; }
        NSString *t = d[@"kMRMediaRemoteNowPlayingInfoTitle"] ?: @"";
        NSString *a = d[@"kMRMediaRemoteNowPlayingInfoArtist"] ?: @"";
        NSNumber *r = d[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"] ?: @0;
        printf("%s\t%s\t%d\n", t.UTF8String, a.UTF8String, r.doubleValue > 0);
        fflush(stdout);
    }
}
