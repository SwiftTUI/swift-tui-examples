LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := swift_tui_jni
LOCAL_SRC_FILES := swift_tui_jni.cpp
LOCAL_CPPFLAGS += -std=c++17 -Wall -Wextra -Werror
LOCAL_LDLIBS := -ldl -llog
include $(BUILD_SHARED_LIBRARY)

