# Hyprland, patched / Hyprland avec correctifs

**English** — Personal build of [Hyprland](https://github.com/hyprwm/Hyprland): the latest upstream
release with a few local patches on top, kept aligned automatically, and a prebuilt stack for
Debian 13 arm64 (e.g. Raspberry Pi 5). Not affiliated with the Hyprland project; no pull request
is made from this repository. Use upstream unless you need one of these patches.

**Français** — Version personnelle de [Hyprland](https://github.com/hyprwm/Hyprland) : la dernière
version publiée en amont avec quelques correctifs locaux, alignée automatiquement, et une pile
précompilée pour Debian 13 arm64 (ex. Raspberry Pi 5). Sans lien avec le projet Hyprland ; aucune
pull request n'est faite depuis ce dépôt. Préférez l'original si ces correctifs ne vous servent pas.

## Install / installer (Debian 13 arm64)

Built on Raspberry Pi OS (Debian 13 "trixie", arm64, Raspberry Pi 5), against its Mesa and libdrm,
which are newer than plain Debian 13's: use Raspberry Pi OS, or Debian 13 with backports. The
installer checks that Hyprland starts with your libraries before replacing anything. /
Compilée sur Raspberry Pi OS (Debian 13, arm64, Pi 5), avec ses Mesa et libdrm plus récentes que
celles de Debian 13 : utiliser Raspberry Pi OS, ou Debian 13 avec les backports. L'installeur
vérifie que Hyprland démarre avec vos bibliothèques avant de remplacer quoi que ce soit.

```sh
curl -fsSL https://github.com/jpreculeau/Hyprland-patched/releases/latest/download/install.sh | sh
```

- Installs the whole stack (Hyprland, aquamarine, hypr* libraries, hyprlock, hypridle,
  xdg-desktop-portal-hyprland, hyprbars, and newer wayland, wayland-protocols, libinput, Lua 5.5)
  in `/opt/hypr-stack`, its runtime dependencies with apt, and a login session
  "Hyprland (patched)". Debian's Hyprland packages are not touched. /
  Installe toute la pile dans `/opt/hypr-stack`, ses dépendances avec apt, et une session de
  connexion « Hyprland (patched) ». Les paquets Hyprland de Debian ne sont pas touchés.
- Config: `~/.config/hypr/hyprland-stack.lua` if present, else `~/.config/hypr/hyprland-stack.conf`
  (before 0.57), else Hyprland's own lookup (`hyprland.lua`; from 0.57 on, Hyprland reads Lua only);
  optional hook `~/.config/hypr/hypr-stack-pre` run before Hyprland. / Config et crochet optionnel.
- **Upgrading to 0.57**: Hyprland 0.57 reads Lua configs only (a `hyprland-stack.conf` would be
  read as Lua and fail). Write `~/.config/hypr/hyprland-stack.lua` before you
  update; Hyprland 0.55 and 0.56 read it too. If the session fails, roll back (below). /
  **Passage à 0.57** : Hyprland 0.57 ne lit plus que du Lua. Écrire `hyprland-stack.lua` avant la
  mise à jour (0.55 et 0.56 le lisent aussi) ; en cas d'échec, revenir en arrière (ci-dessous).
- Update: run the same command (nothing is done if that release is already installed). /
  Mise à jour : relancer la même commande. Older stacks are kept in `/opt/hypr-stack.prev.<date>`
  (about 90 MB each, listed with their total at each update; delete them when no longer needed). /
  Les anciennes piles sont gardées dans `/opt/hypr-stack.prev.<date>` (environ 90 Mo chacune,
  listées à chaque mise à jour ; les supprimer quand elles ne servent plus).
  Rollback / revenir à la pile précédente (gardée dans `/opt/hypr-stack.prev`) :
  `curl -fsSL https://github.com/jpreculeau/Hyprland-patched/releases/latest/download/install.sh | sh -s -- --rollback`
- Only missing runtime dependencies are installed with apt, which is never allowed to remove a
  package; installed ones are not upgraded unless a missing one requires it. If Hyprland then does
  not run with your libraries, update them (`sudo apt update && sudo apt full-upgrade`) and run the
  command again. / Seules les dépendances absentes sont installées avec apt, sans jamais retirer
  de paquet ; celles déjà présentes ne sont mises à jour que si une dépendance absente l'exige.
  Si Hyprland ne démarre pas avec vos bibliothèques, les mettre à jour, puis relancer.
- Screen sharing needs Debian's `xdg-desktop-portal-hyprland` package (Raspberry Pi OS, or
  trixie-backports) for its service files; a drop-in then uses this stack's portal in its session
  and Debian's elsewhere. / Le partage d'écran demande le paquet Debian `xdg-desktop-portal-hyprland`
  (Raspberry Pi OS ou trixie-backports) ; le portail de la pile sert alors dans sa session.
- With autologin, select the session `hyprland-stack` in your display manager's config. /
  En connexion automatique, choisir la session `hyprland-stack` dans la config du gestionnaire.

## Branches

| Branch | Content / contenu |
|---|---|
| `patches` | latest upstream release + local patches + `fork/` tooling / dernière version amont + correctifs + outillage |
| `main` | `patches` + one generated commit making it build with GCC 14 / + un commit généré pour GCC 14 |

Commit changes to `patches` only: `main` is regenerated from it. / Ne modifier que `patches` : `main` en est régénérée.
Upstream history is not included: each upstream release is a single commit `upstream: vX.Y.Z,
unmodified source` (its tree, unchanged), chained to the previous one, with the patches on top.
When upstream publishes a new release, the patches move onto it and both branches are
force-pushed. Releases: `vX.Y.Z-patched.N`. /
L'historique amont n'est pas inclus : chaque version amont est un seul commit (son arbre, inchangé),
chaîné au précédent, avec les correctifs par-dessus. À chaque nouvelle version amont, les
correctifs y sont déplacés et les deux branches poussées en force.

## Patches / correctifs

- **log: make aquamarine logs honor `debug:disable_logs`** — aquamarine's log connection bypassed
  the setting; with logs disabled (Hyprland's default) it now only lets critical messages through,
  so aquamarine's warnings no longer reach the log unless logs are enabled. / La connexion de
  journal d'aquamarine ignorait le réglage ; journaux coupés (défaut de Hyprland), seuls les
  messages critiques passent.
- **input: `follow_layout` option for virtual keyboards** — per-device option (off by default):
  the virtual keyboard of a remote desktop server (e.g. wayvnc) keeps the configured keymap and
  follows the layout of the physical keyboards. / Option par périphérique : le clavier virtuel
  d'un bureau à distance garde le keymap de la config et suit la disposition des claviers
  physiques.
  ```lua
  hl.device({ name = "hl-virtual-keyboard-wayvnc", follow_layout = true })
  ```
  Before 0.57, in hyprlang / avant 0.57, en hyprlang :
  ```
  device {
      name = hl-virtual-keyboard-wayvnc
      follow_layout = true
  }
  ```
  Switch layouts on the physical keyboards (`hyprctl switchxkblayout all next`, or each physical
  keyboard by name): `switchxkblayout main` may target the virtual keyboard while you type
  remotely, and its group is overwritten on the next key. A change of the option applies when the
  client reconnects. / Changer de disposition sur les claviers physiques (`all` ou chacun par son
  nom) : `main` peut viser le clavier virtuel pendant une saisie à distance. Un changement de
  l'option s'applique à la reconnexion du client.
- **GCC 14 compatibility (generated)** — `fork/gcc14.sh`: Debian's `#embed` workaround
  (`fork/embed.patch`, BSD-3-Clause, the Debian package's patch, itself from a PPA as its header
  says), `append_range`/`insert_range` rewritten as `insert()`, `string::subview` as
  `string_view(…).substr`, the member `variant::visit` as `std::visit`, a header for
  `string + string_view`, `ranges::starts_with/ends_with` and `std::format` of a vector (no effect with GCC 15+), a `static_cast` in `XWM.hpp`. /
  Contournement Debian de `#embed`, réécriture d'`append_range`/`insert_range`, de
  `string::subview` et de la méthode `variant::visit`, en-tête de
  compatibilité (sans effet avec GCC 15+), un `static_cast` dans `XWM.hpp`.
- In the companion repository `aquamarine-patched` / dans le dépôt associé : the mgpu renderer of
  the primary GPU is not required, so a setup where it cannot be created (vc4 + v3d) no longer
  retries it on every commit (nor later, until restart). / le renderer mgpu du GPU principal n'est
  plus requis, et n'est plus réessayé avant un redémarrage.

## Tooling / outillage (`fork/`)

| Script | Role / rôle |
|---|---|
| `sync.sh <clones>` | moves the patches onto the newest upstream release (or the newest vX.Y.* with `SYNC_SERIE_<clone dir>=X.Y`, refused if older than the branch's release), regenerates `main`, pushes; stops on a conflict without pushing / déplace les correctifs sur la dernière version (ou la dernière vX.Y.* avec `SYNC_SERIE_<dossier>=X.Y`, refusée si plus ancienne que celle de la branche), s'arrête sans pousser en cas de conflit |
| `build-stack.sh` | builds the whole stack (`stack.txt`, build dependencies: `build-deps.txt`) / compile la pile |
| `package.sh` | builds in a private mount namespace (the installed stack is not touched) and makes the archive / compile à part et produit l'archive |
| `release.sh <clones>` | `sync.sh`, then build and publish a release if this repository or aquamarine-patched changed (new releases of the other components are picked up by the next one) / publie si ce dépôt ou aquamarine-patched ont changé |
| `install.sh` | installs the latest release / installe la dernière version |
| `sync_test.sh sync.sh`, `release_test.sh release.sh`, `package_test.sh package.sh` | tests on throwaway repositories, with a fake `gh` and `ldd` / tests sur dépôts jetables, faux `gh` et `ldd` |
| `install_test.sh install.sh` | apt asked for missing packages only, older stacks kept, with fake `sudo` and `dpkg-query` / apt pour les seuls paquets absents, anciennes piles gardées, faux `sudo` et `dpkg-query` |
| `session_test.sh session/hypr-stack-session` | config passed to Hyprland and hook order, with a fake stack and `HOME` / config passée à Hyprland et ordre du crochet, fausse pile et faux `HOME` |
| `gcc14_test.sh` | `gcc14-compat.py` rewrites, built with the system GCC / réécritures de `gcc14-compat.py`, compilées avec le GCC du système |

Code assisted by an AI model (Claude); see the `Co-Authored-By` lines of each commit. /
Code écrit avec l'aide d'un modèle d'IA (Claude) ; voir les lignes `Co-Authored-By` des commits.
