# Distribution

Guide pour packager et distribuer `voltapeak_batchApp` en dehors du contexte
de développement.

## Sans signature (test interne)

Le projet est livré avec `CODE_SIGN_IDENTITY = "-"` (ad-hoc) et
`ENABLE_APP_SANDBOX = NO`. Une build Release locale produit une application
exécutable telle quelle sur la machine de développement :

```bash
xcodebuild -project voltapeak_batch.xcodeproj \
           -scheme voltapeak_batch \
           -configuration Release \
           -derivedDataPath ./build
open ./build/Build/Products/Release/voltapeak_batch.app
```

Le binaire est inutilisable en l'état sur une autre machine (Gatekeeper
refusera).

## Distribution sur d'autres machines

Pour distribuer `voltapeak_batch.app` hors App Store, deux étapes
réglementaires Apple sont nécessaires :

### 1. Signature avec un Developer ID

Prérequis : compte Apple Developer payant + certificat *Developer ID
Application*.

```bash
codesign --force --options runtime \
         --sign "Developer ID Application: <Votre nom> (<TEAM_ID>)" \
         --timestamp \
         voltapeak_batch.app
```

Vérification :

```bash
codesign -dv --verbose=4 voltapeak_batch.app
spctl -a -v voltapeak_batch.app
```

### 2. Notarisation Apple

```bash
# Créer un zip signé
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

## Création d'un DMG

Un script simple suffit :

```bash
hdiutil create -volname "voltapeak_batch" \
               -srcfolder voltapeak_batch.app \
               -ov \
               -format UDZO \
               voltapeak_batch-1.0.0.dmg
```

Le DMG doit lui aussi être signé puis notarisé pour passer Gatekeeper :

```bash
codesign --sign "Developer ID Application: <...>" \
         --timestamp \
         voltapeak_batch-1.0.0.dmg
xcrun notarytool submit voltapeak_batch-1.0.0.dmg \
      --keychain-profile "AC_PROFILE" --wait
xcrun stapler staple voltapeak_batch-1.0.0.dmg
```

## Distribution App Store

Non supportée en l'état : il faudrait activer `ENABLE_APP_SANDBOX = YES`
et ajouter l'entitlement `com.apple.security.files.user-selected.read-write`.
Voir [DEVELOPMENT.md](DEVELOPMENT.md) pour les ajustements nécessaires.

## Versioning

- `MARKETING_VERSION` (version publique, ex. `1.0.0`) : modifiée dans
  `project.pbxproj`.
- `CURRENT_PROJECT_VERSION` (build number, ex. `1`) : incrémentée à
  chaque release.
- Mise à jour de [CHANGELOG.md](CHANGELOG.md) à chaque release.
- Tag git annoté : `git tag -a v1.0.0 -m "Release 1.0.0"` puis
  `git push origin v1.0.0`.
