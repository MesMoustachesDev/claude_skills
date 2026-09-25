---
name: android-visual-loop
description: Boucle d'itération visuelle autonome sur une UI Android ou Wear OS — lancer un émulateur, builder, installer, capturer l'écran, LE REGARDER, corriger, recommencer. À utiliser dès qu'une modification d'UI Android/Compose/Wear doit être vérifiée pour de vrai (mise en page, débordement de texte, écran rond, locales, thème sombre, tailles de police), plutôt que codée à l'aveugle. Couvre aussi le diagnostic d'un appareil figé et la lecture de signatures d'API depuis un AAR quand la doc ne suffit pas.
---

# Boucle visuelle Android / Wear OS

Le but : pouvoir corriger une UI seul, par allers-retours, sans demander une capture à chaque essai.

## Le principe

```
build → install → launch → screencap → Read le .png → corriger → recommencer
```

**L'étape qui rend tout possible est `Read` sur le fichier `.png`.** Elle affiche l'image visuellement. Sans elle on code à l'aveugle et on livre des débordements, du texte tronqué et des boutons hors écran. Une capture qu'on ne regarde pas ne sert à rien.

Un cycle coûte ~1 min (build incrémental inclus). C'est assez rapide pour **tester une variable à la fois** — indispensable, sinon on ne sait pas quel changement a produit l'effet.

## Lancer l'émulateur

```bash
~/Library/Android/sdk/emulator/emulator -list-avds
nohup ~/Library/Android/sdk/emulator/emulator -avd <AVD> -no-snapshot-load > /tmp/emu.log 2>&1 &
```

Attendre le boot avec une boucle **en background** (`run_in_background: true`) : elle sort toute seule et notifie.

```bash
until adb -s emulator-5554 shell getprop sys.boot_completed 2>/dev/null | grep -q 1; do sleep 5; done
```

Si rien n'apparaît dans `adb devices`, lire `/tmp/emu.log`. Sur Apple Silicon, une image **arm 32 bits** ne démarre pas :
`PANIC: CPU Architecture 'arm' is not supported by the QEMU2 emulator`. Vérifier l'ABI avant de s'acharner :

```bash
grep -E "abi.type|image.sysdir" ~/.android/avd/<AVD>.avd/config.ini   # veut arm64-v8a
```

Toujours cibler explicitement (`-s <serial>`) : un téléphone physique et un émulateur cohabitent souvent.

## Installer et lancer

```bash
adb -s <serial> install -r -d <chemin>.apk
adb -s <serial> shell am force-stop <pkg>
adb -s <serial> shell am start -n <pkg>/<activity-complète>
```

⚠️ **Le chemin de l'APK n'est pas toujours celui qu'on croit.** Un projet qui redéfinit `buildDir` (fréquent avec Flutter) sort ailleurs. Ne pas deviner :

```bash
find . -name "*.apk" -path "*outputs*" -newermt "-10 minutes"
```

Attendre que l'activité soit réellement au premier plan avant de capturer :

```bash
until adb -s <serial> shell dumpsys activity activities 2>/dev/null | grep -q "<Activity>"; do sleep 1; done
```

## Capturer

```bash
adb -s <serial> exec-out screencap -p > /tmp/shot.png
```

`exec-out`, **pas** `adb shell` : le second passe par un pty et peut corrompre le binaire. Puis `Read /tmp/shot.png`.

Pour des captures stables, couper les animations :

```bash
adb -s <serial> shell settings put global window_animation_scale 0
adb -s <serial> shell settings put global transition_animation_scale 0
adb -s <serial> shell settings put global animator_duration_scale 0
```

Une capture prise trop tôt attrape une animation en cours et fait croire à un bug de mise en page. En cas de doute, recapturer 3 s plus tard avant de conclure.

Pour une animation ou un geste : `adb shell screenrecord --time-limit 10 /sdcard/r.mp4` puis `adb pull`.

## Changer la locale

La bonne méthode (Android 13+), par application, sans toucher au système :

```bash
adb -s <serial> shell cmd locale set-app-locales <pkg> --locales fr-FR
adb -s <serial> shell am force-stop <pkg>
adb -s <serial> shell am start -n <pkg>/<activity>
```

**Ne pas perdre de temps avec `setprop persist.sys.locale`** : ça exige `adb root`, ça ne prend pas effet sur le framework déjà lancé, et `am get-config` continue de renvoyer l'ancienne locale.

Vérifier ce que l'appareil applique réellement :

```bash
adb -s <serial> shell am get-config     # locale, taille d'écran, round/notround, densité
```

**Toujours tester la locale la plus verbeuse**, pas seulement l'anglais. L'allemand et le français sont ~30 % plus longs ; c'est là que les boutons débordent. Les glyphes CJK font environ le double de large d'un caractère latin : compter en largeur, pas en nombre de caractères.

## Thème, densité, police

```bash
adb shell cmd uimode night yes            # thème sombre | no | auto
adb shell settings put system font_scale 1.3   # accessibilité
adb shell wm density 560                  # puis: adb shell wm density reset
adb shell wm size 1080x2400               # puis: adb shell wm size reset
```

`wm size` / `wm density` évitent de créer un AVD par format pour vérifier qu'une mise en page tient.

## Interagir

```bash
adb shell input tap <x> <y>
adb shell input swipe <x1> <y1> <x2> <y2> <ms>
adb shell input text "bonjour"
adb shell input keyevent KEYCODE_BACK
adb shell am start -a android.intent.action.VIEW -d "monscheme://route"   # deep link
```

Les coordonnées se déduisent de la capture précédente et de `am get-config`.

## Atteindre un état difficile à provoquer

Certains états dépendent du réseau, d'un appairage ou d'une erreur serveur. Pour les voir :

1. Forcer la condition dans le code, avec un marqueur repérable :
   ```kotlin
   true, // TEMP VISUAL TEST
   ```
2. Builder, capturer, régler la mise en page.
3. **Annuler le forçage**, puis prouver qu'il ne reste rien :
   ```bash
   grep -rn "TEMP VISUAL TEST" <src>   # doit être vide
   ```
4. Rebuilder en `release` avant de commiter.

C'est légitime et rapide. Ce qui ne l'est pas, c'est d'en laisser une trace dans un commit — donc le grep de contrôle n'est pas optionnel.

## Logs

```bash
adb -s <serial> logcat -c                        # vider avant le test
adb -s <serial> logcat -d -s MonTag AndroidRuntime
adb -s <serial> logcat -b crash -d -t 50         # crashs natifs et tombstones
```

## Spécificités Wear OS

Une montre ronde n'est pas un petit téléphone.

- **La place utile est le carré inscrit dans le cercle.** En 384×384 (`sw192dp`), il reste ~135 dp exploitables en hauteur. Un emoji décoratif coûte une ligne qu'on n'a pas.
- **Un bouton pleine largeur se fait rogner les coins par le cercle.** Prévoir un padding horizontal généreux, ou utiliser un composant prévu pour le bord.
- **`EdgeButton` se rétrécit vers le bas de l'écran.** Il tronque les libellés longs *quelle que soit sa taille* — `EdgeButtonSize.Large` n'aide pas, il empiète juste sur le contenu. Deux leviers qui marchent : un **libellé d'un seul mot**, et un `style` de texte plus petit (`labelSmall`). L'explication va dans le message au-dessus, pas dans le bouton.
- **`ScreenScaffold` + `edgeButton` est la bonne structure** : le contenu défile sous le bouton, qui se déploie en fin de scroll. Son lambda `content` fournit déjà le `contentPadding` — pas besoin d'Horologist pour ça.
  ```kotlin
  ScreenScaffold(
      scrollState = columnState,
      edgeButton = { EdgeButton(onClick = …) { Text(…) } },
  ) { contentPadding ->
      TransformingLazyColumn(state = columnState, contentPadding = contentPadding) { … }
  }
  ```
  Si le contenu tient sans défiler, le bouton s'affiche déployé d'emblée — préférable quand ce bouton est le CTA principal, car collapsé il ne se lit pas comme une action.
- **Le texte courbe est coupé net, sans ellipse.** `curvedText` plafonne à ~70° pour du contenu statique : au-delà de deux mots, la phrase est tranchée en plein milieu. Passer `maxSweepAngle` (180f tient une phrase courte complète).
- Budget mesuré à 180° sur un écran 384×384 : **~24 caractères latins**, ~10 idéogrammes. Calibrer sur une locale, puis raccourcir celles qui dépassent.
- Pas de `timeText` par défaut si l'écran est dense : `timeText = { }`.

## Lire une signature d'API dans un AAR

Quand la doc est muette ou périmée (fréquent sur Wear Compose), la vérité est dans le binaire du cache Gradle :

```bash
unzip -o ~/.gradle/caches/modules-2/files-2.1/<group>/<artifact>/<version>/*/<artifact>-<version>.aar -d /tmp/aar
unzip -o /tmp/aar/classes.jar -d /tmp/cls 'chemin/du/package/*'
javap -classpath /tmp/cls <package>.<Fichier>Kt
```

`javap` donne l'ordre et les types des paramètres, pas leurs noms. En cas de doute sur un nom : **appeler en positionnel**, ça compile sans pari. Les noms se confirment ensuite au premier build.

Sert aussi à trancher une migration : décompiler l'ancienne et la nouvelle version, comparer les signatures réellement utilisées, et savoir avant de bumper ce qui va casser.

## Diagnostiquer un appareil figé

Un écran figé sur une app ne veut pas dire que l'app est en cause : si `system_server` meurt, SurfaceFlinger garde la dernière image affichée.

```bash
adb shell uptime                                    # kernel rebooté ou pas ?
adb shell "ps -A -o PID,ETIME,CMD | grep -E 'system_server|zygote64|bootanimation'"
adb shell "service check window; service check activity"   # 'not found' = framework pas remonté
adb shell logcat -b crash -d | tail -40
adb shell df -h /data
```

Un PID de `system_server` récent avec un `uptime` de plusieurs jours = redémarrage du framework, pas de l'appareil. Relever le PID **plusieurs fois** avant de parler de boucle : un ou deux redémarrages ne sont pas un crash loop.

`No space left on device` dans une erreur binder désigne le **buffer binder**, pas le stockage — vérifier `df` avant d'envoyer quelqu'un supprimer des fichiers.

Le mirroring d'Android Studio (`/data/local/tmp/.studio/libscreen-sharing-agent.so`) peut planter et emporter `system_server`. Fermer « Running Devices » avant de conclure à un bug applicatif.

**`adb reboot` sur un appareil personnel se demande avant de se faire.**

## Pièges divers

- `timeout` n'existe pas par défaut sur macOS — écrire des boucles `until … done`.
- Décrire ce que l'utilisateur voit à partir d'un nom de process est une extrapolation. S'en tenir à ce qui est observable, ou demander.
- Vérifier la version réellement installée avant de diagnostiquer un comportement :
  ```bash
  adb shell dumpsys package <pkg> | grep -E "versionName|versionCode"
  ```
  La moitié des « bugs » sont un binaire qui n'est pas celui qu'on croit.
