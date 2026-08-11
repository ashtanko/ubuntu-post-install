#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_HELPER="$REPO_ROOT/lib/config.bash"
# shellcheck source=lib/config.bash
source "$CONFIG_HELPER" || { echo "❌ Missing config helper: $CONFIG_HELPER" >&2; exit 1; }
load_config "$REPO_ROOT"

AWS_INSTALL_DIR="/usr/local/aws-cli"
AWS_BIN="/usr/local/bin/aws"
AWS_CLI_KEY_FINGERPRINT="FB5DB77FD5C118B80511ADA8A6310ACC4672475C"

if [ ! -d "$AWS_INSTALL_DIR" ] || [ ! -x "$AWS_BIN" ]; then
    echo "⏭️  Skipping AWS CLI update: the repository-managed installation was not found under $AWS_INSTALL_DIR."
    exit 0
fi

AWS_BIN_TARGET=$(readlink -f "$AWS_BIN" 2>/dev/null || true)
case "$AWS_BIN_TARGET" in
    "$AWS_INSTALL_DIR"/*) ;;
    *)
        echo "⏭️  Skipping AWS CLI update: $AWS_BIN is not linked to $AWS_INSTALL_DIR."
        exit 0
        ;;
esac

case "$(dpkg --print-architecture)" in
    amd64) AWS_ARCH="x86_64" ;;
    arm64) AWS_ARCH="aarch64" ;;
    *)
        echo "❌ Unsupported AWS CLI architecture: $(dpkg --print-architecture)" >&2
        exit 1
        ;;
esac

for REQUIRED_COMMAND in curl gpg unzip; do
    if ! command -v "$REQUIRED_COMMAND" >/dev/null 2>&1; then
        echo "❌ $REQUIRED_COMMAND is required to update AWS CLI" >&2
        exit 1
    fi
done

BEFORE_VERSION=$("$AWS_BIN" --version 2>&1 || echo "version unknown")
echo "🚀 Updating AWS CLI v2..."
echo "   Before: $BEFORE_VERSION"

AWS_TMP_DIR=$(mktemp -d)
trap 'rm -rf "$AWS_TMP_DIR"' EXIT
AWS_ZIP="$AWS_TMP_DIR/awscliv2.zip"
AWS_SIGNATURE="$AWS_ZIP.sig"
AWS_PUBLIC_KEY="$AWS_TMP_DIR/aws-cli-public-key.asc"
AWS_GNUPGHOME="$AWS_TMP_DIR/gnupg"
AWS_DOWNLOAD_URL="https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip"

mkdir -m 700 "$AWS_GNUPGHOME"
cat >"$AWS_PUBLIC_KEY" <<'AWS_CLI_PUBLIC_KEY'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBF2Cr7UBEADJZHcgusOJl7ENSyumXh85z0TRV0xJorM2B/JL0kHOyigQluUG
ZMLhENaG0bYatdrKP+3H91lvK050pXwnO/R7fB/FSTouki4ciIx5OuLlnJZIxSzx
PqGl0mkxImLNbGWoi6Lto0LYxqHN2iQtzlwTVmq9733zd3XfcXrZ3+LblHAgEt5G
TfNxEKJ8soPLyWmwDH6HWCnjZ/aIQRBTIQ05uVeEoYxSh6wOai7ss/KveoSNBbYz
gbdzoqI2Y8cgH2nbfgp3DSasaLZEdCSsIsK1u05CinE7k2qZ7KgKAUIcT/cR/grk
C6VwsnDU0OUCideXcQ8WeHutqvgZH1JgKDbznoIzeQHJD238GEu+eKhRHcz8/jeG
94zkcgJOz3KbZGYMiTh277Fvj9zzvZsbMBCedV1BTg3TqgvdX4bdkhf5cH+7NtWO
lrFj6UwAsGukBTAOxC0l/dnSmZhJ7Z1KmEWilro/gOrjtOxqRQutlIqG22TaqoPG
fYVN+en3Zwbt97kcgZDwqbuykNt64oZWc4XKCa3mprEGC3IbJTBFqglXmZ7l9ywG
EEUJYOlb2XrSuPWml39beWdKM8kzr1OjnlOm6+lpTRCBfo0wa9F8YZRhHPAkwKkX
XDeOGpWRj4ohOx0d2GWkyV5xyN14p2tQOCdOODmz80yUTgRpPVQUtOEhXQARAQAB
tCFBV1MgQ0xJIFRlYW0gPGF3cy1jbGlAYW1hem9uLmNvbT6JAlQEEwEIAD4CGwMF
CwkIBwIGFQoJCAsCBBYCAwECHgECF4AWIQT7Xbd/1cEYuAURraimMQrMRnJHXAUC
akV0ygUJDqP4lQAKCRCmMQrMRnJHXFHjD/9eyZLYcKuQOlLvtqSDtUBiEZf6ZZjM
i3ygYH8rJNtuToUH+HvSpe819urJCquXhDrlK6N+aqW0hCLtNABJG/vsafIgvIYJ
hSGgpgtNnQyMV1jViRWqPjbouw8OkYKBThUfT1i2Y+wn58ifs6ODBCmTexWtXspA
Si+Gt49xDOW0APmbOPnI+a4HJW6tVEo6MWS0WjzpiBayR3d1A4pt4YrPfSdDgpLo
h2SLQqlRqvvVZJaWBjhkErNFpfsBA06sDcPEOb0G8LBUbR4WOcdvhe5LubJbZuxC
AG9kNPCVeQP1ixwjgjXKysaxeQ6rv0VzIQgRp6tLVLWhy6AKDNvLjFSsmXZ1Wl08
Y/RlOHXlzLuQMRE6sR1wOdRxc9TsrNWTGiBK65cvSWOy03JeBkQQ8pesqltiyxI9
U21kkgiXtTSKNGfKK8pO27D81YANhRqPK7iTp6kuFiY2WtOg90KTMNlIT+Ff85Y2
b1rHj6Z0SrCkJujhWk3IBPic/wJgz01LEc/OAdUPlby90RJZcIBhSlWhT7mXnXIO
c0HWlNQrns2s3CTyYwZSiSlYe9ApeLwhjDo8NhbFuCAy61l6O5UsR4AfZxx/rGKv
2wFb1/RN/P4gNe6vmxZAPjR0AQcwD3tc2McimOLr/22kmPz8IH3I0X7WoSFr0Biz
E91G7bb0hOb/cA==
=knv7
-----END PGP PUBLIC KEY BLOCK-----
AWS_CLI_PUBLIC_KEY

gpg --batch --homedir "$AWS_GNUPGHOME" --import "$AWS_PUBLIC_KEY"
IMPORTED_FINGERPRINT=$(gpg --batch --homedir "$AWS_GNUPGHOME" --with-colons --fingerprint \
    | awk -F: '$1 == "fpr" { print toupper($10); exit }' \
    | tr -d '[:space:]')
if [ "$IMPORTED_FINGERPRINT" != "$AWS_CLI_KEY_FINGERPRINT" ]; then
    echo "❌ AWS CLI signing key fingerprint mismatch: $IMPORTED_FINGERPRINT" >&2
    exit 1
fi

curl --proto '=https' --tlsv1.2 -fsSL --retry 3 --retry-all-errors \
    -o "$AWS_ZIP" "$AWS_DOWNLOAD_URL"
curl --proto '=https' --tlsv1.2 -fsSL --retry 3 --retry-all-errors \
    -o "$AWS_SIGNATURE" "${AWS_DOWNLOAD_URL}.sig"
gpg --batch --homedir "$AWS_GNUPGHOME" --verify "$AWS_SIGNATURE" "$AWS_ZIP"
unzip -q "$AWS_ZIP" -d "$AWS_TMP_DIR"
sudo "$AWS_TMP_DIR/aws/install" \
    --bin-dir /usr/local/bin \
    --install-dir /usr/local/aws-cli \
    --update

AFTER_VERSION=$("$AWS_BIN" --version 2>&1 || echo "version unknown")
echo "✅ AWS CLI update complete"
echo "   After:  $AFTER_VERSION"
