#import <Foundation/Foundation.h>
#import <spawn.h>
#import "TFLRootListController.h"

#define PREF_DOMAIN @"com.34306.tflowerinstall"
#define PREF_PATH @THEOS_PACKAGE_INSTALL_PREFIX "/var/mobile/Library/Preferences/com.34306.tflowerinstall.plist"

extern char **environ;

@implementation TFLRootListController

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

    // Write plist directly so tweak processes can read it
    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithDictionary:@{
        @"enabled": @(enabled),
        @"forceInstall": @(forceInstall),
    }];

    if (iOSVersion) {
        prefs[@"iOSVersion"] = iOSVersion;
    }

    // Ensure parent directory exists
    NSString *prefsPath = PREF_PATH;
    [[NSFileManager defaultManager] createDirectoryAtPath:[prefsPath stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    [prefs writeToFile:prefsPath atomically:YES];

    // Kill TestFlight and installd so they pick up new prefs on next launch
    pid_t pid;
    const char *killall = "/usr/bin/killall";

    char *argv_tf[] = {(char *)killall, "-9", "TestFlight", NULL};
    posix_spawn(&pid, killall, NULL, NULL, argv_tf, environ);

    char *argv_installd[] = {(char *)killall, "-9", "installd", NULL};
    posix_spawn(&pid, killall, NULL, NULL, argv_installd, environ);
}

@end
