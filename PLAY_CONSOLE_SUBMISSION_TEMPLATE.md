# Play Console Submission Template

Use this as a copy-ready baseline for your next Android release submission.

## App Basics

- App name: `Speed Driver`
- Package name: `com.ilabinformationtechnology.driver`
- Release artifact: `build/app/outputs/bundle/release/app-release.aab`

## Background Location Permission Declaration

### Why your app needs background location

`Speed Driver is a logistics driver app. Drivers receive and complete delivery assignments while actively working. Background location is required so live trip tracking and dispatch visibility continue when the app is minimized or the screen is off. This supports real-time operational safety, routing, and delivery status updates during active shifts.`

### User benefit

`Drivers and dispatchers get accurate live trip status and location continuity during active jobs, reducing missed assignments and improving delivery reliability.`

### When it is collected

`Location is used when the driver is checked in/on duty. Foreground location is used while the app is open; background location is used to maintain tracking continuity while the app is not visible.`

### In-app disclosure text

`Speed Driver needs background location so dispatch and trip tracking keep working when the app is minimized or the screen is off. This is used only during working/checked-in periods.`

## Foreground Service Declaration

### Foreground service type

- `location`

### Why foreground service is needed

`The app runs a location foreground service during active driver sessions to provide continuous location updates required for dispatch and trip monitoring.`

## Data Safety Form Draft

Adjust to your exact backend behavior before final submission.

- Location (precise): Collected
- Location (background): Collected when driver is checked in
- Photos/Media/Files: Collected when user uploads required proof images
- App info/performance (crash logs): Collected via Firebase Crashlytics
- Data is encrypted in transit: Yes (HTTPS API)
- Data deletion request support: Fill with your company process/policy

## App Access (For Review Team)

If login is required, provide:

- Test account username
- Test account password
- OTP bypass notes (if any)
- Steps to reach key features:
  1. Log in
  2. Open Dashboard
  3. Check in
  4. Accept or open active order
  5. Minimize app to validate background tracking behavior

## Release Notes Template

`This update improves app stability, background tracking reliability, and crash diagnostics. It also includes production signing and release infrastructure hardening.`

## Pre-Submission Checklist

- Upload AAB built with production key
- Confirm version code is incremented
- Complete Background Location declaration
- Complete Foreground Service declaration
- Complete Data Safety form
- Add privacy policy URL
- Provide app access credentials and review steps
