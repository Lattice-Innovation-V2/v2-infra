#!/bin/bash
# =============================================================================
# Lattice V2 — Key Transfer Script
# =============================================================================
# Run this on the SOURCE machine to bundle keys for transfer.
# On the TARGET machine, run with --install to unpack.
#
# Usage:
#   ./keys-transfer.sh              # Bundle keys into v2-keys-bundle.tar.gz
#   ./keys-transfer.sh --install    # Install keys from v2-keys-bundle.tar.gz
# =============================================================================

BUNDLE="v2-keys-bundle.tar.gz"
STAGING="/tmp/v2-keys-staging"

if [ "$1" = "--install" ]; then
    # ─── INSTALL MODE ────────────────────────────────────────────────────
    echo "=== Installing V2 keys from $BUNDLE ==="

    if [ ! -f "$BUNDLE" ]; then
        echo "ERROR: $BUNDLE not found. Copy it to this directory first."
        exit 1
    fi

    tar xzf "$BUNDLE" -C /tmp
    STAGING="/tmp/v2-keys-staging"

    # 1. SSH keys + config
    echo ""
    echo "--- SSH Keys ---"
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh

    for key in daniellattice_github daniellattice_github.pub; do
        if [ -f "$STAGING/ssh/$key" ]; then
            cp "$STAGING/ssh/$key" ~/.ssh/
            chmod 600 ~/.ssh/"$key"
            echo "  Installed ~/.ssh/$key"
        fi
    done

    # Append SSH config block if not already present
    if ! grep -q "lattice-github.com" ~/.ssh/config 2>/dev/null; then
        echo "" >> ~/.ssh/config
        cat "$STAGING/ssh/config-block.txt" >> ~/.ssh/config
        echo "  Appended lattice-github.com block to ~/.ssh/config"
    else
        echo "  ~/.ssh/config already has lattice-github.com entry (skipped)"
    fi

    # 2. Maven settings
    echo ""
    echo "--- Maven Settings ---"
    mkdir -p ~/.m2
    if [ -f ~/.m2/settings.xml ]; then
        echo "  WARNING: ~/.m2/settings.xml already exists."
        echo "  Backup saved as ~/.m2/settings.xml.bak"
        cp ~/.m2/settings.xml ~/.m2/settings.xml.bak
    fi
    cp "$STAGING/maven/settings.xml" ~/.m2/settings.xml
    echo "  Installed ~/.m2/settings.xml (GitHub Packages auth)"

    # 3. GCP auth reminder
    echo ""
    echo "--- GCP Auth ---"
    echo "  Run these commands manually:"
    echo "    gcloud auth login daniel@latticepay.io"
    echo "    gcloud config set project lattice-innovation-v2"
    echo "    gcloud auth application-default login"
    echo ""
    echo "  For Docker pushes to Artifact Registry:"
    echo "    gcloud auth configure-docker us-central1-docker.pkg.dev"

    # 4. Test SSH
    echo ""
    echo "--- Verify ---"
    echo "  Test GitHub SSH: ssh -T git@lattice-github.com"
    echo "  Test Maven:      cd v2-integrator-service && ./mvnw validate"

    # Cleanup
    rm -rf "$STAGING"
    echo ""
    echo "=== Done. Delete $BUNDLE after verifying. ==="
    exit 0
fi

# ─── BUNDLE MODE (default) ──────────────────────────────────────────────────
echo "=== Bundling V2 keys ==="

rm -rf "$STAGING"
mkdir -p "$STAGING/ssh" "$STAGING/maven"

# 1. SSH key for Lattice GitHub (danlattice account)
echo "--- SSH Keys ---"
cp ~/.ssh/daniellattice_github "$STAGING/ssh/"
cp ~/.ssh/daniellattice_github.pub "$STAGING/ssh/"
echo "  Copied daniellattice_github keypair"

# SSH config block (just the relevant entry)
cat > "$STAGING/ssh/config-block.txt" << 'SSHEOF'
Host lattice-github.com
  HostName github.com
  User danlattice
  IdentityFile ~/.ssh/daniellattice_github
  IdentitiesOnly yes
SSHEOF
echo "  Created SSH config block"

# 2. Maven settings (GitHub Packages auth for latticepay-security)
echo ""
echo "--- Maven Settings ---"
cp ~/.m2/settings.xml "$STAGING/maven/"
echo "  Copied ~/.m2/settings.xml"

# 3. Create the bundle
echo ""
echo "--- Creating bundle ---"
tar czf "$BUNDLE" -C /tmp v2-keys-staging
rm -rf "$STAGING"

echo ""
echo "=== Bundle created: $BUNDLE ==="
echo ""
echo "Transfer this file to the other machine, then run:"
echo "  ./keys-transfer.sh --install"
echo ""
echo "NOTE: This bundle contains PRIVATE KEYS. Delete it after transfer."
echo ""
echo "What's NOT included (must be done manually on target):"
echo "  - GCP auth: gcloud auth login daniel@latticepay.io"
echo "  - GCP project: gcloud config set project lattice-innovation-v2"
echo "  - Docker auth: gcloud auth configure-docker us-central1-docker.pkg.dev"
echo "  - Java 21 + Node 22 (install via sdkman/brew/nvm)"
