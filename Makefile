ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

# Ép Theos dùng chuẩn C++17 để hiểu từ khóa constexpr
TrungDungFF_CFLAGS = -std=c++17
TrungDungFF_CCFLAGS = -std=c++17
TrungDungFF_CXXFLAGS = -std=c++17

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TrungDungFF
TrungDungFF_FILES = Tweak.xm
TrungDungFF_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
