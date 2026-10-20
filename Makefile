# Package scheme is chosen on the command line / CI:
#   make package THEOS_PACKAGE_SCHEME=rootless   -> iphoneos-arm64   (Dopamine, palera1n rootless)
#   make package THEOS_PACKAGE_SCHEME=roothide   -> iphoneos-arm64e  (Dopamine roothide) [needs roothide/theos]
#   make package THEOS_PACKAGE_SCHEME=           -> iphoneos-arm     (rootful)
THEOS_PACKAGE_SCHEME ?= rootless

TARGET := iphone:clang:latest:16.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MaterialMotion
MaterialMotion_FILES = Tweak.x
MaterialMotion_CFLAGS = -fobjc-arc -Wno-unused-variable
MaterialMotion_FRAMEWORKS = UIKit QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
