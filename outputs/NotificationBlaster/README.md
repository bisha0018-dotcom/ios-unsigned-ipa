# Notification Blaster

A small SwiftUI iPhone app that queues a burst of 60 local notifications. Each notification gets an independently randomized delay between the chosen minimum and maximum. Stop removes the run's still-pending requests.

## iOS timing behavior

The app uses non-repeating `UNTimeIntervalNotificationTrigger` requests. Apple permits positive intervals for one-time triggers; its 60-second minimum applies to repeating triggers. The requested 0.5–2.5 second intervals can therefore be scheduled as one-shot requests. iOS controls presentation and does not promise exact wall-clock delivery. Several alerts may be grouped or shown close together. The counter reports requests accepted by the notification center, not confirmed presentations.

Pre-scheduling lets iOS deliver queued notifications when the app is in the background or closed. A run intentionally queues 60 requests and then ends; open the app and press Start again for another run. Notification permission is required. This project makes no network requests and uses no server, database, or login.

## Open in Xcode

Open `NotificationBlaster.xcodeproj` in Xcode and run the app on an iPhone simulator or device. The project targets iOS 16 and later and uses the bundle identifier `com.notificationblaster.iphone`. No third-party packages are required.
