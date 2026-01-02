

# k8s-lab-automation

This repository contains a Bash-based automation for setting up a **local Kubernetes lab on macOS** using **Minikube with the VFKit driver**, Ingress, DNS resolution for local domains, and ArgoCD.

The goal of the project is to provide a **repeatable, minimal-friction local Kubernetes environment** suitable for experimentation, learning, and prototyping GitOps workflows.

---

## Problem Statement

Running Minikube on macOS with a realistic networking setup is not trivial.

In practice, the following issues arise:

* The default Minikube drivers do not provide reliable networking behavior for Ingress and DNS on macOS.
* The `vfkit` driver requires **explicit system-level dependencies** (`vfkit` itself and `vmnet-helper`) that are easy to miss.
* `ingress-dns` alone is not sufficient:

  * macOS needs resolver configuration (`/etc/resolver`)
  * CoreDNS inside the cluster must be explicitly extended
* Without proper `vmnet-shared` networking, egress, Ingress, and DNS resolution behave inconsistently or fail silently.

As a result, a “simple” local cluster often turns into hours of debugging undocumented edge cases.

---

## Solution

This repository provides a **single setup script** that automates the full workflow:

* Starts Minikube with `vfkit` and `vmnet-shared`
* Enables Ingress and Ingress-DNS addons
* Configures DNS on the macOS host
* Extends CoreDNS inside the cluster for a local domain
* Installs ArgoCD and exposes it via HTTPS Ingress

The script intentionally focuses on **deterministic behavior**, not flexibility.

---

## What This Repository Does

* Creates a Minikube cluster with predictable networking
* Makes `*.lab-local.minikube` resolvable from:

  * the macOS host
  * inside the Kubernetes cluster
* Exposes ArgoCD via HTTPS using Ingress
* Prints credentials and validates DNS resolution

---

## Requirements (macOS)

This setup is **macOS-specific** and requires the following components to be installed **before running the script**.

### vfkit

Minikube VM driver for macOS.

```bash
brew install vfkit
```

Verify:

```bash
vfkit --version
```

---

### vmnet-helper

Required for `vmnet-shared` networking.

```bash
curl -fsSL https://github.com/minikube-machine/vmnet-helper/releases/latest/download/install.sh | bash
```

Installs to:

```
/opt/vmnet-helper
```

#### Allow vmnet-helper to run as root

If you declined automatic sudoers setup during installation, install it manually:

```bash
sudo install -m 0640 \
  /opt/vmnet-helper/share/doc/vmnet-helper/sudoers.d/vmnet-helper \
  /etc/sudoers.d/
```

Requirements:

* owned by `root`
* not writable by unprivileged users

---

### kubectl

```bash
brew install kubectl
```

---

## Usage

1. Clone the repository:

```bash
git clone https://github.com/ruleito/k8s-lab-automation.git
cd k8s-lab-automation
```

2. Make the script executable and run it:

```bash
chmod +x setup-kind.sh
./setup-kind.sh
```

3. After completion, the script prints:

* Minikube IP
* ArgoCD admin password
* Access URL:

```
https://argocd.lab-local.minikube
```

---

## Design Notes

* `vmnet-shared` is used intentionally to provide stable egress and predictable routing.
* DNS is configured on **both sides**:

  * macOS resolver (`/etc/resolver`)
  * in-cluster CoreDNS
* Timing delays are used instead of complex readiness logic to keep the script simple and readable.
* This setup is intended for **local labs only**, not production environments.

---

## References

* Minikube VFKit driver
  [https://minikube.sigs.k8s.io/docs/drivers/vfkit/](https://minikube.sigs.k8s.io/docs/drivers/vfkit/)

* Ingress-DNS addon (macOS)
  [https://minikube.sigs.k8s.io/docs/handbook/addons/ingress-dns/#Mac](https://minikube.sigs.k8s.io/docs/handbook/addons/ingress-dns/#Mac)

* Minikube networking issues
  [https://github.com/kubernetes/minikube/issues/21072](https://github.com/kubernetes/minikube/issues/21072)

---

## Scope

This repository intentionally does **not**:

* manage TLS certificates beyond basic HTTPS
* support multiple clusters or domains
* abstract configuration into flags or variables

It is meant to be **understandable, reproducible, and boring**.
