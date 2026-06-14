# R8 rules applied automatically to any consumer of the SwiftTUI Android host.
#
# JNI_OnLoad binds the native methods by class name + method name/signature
# against sh.swifttui.android.host.SwiftTUIJni (see src/main/jni/swift_tui_jni.cpp).
# A consumer's R8 pass must therefore not rename or remove that class or its
# native methods, or the bind silently fails at load.
-keep class sh.swifttui.android.host.SwiftTUIJni {
    *;
}
