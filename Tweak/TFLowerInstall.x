#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <roothide.h>
#import <substrate.h>

#define PREF_PATH jbroot(@"/Library/MobileSubstrate/DynamicLibraries/TFLowerInstallPrefs.plist")

@interface MIBundle : NSObject
- (BOOL)isWatchApp;
@end

static BOOL tweakEnabled = NO;
static BOOL forceInstallEnabled = NO;
static NSString *spoofedVersion = nil;

static void loadPrefs(NSString *path) {
	NSDictionary *preferences = [NSDictionary dictionaryWithContentsOfFile:path];
	tweakEnabled = [preferences[@"enabled"] boolValue];
	forceInstallEnabled = [preferences[@"forceInstall"] boolValue];
	spoofedVersion = [preferences[@"iOSVersion"] copy];
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

- (bool)compatible {
	if (!tweakEnabled) return %orig;
	return YES;
}

- (bool)platformCompatible {
	if (!tweakEnabled) return %orig;
	return YES;
}

- (bool)hardwareCompatible {
	if (!tweakEnabled) return %orig;
	return YES;
}

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
		BOOL result = %orig(arg1, spoofedVersion, arg3, arg4);
		NSString *message = [NSString stringWithFormat:
				@"[TFLowerInstall] MinimumOSVersion check for %@: minimum=%@ actualOS=%@ spoofedOS=%@ requiredOS=%llu result=%d error=%@",
			self, arg1, arg2, spoofedVersion, arg3, result, arg4 != NULL ? *arg4 : nil];
		NSLog(@"%@", message);
		return result;
	}
	return %orig;
}

- (BOOL)_validateWithError:(NSError **)error {
	BOOL result = %orig;
	if (tweakEnabled && forceInstallEnabled) {
		NSError *validationError = error != NULL ? *error : nil;
		NSString *message = [NSString stringWithFormat:
				@"[TFLowerInstall] Bundle validation for %@: result=%d error=%@ userInfo=%@",
			self, result, validationError, validationError.userInfo];
		NSLog(@"%@", message);
	}
	return result;
}

%end

%end

%ctor {
	@autoreleasepool {
		NSString *processName = [[NSProcessInfo processInfo] processName];
		NSString *constructorMessage = [NSString stringWithFormat:
				@"[TFLowerInstall] Constructor loaded in %@ (pid=%d)", processName, [[NSProcessInfo processInfo] processIdentifier]];
		NSLog(@"%@", constructorMessage);

		loadPrefs(PREF_PATH);
		NSString *preferencesMessage = [NSString stringWithFormat:
				@"[TFLowerInstall] Preferences loaded: enabled=%d forceInstall=%d spoofedVersion=%@ path=%@",
			tweakEnabled, forceInstallEnabled, spoofedVersion, PREF_PATH];
		NSLog(@"%@", preferencesMessage);

		if (!tweakEnabled) return;

		if ([processName isEqualToString:@"installd"]) {
			NSString *message = [NSString stringWithFormat:
					@"[TFLowerInstall] Initializing installd hooks (forceInstall=%d, spoofedVersion=%@)",
				forceInstallEnabled, spoofedVersion];
			NSLog(@"%@", message);
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
