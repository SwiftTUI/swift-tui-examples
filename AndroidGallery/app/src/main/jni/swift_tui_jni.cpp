#include <android/log.h>
#include <dlfcn.h>
#include <jni.h>

#include <cstdint>
#include <mutex>

namespace {

constexpr const char* kLogTag = "SwiftTUIJNI";
constexpr const char* kGalleryLibrary = "libGalleryAndroidHost.so";

using CreateGalleryHost = int64_t (*)();
using HandleFunction = void (*)(int64_t);
using ResizeFunction = void (*)(int64_t, int32_t, int32_t, double, double);
using SendInputFunction = void (*)(int64_t, const uint8_t*, int32_t);
using CopyLatestFrameFunction = int32_t (*)(int64_t, uint8_t*, int32_t);
using CopyClipboardTextFunction = int32_t (*)(int64_t, uint8_t*, int32_t);

std::once_flag gLoadOnce;
void* gGalleryHandle = nullptr;

void loadGalleryLibrary() {
  gGalleryHandle = dlopen(kGalleryLibrary, RTLD_NOW | RTLD_LOCAL);
  if (gGalleryHandle == nullptr) {
    __android_log_print(
      ANDROID_LOG_ERROR,
      kLogTag,
      "dlopen(%s) failed: %s",
      kGalleryLibrary,
      dlerror()
    );
  }
}

void* resolveSymbol(const char* name) {
  std::call_once(gLoadOnce, loadGalleryLibrary);
  if (gGalleryHandle == nullptr) {
    return nullptr;
  }

  dlerror();
  void* symbol = dlsym(gGalleryHandle, name);
  const char* error = dlerror();
  if (error != nullptr) {
    __android_log_print(
      ANDROID_LOG_ERROR,
      kLogTag,
      "dlsym(%s) failed: %s",
      name,
      error
    );
    return nullptr;
  }
  return symbol;
}

template <typename Function>
Function swiftSymbol(const char* name) {
  return reinterpret_cast<Function>(resolveSymbol(name));
}

}  // namespace

extern "C" JNIEXPORT jlong JNICALL
Java_org_swifttui_gallery_android_SwiftTUIJni_createGalleryHost(
  JNIEnv*,
  jobject
) {
  auto createHost = swiftSymbol<CreateGalleryHost>(
    "swift_tui_android_create_gallery_host"
  );
  if (createHost == nullptr) {
    return 0;
  }
  return static_cast<jlong>(createHost());
}

extern "C" JNIEXPORT void JNICALL
Java_org_swifttui_gallery_android_SwiftTUIJni_start(
  JNIEnv*,
  jobject,
  jlong handle
) {
  auto start = swiftSymbol<HandleFunction>("swift_tui_android_start");
  if (start != nullptr) {
    start(static_cast<int64_t>(handle));
  }
}

extern "C" JNIEXPORT void JNICALL
Java_org_swifttui_gallery_android_SwiftTUIJni_stop(
  JNIEnv*,
  jobject,
  jlong handle
) {
  auto stop = swiftSymbol<HandleFunction>("swift_tui_android_stop");
  if (stop != nullptr) {
    stop(static_cast<int64_t>(handle));
  }
}

extern "C" JNIEXPORT void JNICALL
Java_org_swifttui_gallery_android_SwiftTUIJni_destroy(
  JNIEnv*,
  jobject,
  jlong handle
) {
  auto destroy = swiftSymbol<HandleFunction>("swift_tui_android_destroy");
  if (destroy != nullptr) {
    destroy(static_cast<int64_t>(handle));
  }
}

extern "C" JNIEXPORT void JNICALL
Java_org_swifttui_gallery_android_SwiftTUIJni_resize(
  JNIEnv*,
  jobject,
  jlong handle,
  jint columns,
  jint rows,
  jdouble cellPixelWidth,
  jdouble cellPixelHeight
) {
  auto resize = swiftSymbol<ResizeFunction>("swift_tui_android_resize");
  if (resize != nullptr) {
    resize(
      static_cast<int64_t>(handle),
      static_cast<int32_t>(columns),
      static_cast<int32_t>(rows),
      static_cast<double>(cellPixelWidth),
      static_cast<double>(cellPixelHeight)
    );
  }
}

extern "C" JNIEXPORT jint JNICALL
Java_org_swifttui_gallery_android_SwiftTUIJni_copyLatestFrame(
  JNIEnv* env,
  jobject,
  jlong handle,
  jbyteArray outBuffer,
  jint capacity
) {
  auto copyLatestFrame = swiftSymbol<CopyLatestFrameFunction>(
    "swift_tui_android_copy_latest_frame"
  );
  if (copyLatestFrame == nullptr) {
    return 0;
  }

  if (outBuffer == nullptr || capacity <= 0) {
    return copyLatestFrame(static_cast<int64_t>(handle), nullptr, 0);
  }

  jsize arrayLength = env->GetArrayLength(outBuffer);
  jint boundedCapacity = capacity < arrayLength ? capacity : arrayLength;
  jbyte* bytes = env->GetByteArrayElements(outBuffer, nullptr);
  if (bytes == nullptr) {
    return 0;
  }

  jint needed = copyLatestFrame(
    static_cast<int64_t>(handle),
    reinterpret_cast<uint8_t*>(bytes),
    static_cast<int32_t>(boundedCapacity)
  );
  env->ReleaseByteArrayElements(outBuffer, bytes, 0);
  return needed;
}

extern "C" JNIEXPORT jint JNICALL
Java_org_swifttui_gallery_android_SwiftTUIJni_copyClipboardText(
  JNIEnv* env,
  jobject,
  jlong handle,
  jbyteArray outBuffer,
  jint capacity
) {
  auto copyClipboardText = swiftSymbol<CopyClipboardTextFunction>(
    "swift_tui_android_copy_clipboard_text"
  );
  if (copyClipboardText == nullptr) {
    return 0;
  }

  if (outBuffer == nullptr || capacity <= 0) {
    return copyClipboardText(static_cast<int64_t>(handle), nullptr, 0);
  }

  jsize arrayLength = env->GetArrayLength(outBuffer);
  jint boundedCapacity = capacity < arrayLength ? capacity : arrayLength;
  jbyte* bytes = env->GetByteArrayElements(outBuffer, nullptr);
  if (bytes == nullptr) {
    return 0;
  }

  jint needed = copyClipboardText(
    static_cast<int64_t>(handle),
    reinterpret_cast<uint8_t*>(bytes),
    static_cast<int32_t>(boundedCapacity)
  );
  env->ReleaseByteArrayElements(outBuffer, bytes, 0);
  return needed;
}

extern "C" JNIEXPORT void JNICALL
Java_org_swifttui_gallery_android_SwiftTUIJni_sendInput(
  JNIEnv* env,
  jobject,
  jlong handle,
  jbyteArray input,
  jint count
) {
  auto sendInput = swiftSymbol<SendInputFunction>(
    "swift_tui_android_send_input"
  );
  if (sendInput == nullptr || input == nullptr || count <= 0) {
    return;
  }

  jsize arrayLength = env->GetArrayLength(input);
  jint boundedCount = count < arrayLength ? count : arrayLength;
  jbyte* bytes = env->GetByteArrayElements(input, nullptr);
  if (bytes == nullptr) {
    return;
  }

  sendInput(
    static_cast<int64_t>(handle),
    reinterpret_cast<const uint8_t*>(bytes),
    static_cast<int32_t>(boundedCount)
  );
  env->ReleaseByteArrayElements(input, bytes, JNI_ABORT);
}

