# Distribution

Ce guide explique comment produire une version distribuable de
`voltapeak_batchApp` (`.app`, `.zip`, `.dmg`). Trois options selon le
contexte : **CI automatisée**, **signature locale ad-hoc**, ou
**notarisation Apple**. Le canevas est identique entre les trois apps
de la famille `voltapeak*` ; voir
[`voltapeakApp/DISTRIBUTION.md`](https://github.com/scadinot/voltapeakApp/blob/main/DISTRIBUTION.md) et
[`voltapeak_loopsApp/DISTRIBUTION.md`](https://github.com/scadinot/voltapeak_loopsApp/blob/main/DISTRIBUTION.md).

## Prérequis communs

Le projet est livré avec `CODE_SIGN_IDENTITY = "-"` (ad-hoc) et
`ENABLE_APP_SANDBOX = NO`. Une build Release locale produit donc une
application exécutable telle quelle sur la machine de développement.

Pour les versions distribuables, vérifier dans le pbxproj :

```
MARKETING_VERSION             = 1.0.0
CURRENT_PROJECT_VERSION       = 1
PRODUCT_BUNDLE_IDENTIFIER     = com.cadinot.voltapeak-batch
MACOSX_DEPLOYMENT_TARGET      = 26.1
```

---

## Option 0 — CI GitHub Actions

**Non configurée pour `voltapeak_batchApp`.** Pour un exemple de
workflows GitHub Actions (`build-artifact.yml` + `release.yml`), voir
[`voltapeak_loopsApp/.github/workflows/`](https://github.com/scadinot/voltapeak_loopsApp/tree/main/.github/workflows).
Le squelette est facilement adaptable à ce repo :

- macOS runner `macos-26` (ou `macos-latest`).
- `xcodebuild archive ... CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual`.
- `ditto -c -k --keepParent` pour empaqueter en zip.
- Upload artifact + création release sur tag `v*`.

---

## Option 1 — Distribution locale ad-hoc (sans notarisation)

Pour usage personnel, prototype, ou diffusion au sein d'une équipe
restreinte.

### Build Release locale

```bash
xcodebuild -project voltapeak_batch.xcodeproj \
           -scheme voltapeak_batch \
           -configuration Release \
           -derivedDataPath ./build
open ./build/Build/Products/Release/voltapeak_batch.app
```

Le binaire est inutilisable en l'état **sur une autre machine**
(Gatekeeper refusera) ; pour ça, voir l'option 2.

### Archive depuis Xcode

1. **Archive** : `Product → Destination → Any Mac` puis `Product →
   Archive`.
2. **Export** dans Organizer : `Distribute App → Copy App → Next →
   choisir un dossier`.

Résultat : un fichier `voltapeak_batch.app`.

### Créer un ZIP

```bash
ditto -c -k --keepParent voltapeak_batch.app voltapeak_batch.zip
```

### Créer un DMG

```bash
hdiutil create -volname "voltapeak_batch" \
               -srcfolder voltapeak_batch.app \
               -ov -format UDZO \
               voltapeak_batch-1.0.0.dmg
```

### Limitation : warning au premier lancement

Sans notarisation, macOS affiche au premier lancement :

> *« voltapeak_batch ne peut pas être ouvert car il provient d'un
> développeur non identifié »*

L'utilisateur doit alors **clic droit → Ouvrir** puis confirmer dans la
boîte de dialogue. Les lancements suivants sont normaux.

---

## Option 2 — Distribution publique (avec notarisation Apple)

Pour diffusion large (site web, distribution à des partenaires externes,
etc.) sans warning au lancement.

### Prérequis additionnels

- Compte **Apple Developer Program** actif (99 €/an).
- Hardened Runtime activé dans Signing & Capabilities :
  ```
  ✅ Hardened Runtime
  ```
- Certificat **Developer ID Application** installé dans le Keychain.

### Étapes

```bash
# Signature
codesign --force --options runtime \
         --sign "Developer ID Application: <Votre nom> (<TEAM_ID>)" \
         --timestamp \
         voltapeak_batch.app

# Vérification
codesign -dv --verbose=4 voltapeak_batch.app
spctl -a -v voltapeak_batch.app

# Empaqueter pour notarisation
ditto -c -k --keepParent voltapeak_batch.app voltapeak_batch.zip

# Soumettre à Apple (≈ 1-5 min)
xcrun notarytool submit voltapeak_batch.zip \
      --keychain-profile "AC_PROFILE" \
      --wait

# Agrafer le ticket dans le bundle
xcrun stapler staple voltapeak_batch.app
```

La création de `AC_PROFILE` se fait une seule fois :

```bash
xcrun notarytool store-credentials AC_PROFILE \
      --apple-id "<email>" \
      --team-id "<TEAM_ID>" \
      --password "<app-specific-password>"
```

### DMG notarisé

```bash
hdiutil create -volname "voltapeak_batch" \
               -srcfolder voltapeak_batch.app \
               -ov -format UDZO \
               voltapeak_batch-1.0.0.dmg

codesign --sign "Developer ID Application: <...>" \
         --timestamp \
         voltapeak_batch-1.0.0.dmg

xcrun notarytool submit voltapeak_batch-1.0.0.dmg \
      --keychain-profile "AC_PROFILE" --wait
xcrun stapler staple voltapeak_batch-1.0.0.dmg
```

### Distribution App Store

Non supportée en l'état : il faudrait activer
`ENABLE_APP_SANDBOX = YES` et ajouter l'entitlement
`com.apple.security.files.user-selected.read-write`. Voir
[DEVELOPMENT.md](DEVELOPMENT.md) pour les ajustements nécessaires.

---

## Vérifications post-build

```bash
# Signature
codesign -dv --verbose=4 voltapeak_batch.app

# Entitlements et hardened runtime
codesign -d --entitlements - voltapeak_batch.app

# Validation Gatekeeper (si notarisé)
spctl -a -vv -t install voltapeak_batch.app
```

---

## Résolution de problèmes

| Symptôme | Cause | Solution |
|---|---|---|
| « voltapeak_batch.app est endommagé » | Attributs de quarantaine après téléchargement | `xattr -cr voltapeak_batch.app` |
| Warning « développeur non identifié » | App non notarisée | Clic droit → Ouvrir, ou notariser (option 2) |
| `notarytool` échoue | Compte Developer non actif / mot de passe d'app | Régénérer mot de passe d'app sur appleid.apple.com |
| L'app crashe sur d'autres Macs | macOS minimum incompatible | L'app exige macOS 26.1+ à cause de l'API et du framework Charts |

---

## Tailles indicatives

| Fichier | Taille |
|---|---|
| `voltapeak_batch.app` (bundle) | ≈ 5-10 Mo |
| `voltapeak_batch.dmg` (UDZO) | ≈ 3-7 Mo |
| `voltapeak_batch.zip` | ≈ 3-7 Mo |

---

## Méthodes de diffusion

| Canal | Pour |
|---|---|
| Email | < 25 Mo, audience restreinte |
| iCloud Drive / Dropbox | Diffusion interne via lien |
| GitHub Releases | Open source, publication officielle |
| Site web personnel | Distribution publique |

---

## Versioning

- `MARKETING_VERSION` (version publique, ex. `1.0.0`) : modifiée dans
  `project.pbxproj`.
- `CURRENT_PROJECT_VERSION` (build number, ex. `1`) : incrémentée à
  chaque release.
- Mise à jour de [CHANGELOG.md](CHANGELOG.md) à chaque release.
- Tag git annoté : `git tag -a v1.0.0 -m "Release 1.0.0"` puis
  `git push origin v1.0.0`.

---

## Références Apple

- [Distributing your app outside the App Store](https://developer.apple.com/documentation/xcode/distributing-your-app-outside-the-app-store)
- [Notarizing macOS Software](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [Hardened Runtime](https://developer.apple.com/documentation/security/hardened_runtime)
