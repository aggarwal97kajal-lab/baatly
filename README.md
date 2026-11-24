# BAATLY — Every Conversation Matters

Cross-platform messaging app (Flutter). This repo is at **Milestone 1: design system + screens (demo build)**.

## App kaise download karein (Android)

1. Ye link phone par kholo: **https://github.com/aggarwal97kajal-lab/baatly/releases/latest/download/baatly.apk**
2. Download hone ke baad file kholo. Agar phone poochhe "Unknown apps install karne dein?" to us baar **Allow** karo.
3. Install → Open.

Har baar `main` branch par naya code aata hai, GitHub Actions apne-aap naya APK bana kar upar wale link par daal deta hai
(lagbhag 8–12 minute). Build ka status: repo ka **Actions** tab.

## Abhi kya chalta hai (demo)

- Animated splash, welcome, 3-page intro
- Phone number + OTP screens (**demo:** SMS nahi jaata, koi bhi 6 digit chalega)
- Profile setup (naam, username check, about), permissions screen
- Chats list: search, filters (All / Unread / Groups / Favourites), pin, mute, archive (long-press)
- Chat: message bhejna, sent → delivered → read ticks, typing indicator, demo reply, reply/copy/delete, reactions, voice-note bubble
- Chat info, chat wallpaper (Mitti Dots, Desi, Baatcheet, Mausam, Raat, Saada)
- Status: dekhna (progress bar, tap/hold), text status banana
- Calls: history + demo call screen (awaaz nahi)
- Light / Dark / System theme, "animations kam karein"

Sab data sirf phone par hai aur app band karne par wapas sample data aa jaata hai. Server abhi nahi hai.

## Project structure

```
lib/
  main.dart
  theme/        tokens.dart (Mitti colours), app_theme.dart
  data/         models.dart, app_state.dart (in-memory demo state)
  widgets/      common.dart (Avatar, ticks, typing dots, wallpaper…)
  screens/
    onboarding/ splash, welcome, intro, phone, otp, profile, permissions
    home/       home_shell, chats, status, calls, community tabs
    chat/       chat, chat info, new chat
    settings/   you, appearance, wallpaper
assets/         brand marks, wallpapers, Poppins font (OFL)
android_overrides/res/   launcher icon + launch screen, copied in by CI
.github/workflows/build-apk.yml
```

`android/` folder repo mein nahi hai: CI `flutter create` se banata hai aur `android_overrides/` se branding daalta hai.
Jab Firebase / native code chahiye hoga (Milestone 2), tab `android/` ko repo mein commit kar denge.

## Developer ke liye (computer par)

```bash
flutter create --org app.baatly --project-name baatly --platforms=android .
cp -r android_overrides/res/. android/app/src/main/res/
flutter pub get
flutter run
```

Status details: [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md)
