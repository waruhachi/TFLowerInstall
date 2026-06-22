#import <Foundation/Foundation.h>
#import <roothide.h>
#import <spawn.h>

#import "TFLowerInstallRootListController.h"

#define PREF_DOMAIN @"moe.waru.tflowerinstall"
#define PREF_PATH jbroot(@"/Library/MobileSubstrate/DynamicLibraries/TFLowerInstallPrefs.plist")

extern char **environ;

@implementation TFLowerInstallRootListController

- (NSArray *)specifiers {
	if (!_specifiers) {
		_specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
		_savedSpecifiers = [_specifiers mutableCopy];
	}
	return _specifiers;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	UIBarButtonItem *applyButton = [[UIBarButtonItem alloc] initWithTitle:@"Apply"
																	style:UIBarButtonItemStylePlain
																   target:self
																   action:@selector(applySettings)];
	self.navigationItem.rightBarButtonItem = applyButton;
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self updateVisibility];
}

- (PSSpecifier *)savedSpecifierForID:(NSString *)identifier {
	for (PSSpecifier *spec in _savedSpecifiers) {
		if ([[spec propertyForKey:@"id"] isEqualToString:identifier]) {
			return spec;
		}
	}
	return nil;
}

- (BOOL)specifierExistsInCurrent:(NSString *)identifier {
	for (PSSpecifier *spec in [self specifiers]) {
		if ([[spec propertyForKey:@"id"] isEqualToString:identifier]) {
			return YES;
		}
	}
	return NO;
}

- (void)updateVisibility {
	NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:PREF_DOMAIN];
	BOOL enabled = [defaults boolForKey:@"enabled"];

	PSSpecifier *forceInstallSpec = [self savedSpecifierForID:@"forceInstall"];
	PSSpecifier *iosVersionSpec = [self savedSpecifierForID:@"iOSVersion"];

	if (enabled) {
		if (forceInstallSpec && ![self specifierExistsInCurrent:@"forceInstall"]) {
			[self insertSpecifier:forceInstallSpec afterSpecifierID:@"enabled" animated:YES];
		}
		if (iosVersionSpec && ![self specifierExistsInCurrent:@"iOSVersion"]) {
			[self insertSpecifier:iosVersionSpec afterSpecifierID:@"forceInstall" animated:YES];
		}
	} else {
		if ([self specifierExistsInCurrent:@"iOSVersion"]) {
			[self removeSpecifier:iosVersionSpec animated:YES];
		}
		if ([self specifierExistsInCurrent:@"forceInstall"]) {
			[self removeSpecifier:forceInstallSpec animated:YES];
		}
	}
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	[super setPreferenceValue:value specifier:specifier];

	NSString *key = [specifier propertyForKey:@"key"];
	if ([key isEqualToString:@"enabled"]) {
		[self updateVisibility];
	}
}

- (void)applySettings {
	// Dismiss keyboard
	for (UIWindow *window in [UIApplication sharedApplication].windows) {
		if (window.isKeyWindow) {
			[window endEditing:YES];
			break;
		}
	}

	// Read current values
	NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:PREF_DOMAIN];
	BOOL enabled = [defaults boolForKey:@"enabled"];
	BOOL forceInstall = [defaults boolForKey:@"forceInstall"];
	NSString *iOSVersion = [defaults stringForKey:@"iOSVersion"];

	if (enabled && (!iOSVersion || [iOSVersion length] == 0)) {
		[defaults setBool:NO forKey:@"enabled"];
		enabled = NO;
		[self updateVisibility];
	}

	// Mirror the settings into the jailbreak root so injected sandboxed apps can read them.
	NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithDictionary:@{
		@"enabled": @(enabled),
		@"forceInstall": @(forceInstall),
	}];

	if (iOSVersion) {
		prefs[@"iOSVersion"] = iOSVersion;
	}

	NSString *prefsPath = PREF_PATH;
	[[NSFileManager defaultManager] createDirectoryAtPath:[prefsPath stringByDeletingLastPathComponent]
							  withIntermediateDirectories:YES
											   attributes:nil
													error:nil];
	// The packaged mirror is owned by mobile. Write in place because an atomic
	// replacement would require write access to the root-owned parent directory.
	BOOL wrotePreferences = [prefs writeToFile:prefsPath atomically:NO];
	NSLog(@"[TFLowerInstall] Wrote preference mirror to %@: result=%d", prefsPath, wrotePreferences);

	// Kill TestFlight and installd so they pick up new prefs on next launch
	pid_t pid;
	const char *killall = jbroot("/usr/bin/killall");

	char *argv_tf[] = {(char *)killall, "-9", "TestFlight", NULL};
	int testFlightSpawnResult = posix_spawn(&pid, killall, NULL, NULL, argv_tf, environ);
	NSLog(@"[TFLowerInstall] Restart TestFlight using %s: posix_spawn=%d", killall, testFlightSpawnResult);

	char *argv_installd[] = {(char *)killall, "-9", "installd", NULL};
	int installdSpawnResult = posix_spawn(&pid, killall, NULL, NULL, argv_installd, environ);
	NSLog(@"[TFLowerInstall] Restart installd using %s: posix_spawn=%d", killall, installdSpawnResult);
}

@end
