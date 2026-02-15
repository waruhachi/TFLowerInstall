#import <Foundation/Foundation.h>
#import <substrate.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <roothide.h>

#define PREF_PATH jbroot(@"/var/mobile/Library/Preferences/moe.waru.tflowerinstall.plist")

@interface MIBundle : NSObject
- (BOOL)isWatchApp;
@end

static BOOL tweakEnabled = NO;
static BOOL forceInstallEnabled = NO;
static NSString *spoofedVersion = nil;

static void loadPrefs(void) {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:PREF_PATH];
    tweakEnabled = [prefs[@"enabled"] boolValue];
    forceInstallEnabled = [prefs[@"forceInstall"] boolValue];
    spoofedVersion = prefs[@"iOSVersion"];
}

// --- C function hooks (TestFlightServices) ---

static bool (*orig_tf_isBuildInstallable)(id build);
static bool hook_tf_isBuildInstallable(id build) {
    if (!tweakEnabled) return orig_tf_isBuildInstallable(build);
    return true;
}

static bool (*orig_tf_isAppCompatible)(id app);
static bool hook_tf_isAppCompatible(id app) {
    if (!tweakEnabled) return orig_tf_isAppCompatible(app);
    return true;
}

static bool (*orig_tf_doesBuildRequireCompatibleWatch)(id build);
static bool hook_tf_doesBuildRequireCompatibleWatch(id build) {
    if (!tweakEnabled) return orig_tf_doesBuildRequireCompatibleWatch(build);
    return false;
}

// --- TestFlight hooks (loaded in TestFlight process) ---

%group TestFlightHooks

%hook TFAppBuild

- (long long)compatibilityState {
    if (!tweakEnabled) return %orig;
    return 0;
}

- (bool)requiresOSUpdate {
    if (!tweakEnabled) return %orig;
    return NO;
}

- (bool)requiresOtherHardware {
    if (!tweakEnabled) return %orig;
    return NO;
}

- (bool)installableByHostDevice {
    if (!tweakEnabled) return %orig;
    return YES;
}

%end

%hook TFApp

- (bool)previouslyTested {
    if (!tweakEnabled) return %orig;
    return NO;
}

%end

%hook OASAppContext

- (bool)containsCompatibleBuild {
    if (!tweakEnabled) return %orig;
    return YES;
}

%end

%hook OASBundleContext

- (bool)isOpenable {
    if (!tweakEnabled) return %orig;
    bool orig = %orig;
    if (!orig) {
        return %orig;
    }
    return orig;
}

%end

%end

// --- installd hooks (loaded in installd process) ---

%group InstalldHooks

%hook MIBundle

- (BOOL)_isMinimumOSVersion:(id)arg1 applicableToOSVersion:(id)arg2 requiredOS:(unsigned long long)arg3 error:(id *)arg4 {
    if (!tweakEnabled || !forceInstallEnabled) return %orig;
    if ([self isWatchApp]) return %orig;
    if (spoofedVersion != nil) {
        return %orig(arg1, spoofedVersion, arg3, arg4);
    }
    return %orig;
}

%end

%end

%ctor {
    @autoreleasepool {
        loadPrefs();

        if (!tweakEnabled) return;

        NSString *processName = [[NSProcessInfo processInfo] processName];

        if ([processName isEqualToString:@"installd"]) {
            %init(InstalldHooks);
        } else {
            // TestFlight process
            %init(TestFlightHooks);

            void *handle = dlopen(NULL, RTLD_NOW);

            void *sym = dlsym(handle, "tf_isBuildInstallable");
            if (sym) {
                MSHookFunction(sym, (void *)hook_tf_isBuildInstallable, (void **)&orig_tf_isBuildInstallable);
            }

            sym = dlsym(handle, "tf_isAppCompatible");
            if (sym) {
                MSHookFunction(sym, (void *)hook_tf_isAppCompatible, (void **)&orig_tf_isAppCompatible);
            }

            sym = dlsym(handle, "tf_doesBuildRequireCompatibleWatch");
            if (sym) {
                MSHookFunction(sym, (void *)hook_tf_doesBuildRequireCompatibleWatch, (void **)&orig_tf_doesBuildRequireCompatibleWatch);
            }
        }
    }
}
