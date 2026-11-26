# Preserve Shop native background notification engine & FCM receivers
-keep class com.example.shop.ShopNotificationReceiver { *; }
-keep class com.example.shop.ShopBootReceiver { *; }
-keep class com.example.shop.ShopPeriodicJobService { *; }
-keep class com.example.shop.ShopNotificationConfig { *; }
-keep class com.example.shop.ShopAlarmScheduler { *; }

# Preserve Gson TypeToken and flutter_local_notifications models under R8
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class com.dexterous.flutterlocalnotifications.** { *; }
