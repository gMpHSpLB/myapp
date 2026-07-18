# Project:
"Enterprise Kubernetes CI Pipeline: Secure Image Build, Cosign Signing, SBOM Attestation, and GitOps Promotion with GitHub Actions"

## Tool versions: 
```console
  GitHub Actions runners ubuntu-24.04,
  docker/build-push-action@v6,
  actions/checkout@v4,
  cosign-installer@v3.6.0,
  syft v1.x,
  trivy v0.58+,
  Kubernetes version: 1.31+,
  ArgoCD 2.12+,
  Helm 3.16+
```
# What You Will Build
```console
•	A production-grade GitHub Actions CI pipeline with 6 stages
•	Container image built with multi-stage Dockerfile using BuildKit cache mounts
•	Trivy vulnerability scan as a hard blocking gate (CRITICAL CVEs fail the build)
•	Cosign keyless image signing using GitHub Actions OIDC (no long-lived keys)
•	Syft SBOM generation in CycloneDX format, attested to the OCI registry
•	Helm chart linted and unit-tested in CI
•	Image tag committed to the GitOps repo as a PR (triggering ArgoCD sync)
•	Complete reusable workflow structure: one workflow calls another
•	All secrets managed via GitHub Environments, not repository secrets
```
## CI's job is to produce and verify an artefact. Delivery is ArgoCD's job.

CI produces and verifies an artefact; ArgoCD is the only thing with cluster credentials. 
Every design decision in this pipeline:
   — no kubectl apply in CI, 
   — SHA/digest tags instead of latest, 
   — A separate GitOps repo — falls out of that one boundary.
   
# Pipeline Stage Overview

<img width="2720" height="3440" alt="t05_github_actions_pipeline" src="https://github.com/user-attachments/assets/2e1ef39a-486f-4d9c-8cd5-6b73e79a89c0" />

```console
Stage 1: Test + Lint
  ├── Python unit tests (pytest)
  ├── Helm lint (helm lint --strict)
  └── helm-unittest (chart unit tests)

Stage 2: Build (depends on Stage 1)
  ├── docker buildx build (multi-platform: linux/amd64 + linux/arm64)
  ├── BuildKit cache mount (faster rebuilds)
  └── Push to GHCR with SHA tag

Stage 3: Security Scan (depends on Stage 2)
  ├── trivy image scan
  ├── CRITICAL CVE → fail build (exit non-zero)
  └── Scan report uploaded as GitHub Actions artefact

Stage 4: Sign + Attest (depends on Stage 3)
  ├── cosign sign (keyless — OIDC via GitHub Actions)
  ├── syft generate SBOM (CycloneDX JSON)
  └── cosign attest (attach SBOM to image in registry)

Stage 5: Helm Package (parallel with Stage 4)
  ├── helm package ./charts/myapp
  └── helm push oci://ghcr.io/org/charts

Stage 6: GitOps Update (depends on Stage 4)
  ├── Clone gitops-repo
  ├── Update envs/dev/values.yaml: image.tag: $DIGEST
  ├── Commit + push (direct to dev, PR for staging/prod)
  └── ArgoCD webhook fires → sync begins
```

# Storage map — where every artifact physically lives:
<img width="2720" height="2600" alt="t05_artifact_storage_map" src="https://github.com/user-attachments/assets/9fc361cb-e8d4-41fa-9a5b-8790fa1368f2" />

## Why three repos and how they link
You have:
 1. myapp repo : Contains app source code (FastAPI), Dockerfile, Helm chart, and dev/staging/prod values for development and testing.
  
 2. Gitops-Argocd_1 repo : Contains ArgoCD Application definitions and environment values for dev, staging, prod — this is the deployment config repo ArgoCD watches.
  
 3. OCI registry (GHCR) : Stores built container images and Helm charts (ghcr.io/gmphsplb/myapp, ghcr.io/gmphsplb/helm-lab).

### How they link:
  - CI in myapp builds and pushes the image/chart to GHCR.
  - The same CI updates the Gitops-Argocd_1 repo (values files) to point to the new image digest / version.
  - ArgoCD is configured to watch the Gitops-Argocd_1 repo; when values change (and PR is merged), ArgoCD syncs the cluster to match Git.

So:
myapp repo = how to build & test the app.
GHCR = where the built artifacts live.
Gitops-Argocd_1 = what should be deployed where.

### This separation is a recommended GitOps pattern: 
  - app code in one repo, deployment config in another, artifacts in a registry. 
  - It decouples development from operations and lets ArgoCD only need read access to the config repo and registry.

## Why both repos have environment values
You effectively have two layers of environment-specific config:

1. myapp repo values
  - Used for development/CI: helm lint, helm unittest, maybe local dev cluster installs.
  - Owned by the app team; close to the chart and code.

2. Gitops-Argocd_1 envs/dev|staging|prod/values.yaml
  - Used for actual deployments in the cluster, via ArgoCD.
  - Owned by the ops/platform/GitOps perspective.

### Why have both:
It lets you:
    - Test the chart in myapp with realistic values (dev/staging/prod) without touching the live cluster config.
    - Keep deployment ownership and promotion rules in a dedicated GitOps repo (Gitops-Argocd_1), including PR approvals, audit trail, and  
      environment separation.

Over time, you can converge these so that Gitops-Argocd_1 values become the single source of truth, and myapp’s values are used only for 
local testing or are even removed if you prefer one config repo pattern.

In short: myapp values are for pre-deploy validation; Gitops-Argocd_1 values are for actual deployment state that ArgoCD enforces.

## When OCI is used vs when Gitops-Argocd_1 comes in
### OCI (GHCR) use
  OCI registry is used when:
    1. CI runs in myapp:
        - Builds the Docker image and pushes ghcr.io/gmphsplb/myapp@sha256:....
        - Packages the Helm chart and pushes oci://ghcr.io/gmphsplb/helm-lab/myapp.
    2. ArgoCD deploys:
        - Kubernetes pulls the image from GHCR.
        - (If you configure ArgoCD to use the OCI Helm chart directly, Helm in ArgoCD pulls from GHCR too.)
  So OCI is the artifact store: images and charts live there, immutable and versioned.

### Gitops-Argocd_1 use
  Gitops-Argocd_1 comes into play when:
    -  You want to change what is deployed: you update envs/dev/values.yaml or envs/staging/values.yaml to point to a new image digest or 
       change config.
    -  CI (from myapp) automates that change by:
         - Checking out Gitops-Argocd_1.
         - Updating image.digest, image.tag, image.repository in envs/dev or envs/staging.
         - Committing/pushing and creating a PR for staging.
    -  ArgoCD monitors Gitops-Argocd_1:
         - Sees that values changed.
         - Syncs the cluster to those new values (deploying the new image from GHCR).
  So Gitops-Argocd_1 is the declarative desired state for each environment; OCI is the actual artifact that implements that state.


## Security scan job
### What is a “security scan”?
A security scan is an automated check that looks for known security problems in your software before you deploy it.

In our case, it scans:
  - The container image ghcr.io/gmphsplb/myapp@sha256:... for:
      - Vulnerable OS packages (Debian, etc.).
      - Vulnerable Python libraries and other dependencies.
  - Your Dockerfile and Kubernetes manifests for misconfigurations (dangerous settings, insecure defaults).

### Which tool is used and why?
You use Trivy, an open‑source security scanner from Aqua Security.
   - In the “Run Trivy vulnerability scanner” step, it runs:
    ```console
      text
      trivy image ghcr.io/gmphsplb/myapp@sha256:...
      This scans the built image for vulnerabilities.
    ```
   - In the “Run Trivy config scan” step, it runs a config scan (scan-type: "config") on your repository to look for insecure
     Infrastructure‑as‑Code settings (Dockerfile, Kubernetes YAML).

You chose Trivy because:
  - It’s widely used, free, and supports images, files, and config.
  - It integrates easily with GitHub Actions and can export results to SARIF so they show up in GitHub’s Security tab

## Sign + attest job
The “Sign + Attest” job is about trust and transparency for your image.

### What does “sign” and “attest” mean?
Sign: Create a digital signature on the image, proving:
   - Who built it (identity).
   - That it hasn’t been tampered with (integrity).
Attest: Attach signed extra information about the image, such as:
   - SBOM (what’s inside).
   - Build details (when, how, from which repo).
You use Cosign to sign and attest, and Syft to generate SBOM.

## What is SBOM?
SBOM = Software Bill of Materials.
  - It’s like an ingredient list for your software.
  - It lists all components, libraries, and dependencies inside your image in a machine‑readable format.
  - SBOM helps you:
     - Know exactly what’s inside the image.
     - Quickly check for vulnerable or outdated components.
     - Meet security and compliance requirements (e.g., government SBOM mandates).
Syft is the tool generating this SBOM for your image.

## Syft SBOM attestation
Your pipeline then:
  1. Uses Syft to generate SBOMs (CycloneDX and SPDX) for the image.
  2. Uses Cosign attest to attach the SBOM as an attestation:
   ```console
    bash
    cosign attest \
      --yes \
      --type cyclonedx \
      --predicate sbom.cyclonedx.json \
      "ghcr.io/gmphsplb/myapp@sha256:..."
  ```
Meaning:
   - The SBOM file (CycloneDX format) is sent to GHCR as an attestation linked to the image.
   - It is signed with the same keyless mechanism, so:
        - You can verify it was created by your CI.
        - You can trust the SBOM has not been tampered with.
Later, anyone with access to the image can run:
```console
bash
cosign verify-attestation --type cyclonedx ghcr.io/gmphsplb/myapp@sha256:...
```
to fetch and verify the SBOM attestation, getting a trusted ingredient list for the image.


## OIDC token and keyless signing (Cosign + Sigstore)
Your Cosign step uses keyless signing via Sigstore.

### What is an OIDC token?
OIDC = OpenID Connect, an identity protocol.
  - An OIDC token is a signed token that says:
      - “This GitHub Actions job is running in repo gMpHSpLB/myapp, on this workflow, by this actor.”
When the pipeline runs, GitHub can give an OIDC token that proves which repo and workflow started this job.

### “GitHub Actions provides OIDC token proving this job ran from this repo”
Meaning:
  - Cosign asks GitHub: “Who am I?”.
  - GitHub returns an OIDC token saying:
      - “This request comes from a GitHub Actions job for repository gMpHSpLB/myapp (and specific workflow).”
  - Cosign uses that token as the identity of the signer.
So you don’t log in with a username/password; the CI job itself is the identity.

### What is Fulcio CA and what does it do?
Fulcio is Sigstore’s certificate authority (CA).
  - It takes the OIDC token from GitHub and checks that it’s valid.
  - Then it issues a short‑lived certificate that says:
        “This temporary key belongs to the GitHub Actions identity for repo gMpHSpLB/myapp.”

### “Fulcio CA issues a short-lived certificate bound to the OIDC identity”
Meaning:
  - A temporary public/private keypair is created in memory.
  - Fulcio gives a certificate that ties that key to the GitHub Actions identity (your repo/workflow).
  - The certificate only lives for a short time (minutes), then expires.
So instead of a long‑lived private key you have to store, you get a disposable certificate linked to “this CI job”.

### What does “Cosign signs the image digest with the certificate key” mean?
Your command:
```console
  bash
  cosign sign \
    --yes \
    --oidc-issuer=https://token.actions.githubusercontent.com \
    "ghcr.io/gmphsplb/myapp@${DIGEST}"
```
What happens:
  - Cosign computes the digest (hash) of the image (sha256:…).
  - It uses the temporary private key (from Fulcio’s certificate) to create a digital signature over that digest.
  - That signature can later be verified with the corresponding public key/certificate.

So “sign the image digest” means: lock the image’s hash with a cryptographic signature tied to your CI identity.

### “Signature stored in OCI registry as a separate manifest”
Cosign stores the signature in GHCR next to the image, not inside it.
  - GHCR supports extra “manifest” objects associated with an image.
  - Cosign pushes a signature object that says:
      - “Here is the signature for ghcr.io/gmphsplb/myapp@sha256:....”
So:
  - The image stays the same.
  - The registry holds an additional signed record saying “this image was signed by your CI job”.

### What is Sigstore Rekor and “transparency log records the signature permanently”?
Rekor is Sigstore’s transparency log.
  - It’s a public, append‑only log of all signatures and attestations.
  - Every time you sign, a record is written that includes:
       - Image digest.
       - Certificate.
       - Signature.
       - Timestamp.

### “Records the signature permanently” means:
  - The signing event is stored in Rekor.
  - Anyone can later look up:
      - When it was signed.
      - By which identity.
      - For which artifact.

This gives an audit trail and makes it much harder for an attacker to fake or hide signatures.

### “Key never stored anywhere — certificate expires after the signing”
This summarizes why it’s called keyless signing:
  - The private key used to sign:
      - Exists only in memory during the signing.
      - Is destroyed afterwards.
  The certificate:
      - Is short‑lived (expires quickly).
      - Attests to the identity at signing time.

You don’t:
  - Generate and store long‑term signing keys.
  - Manage key rotation or secret storage for signing keys.

Instead:
  - Each CI run gets a fresh, short‑lived identity and key.
  - Rekor’s log and Fulcio’s certificate provide trust and verifiability.

This reduces risk: there is no long‑lived private key that can be stolen.

<img width="2720" height="1840" alt="t05_job4_5_6_data_flow" src="https://github.com/user-attachments/assets/7f49da37-e103-4ec8-823c-26a2454434ab" />

