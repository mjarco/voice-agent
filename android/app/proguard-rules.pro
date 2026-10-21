# flutter_local_notifications persists its scheduled notifications with Gson
# (README, "Release build configuration"). Without these rules R8 strips the
# generic signature of TypeToken and every schedule/cancel/reschedule throws
# "TypeToken must be created with a type argument" (#357).

# Gson, from https://github.com/google/gson/blob/main/examples/android-proguard-example/proguard.cfg
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

# The plugin's models are serialised by field name and read back by later
# builds, so their names must not change between builds.
-keep class com.dexterous.** { *; }
