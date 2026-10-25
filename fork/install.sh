#!/bin/sh
# Installs (or updates) the Hyprland-patched stack in /opt/hypr-stack on Debian 13 arm64, from the
# latest release of this repository, and adds a "Hyprland (patched)" login session.
# Installe (ou met à jour) la pile Hyprland-patched dans /opt/hypr-stack sur Debian 13 arm64,
# depuis la dernière version publiée de ce dépôt, et ajoute une session de connexion.
#
#   curl -fsSL https://github.com/jpreculeau/Hyprland-patched/releases/latest/download/install.sh | sh
#   ... | sh -s -- --rollback     back to the previous stack / revenir à la pile précédente
#
# The previous stack is kept in /opt/hypr-stack.prev. Debian's packages are never removed.
# La pile précédente est gardée dans /opt/hypr-stack.prev. Aucun paquet Debian n'est retiré.
set -eu

# Everything runs inside main(), called on the last line: a download cut short runs nothing.
# Tout est dans main(), appelée à la dernière ligne : un téléchargement coupé n'exécute rien.
main() {
    REPO=jpreculeau/Hyprland-patched
    P=/opt/hypr-stack
    ARCHIVE=hypr-stack-debian13-arm64.tar.zst
    URL=${HYPR_STACK_URL:-https://github.com/$REPO/releases/latest/download}
    # not found by ldd (loaded at run time) / non trouvées par ldd (chargées à l'exécution)
    EXTRA_DEPS="xwayland libinput-bin libegl-mesa0 libgbm1 libgl1-mesa-dri xdg-desktop-portal zstd"
    APT_UPDATED=

    [ "$(id -u)" -ne 0 ] || die "run it as your user, it calls sudo itself / lancer en utilisateur"
    command -v sudo > /dev/null || die "sudo is required / sudo est nécessaire"

    if [ "${1:-}" = --rollback ]; then
        rollback
        return
    fi

    [ "$(dpkg --print-architecture 2> /dev/null)" = arm64 ] || die "arm64 only / arm64 seulement"
    os=$(. /etc/os-release && echo "${ID:-}:${VERSION_ID:-}")
    [ "$os" = debian:13 ] || [ -n "${HYPR_STACK_FORCE:-}" ] \
        || die "built for Debian 13, found $os (HYPR_STACK_FORCE=1 to try anyway) / compilée pour Debian 13"

    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT
    echo "Downloading / téléchargement : $URL/$ARCHIVE"
    curl --proto '=https' -fL --progress-bar -o "$TMP/$ARCHIVE" "$URL/$ARCHIVE"
    curl --proto '=https' -fsSL -o "$TMP/$ARCHIVE.sha256" "$URL/$ARCHIVE.sha256"
    (cd "$TMP" && sha256sum -c --quiet "$ARCHIVE.sha256") || die "checksum mismatch / empreinte incorrecte"

    command -v zstd > /dev/null || apt_install zstd
    mkdir "$TMP/new"
    tar -C "$TMP/new" -I zstd -xf "$TMP/$ARCHIVE"
    if [ -f "$P/share/hypr-stack/manifest.txt" ] \
        && cmp -s "$P/share/hypr-stack/manifest.txt" "$TMP/new/share/hypr-stack/manifest.txt"; then
        echo "This release is already installed / cette version est déjà installée."
    else
        # shellcheck disable=SC2046,SC2086
        apt_install $(grep -v '^#' "$TMP/new/share/hypr-stack/runtime-deps.txt") $EXTRA_DEPS
        # every symbol resolved against this system's libraries, before replacing anything
        # tous les symboles résolus contre les bibliothèques du système, avant de remplacer quoi que ce soit
        # (Hyprland needs XDG_RUNTIME_DIR even for --version, e.g. missing under sudo -iu)
        XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$TMP}" LD_BIND_NOW=1 LD_LIBRARY_PATH="$TMP/new/lib" \
            "$TMP/new/bin/Hyprland" --version > /dev/null \
            || die "Hyprland does not run with this system's libraries (needs Raspberry Pi OS or Debian 13 with backports?) / ne démarre pas avec les bibliothèques du système"
        sudo rm -rf "$P.new"
        sudo cp -a "$TMP/new" "$P.new"
        sudo chown -R root:root "$P.new"
        if [ -d "$P" ]; then
            sudo rm -rf "$P.prev"
            sudo mv "$P" "$P.prev"
        fi
        sudo mv "$P.new" "$P"
    fi

    sudo install -Dm644 "$P/share/hypr-stack/hyprland-stack.desktop" /usr/share/wayland-sessions/hyprland-stack.desktop
    [ -f /etc/pam.d/hyprlock ] || sudo install -m644 "$P/share/hypr-stack/pam/hyprlock" /etc/pam.d/hyprlock
    portal

    echo
    sed 's/^/  /' "$P/share/hypr-stack/manifest.txt"
    echo "Installed in $P. Choose \"Hyprland (patched)\" at login. / Installée ; choisir cette session."
}

die() { echo "install.sh: $*" >&2; exit 1; }

apt_install() {
    [ -n "$APT_UPDATED" ] || sudo apt-get update < /dev/null
    APT_UPDATED=1
    # --no-remove: never remove a Debian package to satisfy these / ne jamais retirer de paquet
    sudo apt-get install -y --no-install-recommends --no-remove "$@" < /dev/null
}

rollback() {
    [ -d "$P.prev" ] || die "no previous stack in $P.prev / aucune pile précédente"
    if [ -d "$P" ]; then
        sudo rm -rf "$P.rollback"
        sudo mv "$P" "$P.rollback"
        sudo mv "$P.prev" "$P"
        sudo mv "$P.rollback" "$P.prev"
    else
        sudo mv "$P.prev" "$P"
    fi
    echo "Previous stack restored; log out and back in. / Pile précédente rétablie ; se reconnecter."
}

# Screen sharing: this stack's portal in its own session only (hypr-stack-session sets
# HYPR_STACK=1), Debian's elsewhere or if the stack is gone.
# Partage d'écran : le portail de la pile dans sa session seulement, celui de Debian ailleurs.
portal() {
    if [ ! -f /usr/lib/systemd/user/xdg-desktop-portal-hyprland.service ]; then
        echo "Note: no screen sharing without Debian's xdg-desktop-portal-hyprland (trixie-backports," >&2
        echo "Raspberry Pi OS); install it, then run this script again. / Pas de partage d'écran sans ce paquet." >&2
        return 0
    fi
    d="$HOME/.config/systemd/user/xdg-desktop-portal-hyprland.service.d"
    mkdir -p "$d"
    cat > "$d/hypr-stack.conf" << 'UNIT'
[Service]
ExecStart=
ExecStart=/bin/sh -c 'if [ "$HYPR_STACK" = 1 ] && [ -x /opt/hypr-stack/libexec/xdg-desktop-portal-hyprland ]; then exec /opt/hypr-stack/libexec/xdg-desktop-portal-hyprland; else exec /usr/libexec/xdg-desktop-portal-hyprland; fi'
UNIT
    systemctl --user daemon-reload 2> /dev/null || true
}

main "$@"
