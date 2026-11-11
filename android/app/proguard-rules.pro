# Keep Flutter engine and plugin registrants.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep classes referenced via reflection by Firebase/Crashlytics.
-keepattributes *Annotation*
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-dontwarn org.codehaus.mojo.animal_sniffer.IgnoreJRERequirement

# DataStore binds this class to libdatastore_shared_counter.so by its Java/JNI
# name. Keeping it prevents R8 from renaming the native methods in release APKs.
-keep class androidx.datastore.core.NativeSharedCounter { *; }

# Flutter's optional deferred-components support references Play Core classes
# even when the app does not bundle deferred components.
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task
-dontwarn com.google.android.gms.base.R$drawable

# flutter_callkit_incoming — keep the plugin + its Jackson-serialised entities
# (belt-and-suspenders; the plugin ships consumer rules, but pin them here so a
# release/R8 build can never strip the incoming-call machinery).
-keep class com.hiennv.flutter_callkit_incoming.** { *; }
-keep class com.fasterxml.** { *; }
-dontwarn com.fasterxml.jackson.**

# androidx.window extension/sidecar classes are provided by the OEM at runtime
# and referenced (optionally) via the androidx.window library pulled in by
# flutter_callkit_incoming's incoming-call activity — safe to not warn on.
-dontwarn androidx.window.extensions.WindowExtensions
-dontwarn androidx.window.extensions.WindowExtensionsProvider
-dontwarn androidx.window.extensions.area.ExtensionWindowAreaPresentation
-dontwarn androidx.window.extensions.layout.DisplayFeature
-dontwarn androidx.window.extensions.layout.FoldingFeature
-dontwarn androidx.window.extensions.layout.WindowLayoutComponent
-dontwarn androidx.window.extensions.layout.WindowLayoutInfo
-dontwarn androidx.window.sidecar.SidecarDeviceState
-dontwarn androidx.window.sidecar.SidecarDisplayFeature
-dontwarn androidx.window.sidecar.SidecarInterface$SidecarCallback
-dontwarn androidx.window.sidecar.SidecarInterface
-dontwarn androidx.window.sidecar.SidecarProvider
-dontwarn androidx.window.sidecar.SidecarWindowLayoutInfo
