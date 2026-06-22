# 📱💻 ANABOK CLEANER — Guide d'installation et compilation

## 🎯 Ce que fait l'application

**Module 1 — Gestionnaire de fichiers**
- Scan complet du stockage (Android ou Windows)
- Affichage par taille, nom, date
- Filtres : Images, Vidéos, Audios, Documents, APK, Gros fichiers (+50MB)
- Recherche en temps réel
- Sélection multiple → suppression groupée
- Affiche l'espace libéré

**Module 2 — Téléchargeur vidéo**
- Coller un lien YouTube, TikTok, Facebook, Instagram, Twitter, Dailymotion...
- Choisir la qualité : 1080p / 720p / 480p / 360p / Meilleure
- Mode MP3 audio uniquement
- Suivi de progression en temps réel
- Historique des téléchargements

---

## 🛠️ ÉTAPE 1 — Installer Flutter SDK

### Windows
1. Télécharger Flutter SDK : https://docs.flutter.dev/get-started/install/windows
2. Extraire dans `C:\flutter`
3. Ajouter `C:\flutter\bin` au PATH système
4. Ouvrir PowerShell et exécuter : `flutter doctor`

### Vérifier l'installation
```bash
flutter doctor
```
Tout doit être ✅ sauf ce que tu n'utilises pas.

---

## 🛠️ ÉTAPE 2 — Installer les dépendances

```bash
cd anabok_cleaner
flutter pub get
```

---

## 📦 ÉTAPE 3 — Compiler l'APK Android

### Prérequis Android
- Android Studio installé (pour les SDK Android)
- `flutter doctor` montre ✅ pour Android

### Commandes
```bash
# APK simple (debug, pour tester)
flutter build apk --debug

# APK release (à installer sur téléphone)
flutter build apk --release

# APK séparés par architecture (plus léger)
flutter build apk --split-per-abi --release
```

### Où trouver l'APK ?
```
anabok_cleaner/build/app/outputs/flutter-apk/
├── app-release.apk          ← APK universel
├── app-arm64-v8a-release.apk  ← Pour Android 64-bit (recommandé)
├── app-armeabi-v7a-release.apk ← Pour Android 32-bit
```

### Installer sur téléphone
1. Copier l'APK sur le téléphone
2. Activer "Sources inconnues" dans les paramètres Android
3. Ouvrir le fichier APK sur le téléphone

---

## 🖥️ ÉTAPE 4 — Compiler pour Windows

### Prérequis Windows
- Visual Studio 2022 avec workload "Desktop development with C++"
- `flutter doctor` montre ✅ pour Windows

```bash
# Activer le support Windows
flutter config --enable-windows-desktop

# Compiler
flutter build windows --release
```

### Où trouver l'exe ?
```
anabok_cleaner/build/windows/runner/Release/
└── anabok_cleaner.exe   ← L'application Windows
```

---

## 📥 ÉTAPE 5 — Installer yt-dlp (pour le téléchargement vidéo)

### Sur Windows
1. Télécharger `yt-dlp.exe` : https://github.com/yt-dlp/yt-dlp/releases/latest
2. Créer le dossier `C:\yt-dlp\`
3. Placer `yt-dlp.exe` dans ce dossier
4. (Recommandé) Installer FFmpeg pour les meilleures qualités :
   - Télécharger FFmpeg : https://www.gyan.dev/ffmpeg/builds/
   - Ajouter au PATH

### Sur Android (via Termux)
```bash
# Installer Termux depuis F-Droid : https://f-droid.org/packages/com.termux/
# Ouvrir Termux et exécuter :
pkg update && pkg upgrade
pkg install python yt-dlp ffmpeg
```

---

## ⚙️ Configuration des permissions Android

Le fichier `android_manifest_reference.xml` fourni contient toutes les permissions nécessaires.

Copiez son contenu dans :
```
anabok_cleaner/android/app/src/main/AndroidManifest.xml
```

---

## 🔧 Résolution de problèmes courants

### "Permission denied" sur Android 11+
→ L'app demande la permission MANAGE_EXTERNAL_STORAGE
→ Aller dans Paramètres → Apps → ANABOK CLEANER → Permissions → Accès à tous les fichiers

### yt-dlp non trouvé sur Windows
→ Vérifier que `C:\yt-dlp\yt-dlp.exe` existe
→ Ou ajouter yt-dlp au PATH Windows et relancer l'app

### Scan lent sur Android
→ Normal pour un premier scan complet
→ Le stockage interne Android peut avoir 50 000+ fichiers

---

## 📁 Structure du projet

```
anabok_cleaner/
├── lib/
│   ├── main.dart                    ← Entrée de l'app
│   └── screens/
│       ├── home_screen.dart         ← Navigation principale
│       ├── file_manager_screen.dart ← Module fichiers
│       └── video_downloader_screen.dart ← Module vidéos
├── pubspec.yaml                     ← Dépendances Flutter
└── android_manifest_reference.xml   ← Permissions Android
```

---

## 🎨 Design

- Thème sombre : fond `#0F0F1A`
- Accent rouge-orange : `#E94560` → `#FF6B35`
- Accent cyan : `#4ECDC4`
- Police : Poppins (Google Fonts)
- Branding ANABOK GROUP

---

*Développé pour ANABOK GROUP — Lomé, Togo*
