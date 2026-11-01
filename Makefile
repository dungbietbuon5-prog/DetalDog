ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TrungDungFF
TrungDungFF_FILES = Tweak.xm
TrungDungFF_FRAMEWORKS = UIKit Foundation

# Bỏ qua lỗi deprecated (hàm cũ) để Theos không dừng build
TrungDungFF_CFLAGS = -Wno-error -Wno-deprecated-declarations
TrungDungFF_CCFLAGS = -Wno-error -Wno-deprecated-declarations
TrungDungFF_CXXFLAGS = -Wno-error -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/tweak.mk
