# Validation

Ce document décrit la méthodologie utilisée pour valider que
`voltapeak_batchApp` produit les bons résultats, en deux temps :

1. **Parité numérique avec voltapeakApp** — garantie structurelle, les
   fonctions d'analyse étant reprises à l'identique.
2. **Validation propre au batch** — spécifique à cette app : parsing,
   parallélisme, agrégation XLSX multi-électrodes, gestion d'erreurs.

## 1. Parité numérique avec voltapeakApp (et donc Python)

Les cinq fichiers suivants sont **identiques byte-pour-byte** à ceux de
[`scadinot/voltapeakApp`](https://github.com/scadinot/voltapeakApp) :

| Fichier | Rôle |
|---|---|
| `SavitzkyGolay.swift` | Filtre Savitzky-Golay scipy-exact |
| `WhittakerASPLS.swift` | asPLS Zhang 2020 |
| `SignalProcessing.swift` | Détection de pic + gradient numpy |
| `SWVFileReader.swift` | Lecture/parse `.txt` SWV |
| `VoltammetryData.swift` | Modèles de données |

La validation bit-exact (à la 6ᵉ décimale) contre la référence Python
(`scipy`, `pybaselines`) a été réalisée dans `voltapeakApp` et est
documentée ici :
[voltapeakApp/VALIDATION.md](https://github.com/scadinot/voltapeakApp/blob/main/VALIDATION.md).

Cette validation n'est **pas rejouée** ici. Pour la vérifier en pratique :

1. Choisir un fichier SWV de test.
2. L'ouvrir dans `voltapeakApp` → noter le pic affiché.
3. Le placer seul dans un dossier et lancer l'app `voltapeak_batch`
   (scheme du repo `voltapeak_batchApp`) dessus.
4. Ouvrir le classeur récapitulatif : le pic dans l'unique ligne doit
   être identique à celui affiché par `voltapeakApp` (mêmes décimales).

Toute divergence indiquerait une régression dans la copie des fichiers
d'analyse — à corriger immédiatement (`diff` direct des `.swift` avec
`voltapeakApp`).

## 2. Validation propre au batch

### (a) Jeu de données et convention de nommage

Préparer un dossier `validation_set/` contenant au moins :

```
validation_set/
├── ESSAI1_C01.txt   # base ESSAI1, électrode C01
├── ESSAI1_C02.txt   # base ESSAI1, électrode C02
├── ESSAI2_C01.txt   # base ESSAI2, électrode C01
├── ESSAI2_C02.txt   # base ESSAI2, électrode C02
├── ESSAI2_C03.txt   # base ESSAI2, électrode C03
└── HORS_CONVENTION.txt   # cas hors pattern <base>_C<NN>.txt
```

Chaque fichier au format :
```
Potentiel (V)\tCourant (A)
-0.500\t-1.234e-06
...
```

### (b) Comparaison visuelle des PNG (Python vs Swift)

Lancer les deux pipelines sur `validation_set/` :

```bash
# Python (référence)
git clone https://github.com/scadinot/voltapeak_batch.git
cd voltapeak_batch
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python -m voltapeak_batch     # GUI : sélectionner validation_set/
mv "../validation_set (results)" /tmp/python_output

# Swift (cible)
# Xcode ⌘R, sélectionner validation_set/, paramètres identiques
mv "validation_set (results)" /tmp/swift_output

# Comparaison des dimensions PNG
for f in /tmp/python_output/*.png; do
  name=$(basename "$f")
  diff <(magick identify -format "%w %h" "$f") \
       <(magick identify -format "%w %h" "/tmp/swift_output/$name") \
       && echo "OK $name"
done
```

Critère : dimensions identiques. La comparaison pixel par pixel n'est
PAS attendue car `matplotlib` et SwiftUI Charts diffèrent légèrement sur
les fontes et l'anticrénelage. Les **courbes** doivent être superposables.

### (c) Comparaison des valeurs agrégées

Ouvrir `python_output/validation_set.xlsx` et
`swift_output/validation_set.xlsx` dans Numbers ou Excel.

Vérifier pour chaque ligne / colonne :

| Colonne | Tolérance attendue |
|---|---|
| `Base` | identité stricte |
| `Fréq (Hz)` | 50.0 ↔ 50.0 |
| `<elec> - Tension (V)` | écart < 1e-6 V |
| `<elec> - Courant (A)` | écart < 1e-9 A |
| `<elec> - Charge (C)` | formule = `=<col_courant><ligne>/<col_freq><ligne>` |

Petite dérive possible : l'asPLS converge sur les **poids**, pas sur la
baseline ; pour `tol = 1e-2` et `maxIter = 25` l'écart numérique attendu
entre les deux implémentations reste sous `1e-6` en relatif.

### (d) Comparaison CSV / XLSX par fichier (si option activée)

```bash
python -c "
import pandas as pd
for name in ('ESSAI1_C01', 'ESSAI1_C02'):
    py = pd.read_csv(f'/tmp/python_output/{name}.csv')
    sw = pd.read_csv(f'/tmp/swift_output/{name}.csv')
    diff = (py.values - sw.values).__abs__().max()
    print(name, 'max abs diff =', diff)
"
```

Critère : `max abs diff < 1e-6` sur toutes les colonnes.

### (e) Cas d'erreur

À tester explicitement :

| Cas | Comportement attendu |
|---|---|
| Fichier vide | Ligne rouge dans le journal, autres fichiers traités |
| Fichier sans 2 colonnes | Ligne rouge, autres fichiers traités |
| Fichier avec courants tous nuls | Filtrés en lecture → erreur « données insuffisantes » |
| Fichier hors pattern `<base>_C<NN>.txt` | Apparaît dans le récapitulatif avec son nom complet en *Base* et colonnes électrode vides |
| Dossier sans `.txt` | Message « Aucun fichier .txt trouvé » |
| Re-lancement sur le même dossier | Anciens `.png/.csv/.xlsx` supprimés avant écriture |

### (f) Mode séquentiel vs parallèle

Lancer la même validation avec **traitement parallèle désactivé**. Le
récapitulatif Excel doit être **bit-identique** entre les deux modes
(l'agrégation trie par ordre d'origine des fichiers, indépendamment de
l'ordre de complétion des tâches). Si ce n'est pas le cas, c'est le signe
d'un data-race — à corriger.

## 3. Comment reproduire la validation

1. Cloner `voltapeak_batchApp` et son équivalent Python `voltapeak_batch`.
2. Préparer le dossier de fixtures `validation_set/` (cf. § 2.a).
3. Lancer le pipeline Python (référence) puis le pipeline Swift sur les
   mêmes fixtures.
4. Vérifier les six points (a)-(f) ci-dessus.
5. Optionnel : comparer un pic individuel entre `voltapeak_batchApp` et
   `voltapeakApp` sur le même fichier (cf. § 1).

## État de la validation

✅ Parité numérique avec `voltapeakApp` (donc Python) : structurellement
garantie par la reprise byte-pour-byte des fichiers d'analyse — cf.
[voltapeakApp/VALIDATION.md](https://github.com/scadinot/voltapeakApp/blob/main/VALIDATION.md).

✅ Agrégation multi-électrodes : structure récapitulative + formules Excel
validée manuellement sur dossiers de fixtures.

✅ Cohérence parallèle vs séquentiel : `BatchFileResult` collectés puis
triés par ordre d'origine, l'ordre de complétion des tâches n'a pas
d'impact sur la sortie.

⚠️ Tests unitaires automatisés : absents (dette technique consciente,
voir [DEVELOPMENT.md § Tests](DEVELOPMENT.md#tests) pour pistes).
