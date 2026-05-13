# Validation

Procédure pour vérifier que `voltapeak_batchApp` (Swift) produit des
résultats équivalents à
[`voltapeak_batch`](https://github.com/scadinot/voltapeak_batch) (Python) sur
les mêmes fichiers d'entrée.

## Postulat

Les fonctions d'analyse (`SWVFileReader`, `SavitzkyGolay`, `SignalProcessing`,
`WhittakerASPLS`) sont **identiques** à celles de
[`voltapeakApp`](https://github.com/scadinot/voltapeakApp). Cette dernière a
déjà été validée à la 6ᵉ décimale par rapport à `scipy` et `pybaselines`
(cf. `VALIDATION.md` de `voltapeakApp`).

La validation batch porte donc sur :
1. la **bonne intégration** de ces fonctions dans le pipeline batch ;
2. la **fidélité de l'agrégation** (regex `<base>_C<NN>.txt`, ordre des
   électrodes, formule Excel `=Courant/Fréq`) ;
3. la **gestion des erreurs** par fichier sans interrompre le lot.

## Jeu de données de validation

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

## Procédure

### 1. Exécution Python (référence)

```bash
git clone https://github.com/scadinot/voltapeak_batch.git
cd voltapeak_batch
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python -m voltapeak_batch
# GUI : sélectionner validation_set/, paramètres par défaut, "Lancer l'analyse"
# Sortie : validation_set (results)/
mv "../validation_set (results)" /tmp/python_output
```

### 2. Exécution Swift (cible)

Dans Xcode : `Cmd+R`, sélectionner `validation_set/`, paramètres identiques,
lancer.

```bash
mv "validation_set (results)" /tmp/swift_output
```

### 3. Comparaisons

#### 3.1 Comparaison visuelle des PNG

```bash
for f in /tmp/python_output/*.png; do
  name=$(basename "$f")
  diff <(magick identify -format "%w %h" "$f") \
       <(magick identify -format "%w %h" "/tmp/swift_output/$name") \
       && echo "OK $name"
done
```

Critère : dimensions identiques. La comparaison pixel par pixel n'est PAS
attendue car `matplotlib` et SwiftUI Charts diffèrent légèrement sur les
fontes et l'anticrénelage. Les **courbes** doivent être superposables.

#### 3.2 Comparaison des valeurs agrégées

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

#### 3.3 Comparaison des CSV / XLSX par fichier (si option activée)

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

## Cas d'erreur

À tester explicitement :

| Cas | Comportement attendu |
|---|---|
| Fichier vide | Ligne rouge dans le journal, autres fichiers traités |
| Fichier sans 2 colonnes | Ligne rouge, autres fichiers traités |
| Fichier avec courants tous nuls | Filtrés en lecture → erreur « données insuffisantes » |
| Fichier hors pattern `<base>_C<NN>.txt` | Apparaît dans le récapitulatif avec son nom complet en *Base* et colonnes électrode vides |
| Dossier sans `.txt` | Message « Aucun fichier .txt trouvé » |
| Re-lancement sur le même dossier | Anciens `.png/.csv/.xlsx` supprimés avant écriture |

## Mode séquentiel vs parallèle

Lancer la même validation avec **traitement parallèle désactivé**. Le
récapitulatif Excel doit être **bit-identique** entre les deux modes
(l'agrégation trie par ordre d'origine des fichiers, indépendamment de
l'ordre de complétion des tâches).
