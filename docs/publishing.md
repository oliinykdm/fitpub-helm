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
- `helm package --sign` with the release signing key;
- a published `.tgz.prov` file next to the chart package;
- `artifacthub.io/signKey` in `Chart.yaml`;
- the public GPG key served from the Helm repository.

The chart uses this signing key metadata:

```yaml
annotations:
  artifacthub.io/signKey: |
    fingerprint: E4C86577339895552E1CAB5E49BD9E5EA6C243B7
    url: https://oliinykdm.github.io/fitpub-helm/pgp-public-key.asc
```

The release workflow signs chart packages with `helm package --sign` and publishes `pgp-public-key.asc` to the Helm repository.

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

Required GitHub Actions secrets:

- `GPG_KEYRING_BASE64`: base64-encoded private key export
- `GPG_PASSPHRASE`: key passphrase, if the key has one

The release workflow signs packages with `helm package --sign --key "FitPub Helm Chart Release"`.
That `--key` value must be a substring of the GPG UID, not the fingerprint. The
fingerprint is used by Artifact Hub in `artifacthub.io/signKey`.

After signing is wired into the release workflow, verify locally (replace `<version>` with the current chart version):

```bash
helm repo update fitpub
helm pull fitpub/fitpub --version <version> --prov
curl -fsSL https://oliinykdm.github.io/fitpub-helm/pgp-public-key.asc | gpg --import
helm verify fitpub-<version>.tgz
```
