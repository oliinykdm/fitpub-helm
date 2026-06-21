# Publishing

## Artifact Hub

The public Helm repository is served from GitHub Pages:

```text
https://oliinykdm.github.io/fitpub-helm
```

GitHub Pages must be configured as:

- source: `Deploy from a branch`
- branch: `gh-pages`
- folder: `/root`

Artifact Hub repository metadata is stored in `artifacthub-repo.yml` and copied to `gh-pages` by the release workflow.

## Chart README

Artifact Hub displays the README included in the chart package. Keep package-facing documentation in:

```text
charts/fitpub/README.md
```

The repository root `README.md` is for repository-level documentation.

## Signed Charts

Artifact Hub shows a chart as signed when the Helm package has a provenance file and the chart metadata points to the public signing key.

Signed Helm chart publishing requires:

- a GPG private key available to the release workflow;
- `helm package --sign` or chart-releaser signing configuration;
- a published `.tgz.prov` file next to the chart package;
- `artifacthub.io/signKey` in `Chart.yaml`;
- the public GPG key served from the Helm repository.

The `Chart.yaml` annotation should look like:

```yaml
annotations:
  artifacthub.io/signKey: |
    fingerprint: YOUR_GPG_KEY_FINGERPRINT
    url: https://oliinykdm.github.io/fitpub-helm/pgp-public-key.asc
```

Do not add this annotation until the public key is published and release signing is enabled, otherwise Artifact Hub will show incomplete signing metadata.

## Typical Setup

Create or choose a dedicated release signing key:

```bash
gpg --full-generate-key
gpg --list-secret-keys --keyid-format LONG
```

Export the private key for GitHub Actions:

```bash
gpg --export-secret-keys YOUR_KEY_FINGERPRINT | base64 > gpg-private-key.asc.b64
```

Export the public key for GitHub Pages:

```bash
gpg --armor --export YOUR_KEY_FINGERPRINT > pgp-public-key.asc
```

Recommended GitHub Actions secrets:

- `GPG_KEYRING_BASE64`: base64-encoded private key export
- `GPG_KEY_NAME`: key fingerprint or key ID used for signing
- `GPG_PASSPHRASE`: key passphrase, if the key has one

After signing is wired into the release workflow, verify locally:

```bash
helm repo update fitpub
helm pull fitpub/fitpub --version 0.2.2 --prov
curl -fsSL https://oliinykdm.github.io/fitpub-helm/pgp-public-key.asc | gpg --import
helm verify fitpub-0.2.2.tgz
```
