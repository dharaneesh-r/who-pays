# Play Core is referenced by Flutter's deferred-components support, which this
# app does not use. Without these rules R8 fails the release build on missing
# classes that are never actually reached.
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# Keep the Flutter embedding entry points.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }
