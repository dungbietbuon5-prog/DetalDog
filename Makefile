ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TrungDungFF
TrungDungFF_FILES = Tweak.xm
TrungDungFF_FRAMEWORKS = UIKit Foundation

# Bắt buộc phải có 2 dòng này để bỏ qua lỗi deprecated
TrungDungFF_CFLAGS = -Wno-error -Wno-deprecated-declarations
TrungDungFF_CCFLAGS = -Wno-error -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/tweak.mk
