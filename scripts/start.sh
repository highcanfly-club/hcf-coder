#!/bin/bash
WORKDIR=${BASEDIR}/workdir/
mkdir -p ${BASEDIR}/.ssh
mkdir -p $WORKDIR
cd $WORKDIR/..
SECRET=$(/usr/bin/secret2sshkey --secret ssh-key-secret --ssh-dir ${BASEDIR}/.ssh)
echo $SECRET
IDENTITY=`echo $SECRET | awk -F ' ' '{print $3}' | awk -F '=' '{print $2}'`
echo "Using IDENTITY=$IDENTITY"
chmod -R go-rwx ${BASEDIR}/.ssh
echo "mount root@$REMOTEHOST:$REMOTEDIR in $WORKDIR"
FSTAB_LINE="root@$REMOTEHOST:$REMOTEDIR $WORKDIR  fuse.sshfs noauto,x-systemd.automount,_netdev,users,idmap=user,AddressFamily=inet,StrictHostKeyChecking=accept-new,IdentityFile=$IDENTITY,port=$REMOTEPORT,allow_other,reconnect 0 0"
grep -qF "$FSTAB_LINE" /etc/fstab || echo "$FSTAB_LINE" >> /etc/fstab
#sshfs -p $REMOTEPORT -o AddressFamily=inet,StrictHostKeyChecking=accept-new  root@$REMOTEHOST:$REMOTEDIR $WORKDIR
/bin/mount $WORKDIR

# ---------------------------------------------------------------------------
# Persistent user state. Everything below ${BASEDIR} lives on the PVC:
#   .local/share/code-server (user-data-dir: settings, globalStorage, state.vscdb, argv.json)
#   .config (kilo...), .local/share/kilo, .claude
# Extensions are in the image (EXTENSIONS_DIR), so an image upgrade brings new versions.
# ---------------------------------------------------------------------------
USER_DATA_DIR=${BASEDIR}/.local/share/code-server
USER_DIR=${USER_DATA_DIR}/User
EXTENSIONS_DIR=${EXTENSIONS_DIR:-/opt/code-server/extensions}
CONFIG_DIR=${HCF_CONFIG_DIR:-/usr/share/hcf-coder/config}
LOCALE=${LOCALE:-fr}

# Migration: older images symlinked .local and .config to /vscode (inside the image layer,
# so nothing was kept). Replace those links by real directories on the PVC.
for DIR in .local .config; do
    if [ -L "${BASEDIR}/${DIR}" ]; then
        echo "Replacing symlink ${BASEDIR}/${DIR} by a real directory"
        rm -f "${BASEDIR}/${DIR}"
    fi
done
mkdir -p "${USER_DIR}/globalStorage" "${BASEDIR}/.config" "${BASEDIR}/.claude"

# One-shot restore of the state saved from the old container layer (see README, "Migration").
MIGRATION=${BASEDIR}/hcf-migration.tgz
if [ -f "$MIGRATION" ]; then
    echo "Restoring user state from $MIGRATION"
    if tar -xzf "$MIGRATION" -C "${BASEDIR}"; then
        mv "$MIGRATION" "${MIGRATION}.done"
    else
        echo "WARN: restore from $MIGRATION failed, archive kept" >&2
    fi
fi

# Default settings: only fill what the user did not set, user values always win.
SETTINGS=${USER_DIR}/settings.json
if [ -f "${CONFIG_DIR}/settings.defaults.json" ]; then
    if [ ! -s "$SETTINGS" ]; then
        cp "${CONFIG_DIR}/settings.defaults.json" "$SETTINGS"
    elif jq -e . "$SETTINGS" >/dev/null 2>&1; then
        TMP=$(mktemp "${SETTINGS}.XXXXXX") && jq -s '.[0] * .[1]' "${CONFIG_DIR}/settings.defaults.json" "$SETTINGS" > "$TMP" && mv "$TMP" "$SETTINGS"
    else
        echo "WARN: $SETTINGS is not strict JSON (comments?), defaults not applied" >&2
    fi
fi

# Display language: set once if missing, argv.json is where VS Code stores it.
ARGV=${USER_DIR}/argv.json
[ -s "$ARGV" ] || echo '{}' > "$ARGV"
if jq -e . "$ARGV" >/dev/null 2>&1; then
    if ! jq -e 'has("locale")' "$ARGV" >/dev/null 2>&1; then
        TMP=$(mktemp "${ARGV}.XXXXXX") && jq --arg l "$LOCALE" '. + {locale: $l}' "$ARGV" > "$TMP" && mv "$TMP" "$ARGV"
    fi
else
    echo "WARN: $ARGV is not strict JSON, locale not enforced" >&2
fi
# Language pack index is derived from the extensions of the image: refresh at every start.
[ -f /usr/share/languagepacks.json ] && cp /usr/share/languagepacks.json "${USER_DATA_DIR}/languagepacks.json"

# Experimental: register "Desktop" and "iPad" settings profiles (switch from the gear menu).
if [ "${HCF_SEED_PROFILES:-true}" = "true" ] && [ -d "${CONFIG_DIR}/profiles" ]; then
    STORAGE=${USER_DIR}/globalStorage/storage.json
    [ -s "$STORAGE" ] || echo '{}' > "$STORAGE"
    if jq -e . "$STORAGE" >/dev/null 2>&1; then
        for P in desktop ipad; do
            NAME=$(echo "$P" | sed 's/desktop/Desktop/; s/ipad/iPad/')
            mkdir -p "${USER_DIR}/profiles/hcf-${P}"
            [ -f "${USER_DIR}/profiles/hcf-${P}/settings.json" ] || cp "${CONFIG_DIR}/profiles/${P}.json" "${USER_DIR}/profiles/hcf-${P}/settings.json"
            if ! jq -e --arg n "$NAME" '(.userDataProfiles // []) | any(.name == $n)' "$STORAGE" >/dev/null 2>&1; then
                TMP=$(mktemp "${STORAGE}.XXXXXX") && jq --arg n "$NAME" --arg l "hcf-${P}" '.userDataProfiles = ((.userDataProfiles // []) + [{name: $n, location: $l}])' "$STORAGE" > "$TMP" && mv "$TMP" "$STORAGE"
            fi
        done
    fi
fi

# Toolchains kept in the image layer
LINKS=".cargo .bash_history .bashrc .profile .gitconfig .rustup go"
for LINK in $LINKS ; do
    if [ ! -e "${BASEDIR}/${LINK}" ] && [ -e "/vscode/${LINK}" ] ; then
        echo "Linking ${BASEDIR}/${LINK}"
        ln -svf /vscode/${LINK} ${BASEDIR}/${LINK} || true
    fi
done

# Check if LC_ALL is set in .bashrc, if not, add it to the end of the file, if .baschrc does not exist, create it and add the line. This is needed for some locales to work properly.
if [ ! -f "${HOME}/.bashrc" ]; then
    touch "${HOME}/.bashrc"
fi
if ! grep -q "export LC_ALL=" "${HOME}/.bashrc"; then
    # If ${LOCALE}.UTF-8 exists in locale -a, add it to .bashrc, otherwise use C.UTF-8
    if locale -a | grep -q "${LOCALE}.UTF-8"; then
        echo "export LC_ALL=${LOCALE}.UTF-8" >> "${HOME}/.bashrc"
    else
        echo "export LC_ALL=C.UTF-8" >> "${HOME}/.bashrc"
    fi
fi

exec /usr/bin/entrypoint.sh --enable-remote-storage --auth none --disable-telemetry --bind-addr 0.0.0.0:8080 \
    --user-data-dir "${USER_DATA_DIR}" --extensions-dir "${EXTENSIONS_DIR}" \
    --app-name "${APPNAME:-HCF Code server}" .
