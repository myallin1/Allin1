# Google Sign-In / Firebase keep rules for future release builds.
# Current release config has minify disabled, but these rules protect
# the auth path if minification is re-enabled later.

-keep class com.google.android.gms.auth.** { *; }
-keep class com.google.android.gms.common.api.** { *; }
-keep class com.google.android.gms.common.internal.** { *; }
-keep class com.google.android.gms.tasks.** { *; }
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.common.GooglePlayServicesUtil { *; }
-dontwarn com.google.android.gms.**
-dontwarn com.google.firebase.**
