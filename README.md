# Kratos Clap

Clap visuel et sonore pour les tournages de KRATOS VISUALS.

## Ce que fait l'app

1. Affiche le slate (artiste, titre, séquence, prise, cadence) en blanc sur noir.
2. Choisit un rafraîchissement d'écran précis pour le flash, puis programme le bip pour qu'il
   sorte de l'enceinte exactement à cet instant (son calé sur l'image à l'échantillon près).
3. Après les frames blanches réglées (2 par défaut), affiche le logo en noir sur blanc.
4. Incrémente la prise automatiquement.
5. Étalonnage : mesure la latence réelle de la sortie audio (Bluetooth compris) au micro
   et la mémorise pour chaque enceinte.

## Contenu du dépôt

| Fichier | Rôle |
|---|---|
| `project.yml` | Description du projet pour XcodeGen (remplace le projet Xcode) |
| `.github/workflows/build.yml` | Instructions de compilation pour GitHub Actions |
| `KratosClap/*.swift` | Le code de l'app |
| `KratosClap/logo.png` | Logo KRATOS VISUALS détouré (fond transparent) |

## Remplacer le logo

- Format PNG, fond **transparent**, nommé exactement `logo.png`, dans le dossier `KratosClap/`.
- La couleur n'a pas d'importance : l'app le transforme en silhouette noire à partir de la transparence.
- Un logo sur fond blanc opaque donnerait un carré noir : il doit être détouré.
- Environ 1024 × 1024 px suffit.

## Compiler avec GitHub Actions

1. Crée un dépôt sur github.com (bouton « New »), par exemple `kratos-clap`.
2. Envoie tout le contenu de ce dossier dans le dépôt, avec GitHub Desktop
   (« Add an existing repository » puis « Publish ») ou par glisser-déposer
   sur la page du dépôt (« Add file » → « Upload files »).
   Vérifie que le dossier `.github/workflows/` est bien présent en ligne.
3. Onglet **Actions** du dépôt : la compilation démarre toute seule à chaque envoi sur `main`.
   Tu peux aussi la relancer avec « Compiler Kratos Clap » → « Run workflow ».
4. Pastille verte : clique sur l'exécution et télécharge l'artifact `KratosClap-ipa` en bas de page.
   Dézippe-le pour obtenir `KratosClap.ipa`.
5. Pastille rouge : clique sur l'étape en échec pour lire l'erreur
   (cherche les lignes contenant `error:`). Le journal complet est aussi téléchargeable
   dans l'artifact `journal-compilation`.

## Installer sur l'iPhone avec Sideloadly (Windows)

1. Installe iTunes et iCloud **depuis le site d'Apple** (pas le Microsoft Store), puis Sideloadly.
2. Branche l'iPhone, déverrouille-le, « Faire confiance à cet ordinateur ».
3. Glisse `KratosClap.ipa` dans Sideloadly, entre ton Apple ID (idéalement un compte secondaire), « Start ».
4. Sur l'iPhone, la première fois :
   - Réglages → Confidentialité et sécurité → Mode développeur → activer (redémarrage) ;
   - Réglages → Général → VPN et gestion de l'appareil → ton Apple ID → Faire confiance.

Avec un Apple ID gratuit, l'app expire au bout de 7 jours : réinstalle-la la veille d'un tournage.

## Utilisation sur le plateau

1. Connecte l'enceinte, puis « Étalonner cette sortie » depuis la place de l'artiste, dans le calme.
2. Vérifie l'écart entre mesures : s'il dépasse 10–15 ms, l'enceinte est instable, réétalonne.
3. Règle la cadence caméra.
4. CLAP, filme l'écran pendant le slate et le flash.
5. En post : cale la **première frame blanche** sur le début du bip.
6. Si tu constates un décalage constant, corrige-le avec le décalage manuel
   (valeur positive = flash plus tard).
