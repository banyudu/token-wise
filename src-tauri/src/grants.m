// App Sandbox folder-access bridge.
//
// Apple rejects `com.apple.security.temporary-exception.files.home-relative-path`
// (guideline 2.4.5(i)), so the Mac App Store build can't read `~/.claude` or
// `~/.codex` directly. Instead the user grants access once via a native folder
// picker, and we persist a *security-scoped bookmark* so the grant survives
// relaunches.
//
// This file exposes four plain-C functions to Rust (see src/grants.rs). It is
// compiled with ARC (`-fobjc-arc`) and linked against Foundation + AppKit.
#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

// Presents a directory picker (pre-navigated into `defaultPathUtf8` when that
// path exists, so dotfolders like `~/.claude` are easy to confirm), then creates
// a security-scoped bookmark from the panel's URL. On success returns 1 and fills
// `*outPath` (malloc'd UTF-8) and `*outBytes`/`*outLen` (malloc'd bookmark data);
// the caller frees both with `tw_free`. Returns 0 if the user cancelled or the
// bookmark could not be created.
int tw_pick_and_bookmark(const char *defaultPathUtf8,
                         char **outPath,
                         void **outBytes,
                         long *outLen) {
    __block int ok = 0;
    // NSOpenPanel must run on the main thread (it spins a modal event loop).
    // Rust calls this from a Tauri worker thread; dispatch_sync onto the main
    // queue blocks that worker until the user closes the panel.
    dispatch_sync(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            NSOpenPanel *panel = [NSOpenPanel openPanel];
            panel.canChooseFiles = NO;
            panel.canChooseDirectories = YES;
            panel.allowsMultipleSelection = NO;
            panel.canCreateDirectories = NO;
            // Dotfolders are hidden by default — reveal them so the user can see
            // `.claude` / `.codex` without needing to know the ⌘⇧. shortcut.
            panel.showsHiddenFiles = YES;
            panel.prompt = @"Grant Access";

            if (defaultPathUtf8 != NULL) {
                NSString *dp = [NSString stringWithUTF8String:defaultPathUtf8];
                if ([[NSFileManager defaultManager] fileExistsAtPath:dp]) {
                    // Opening *inside* the dotfolder means the user just clicks
                    // "Grant Access" to confirm it.
                    panel.directoryURL = [NSURL fileURLWithPath:dp isDirectory:YES];
                }
            }

            if ([panel runModal] != NSModalResponseOK || panel.URL == nil) {
                return;
            }

            NSError *err = nil;
            NSData *data = [panel.URL
                bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope
                includingResourceValuesForKeys:nil
                                  relativeToURL:nil
                                         error:&err];
            if (data == nil || [data length] == 0) {
                return;
            }

            const char *utf = [[panel.URL path] UTF8String];
            *outPath = strdup(utf ? utf : "");
            NSUInteger len = [data length];
            *outBytes = malloc(len);
            memcpy(*outBytes, [data bytes], len);
            *outLen = (long)len;
            ok = 1;
        }
    });
    return ok;
}

// Resolves previously-stored bookmark bytes into a URL and begins
// security-scoped access to it. On success returns 1 and fills `*outPath`
// (malloc'd UTF-8, free with `tw_free`) and `*outUrlHandle` — an opaque handle
// the caller must later pass to `tw_release_url` to stop access and release the
// URL. Returns 0 if the bookmark is stale or invalid. Thread-safe (no UI).
int tw_resolve_bookmark(const void *bytes,
                        long len,
                        char **outPath,
                        void **outUrlHandle) {
    if (bytes == NULL || len <= 0) {
        return 0;
    }
    @autoreleasepool {
        NSData *data = [NSData dataWithBytes:bytes length:(NSUInteger)len];
        BOOL stale = NO;
        NSError *err = nil;
        NSURL *url = [NSURL URLByResolvingBookmarkData:data
                                               options:NSURLBookmarkResolutionWithSecurityScope
                                         relativeToURL:nil
                                   bookmarkDataIsStale:&stale
                                                 error:&err];
        if (url == nil) {
            return 0;
        }
        [url startAccessingSecurityScopedResource];
        const char *utf = [[url path] UTF8String];
        *outPath = strdup(utf ? utf : "");
        // Hand ownership of `url` to the caller as a raw handle; ARC retains it
        // here and releases it inside `tw_release_url`.
        *outUrlHandle = (void *)CFBridgingRetain(url);
        return 1;
    }
}

// Stops security-scoped access for a handle returned by `tw_resolve_bookmark`
// and releases the underlying URL. Safe to call with NULL.
void tw_release_url(void *urlHandle) {
    if (urlHandle == NULL) {
        return;
    }
    @autoreleasepool {
        NSURL *url = CFBridgingRelease(urlHandle);
        [url stopAccessingSecurityScopedResource];
        // `url` is released by ARC when it goes out of scope below.
    }
}

// Frees memory returned by `tw_pick_and_bookmark` / `tw_resolve_bookmark`
// (`outPath` and `outBytes`). Safe to call with NULL.
void tw_free(void *ptr) {
    free(ptr);
}
