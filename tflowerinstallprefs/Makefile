TARGET := iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = tflowerinstallprefs

tflowerinstallprefs_FILES = TFLRootListController.m
tflowerinstallprefs_FRAMEWORKS = UIKit
tflowerinstallprefs_PRIVATE_FRAMEWORKS = Preferences
tflowerinstallprefs_INSTALL_PATH = /Library/PreferenceBundles
tflowerinstallprefs_CFLAGS = -fobjc-arc -w

include $(THEOS_MAKE_PATH)/bundle.mk
