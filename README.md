# Inception-of-Things (IoT)

> Projet d'introduction à **Kubernetes** de l'école 42. En trois étapes, on passe
> d'une simple machine virtuelle à un pipeline de déploiement continu (GitOps)
> piloté par Argo CD.

Ce README explique **ce que fait chaque partie, pourquoi, et comment la lancer**.
Il est écrit pour quelqu'un qui découvre Kubernetes : chaque outil est présenté
au moment où il devient nécessaire.

---

## Sommaire

1. [Les outils, en deux mots](#1-les-outils-en-deux-mots)
2. [Vue d'ensemble du projet](#2-vue-densemble-du-projet)
3. [Prérequis](#3-prérequis)
4. [Partie 1 : un cluster K3s à deux machines](#4-partie-1--un-cluster-k3s-à-deux-machines)
5. [Partie 2 : trois applications derrière un Ingress](#5-partie-2--trois-applications-derrière-un-ingress)
6. [Partie 3 : K3d et Argo CD (GitOps)](#6-partie-3--k3d-et-argo-cd-gitops)
7. [Commandes utiles](#7-commandes-utiles)
8. [Problèmes rencontrés et solutions](#8-problèmes-rencontrés-et-solutions)
9. [Glossaire](#9-glossaire)

---

## 1. Les outils, en deux mots

| Outil | Rôle | Analogie |
|---|---|---|
| **Vagrant** | Décrit et crée des machines virtuelles à partir d'un fichier texte (`Vagrantfile`). | Une recette de cuisine pour fabriquer une VM à l'identique. |
| **VirtualBox** | L'hyperviseur qui exécute réellement les VM créées par Vagrant. | Le four qui cuit la recette. |
| **Kubernetes (K8s)** | Orchestrateur de conteneurs : il lance, surveille, réplique et expose des applications. | Un chef d'orchestre pour conteneurs Docker. |
| **K3s** | Distribution *légère* de Kubernetes (un seul binaire, ~100 Mo). Parfaite pour une VM. | Kubernetes « de poche ». |
| **K3d** | Lance un cluster K3s **dans des conteneurs Docker** au lieu de VM. Plus rapide, plus léger. | K3s dans une boîte Docker. |
| **kubectl** | L'outil en ligne de commande pour parler au cluster. | La télécommande du cluster. |
| **Traefik** | Le *reverse proxy* livré avec K3s. Il joue le rôle d'**Ingress Controller**. | Le réceptionniste qui oriente les visiteurs. |
| **Argo CD** | Outil **GitOps** : il surveille un dépôt Git et applique automatiquement ce qu'il contient sur le cluster. | Un robot qui synchronise Git et le cluster. |

### K3s vs K3d, la différence à retenir

- **K3s** est *la distribution Kubernetes* elle-même. Elle s'installe sur une machine (ici une VM) et y tourne comme un service.
- **K3d** est *un outil* qui crée des clusters K3s en lançant chaque nœud dans un conteneur Docker. Il a donc besoin de Docker, mais il crée et détruit un cluster en quelques secondes.

---

## 2. Vue d'ensemble du projet

```
ft_Inception-of-Things/
├── p1/                      Partie 1 : cluster K3s à 2 VM (serveur + worker)
│   ├── Vagrantfile
│   ├── scripts/install_k3s.sh
│   └── confs/               (dossier partagé, reçoit le token du serveur)
├── p2/                      Partie 2 : 1 VM K3s + 3 applis web + Ingress
│   ├── Vagrantfile
│   ├── scripts/install_k3s.sh
│   └── confs/
│       ├── pages.yaml       ConfigMaps contenant les pages HTML
│       └── deployment.yaml  Deployments, Services et Ingress
├── p3/                      Partie 3 : 1 VM Docker + K3d + Argo CD
│   ├── Vagrantfile
│   ├── scripts/install.sh
│   └── confs/argocd-app.yaml
└── subject_IoT.pdf
```

Chaque partie est **indépendante** : on se place dans son dossier et on lance
`vagrant up`. Le `Vagrantfile` crée la VM, puis exécute le script du dossier
`scripts/` pour tout installer et configurer automatiquement. **Aucune action
manuelle n'est nécessaire** après `vagrant up`.

Progression pédagogique :

```
 P1                      P2                          P3
 Installer K3s     →     Déployer des applis    →    Automatiser le déploiement
 (infrastructure)        (Deployment / Service        (GitOps avec Argo CD)
                          / Ingress)
```

---

## 3. Prérequis

Sur la machine hôte :

- **VirtualBox**
- **Vagrant**
- La box Debian 12 utilisée : `koalephant/debian12` (téléchargée automatiquement au premier `vagrant up`).

> Sur un Mac Apple Silicon (arm64), la box est elle aussi en arm64. Le script de
> la partie 3 active l'émulation QEMU pour pouvoir lancer des images Docker
> amd64 (comme `wil42/playground`).

Toutes les VM utilisent le réseau privé `192.168.56.0/24`, comme exigé par le sujet.

---

## 4. Partie 1 : un cluster K3s à deux machines

### Objectif

Créer **deux VM** et les relier en un seul cluster Kubernetes :

| Machine | Rôle K3s | IP | Ressources |
|---|---|---|---|
| `hclaudeS` | **server** (control plane, le « cerveau ») | 192.168.56.110 | 1 CPU, 1 Go |
| `hclaudeSW` | **agent** (worker, exécute les pods) | 192.168.56.111 | 1 CPU, 1 Go |

### Comment ça marche

1. Le [Vagrantfile](p1/Vagrantfile) boucle sur un dictionnaire `MACHINES` pour
   définir les deux VM avec le même code. Chacune reçoit son hostname et son IP.
2. Le dossier `p1/confs/` est monté dans les deux VM sous `/vagrant`. C'est le
   **canal de communication** entre les machines.
3. Le script [install_k3s.sh](p1/scripts/install_k3s.sh) reçoit le nom de la
   machine en argument et se comporte différemment :

   - **Sur le serveur** : installe K3s en mode `server`, lié à l'IP
     `192.168.56.110`. Une fois démarré, K3s génère un **token** dans
     `/var/lib/rancher/k3s/server/node-token`. Le script le copie dans
     `/vagrant/shared/token`.
   - **Sur le worker** : attend que le fichier `token` apparaisse (boucle
     `while`), puis installe K3s en mode `agent` en pointant vers
     `https://192.168.56.110:6443` avec ce token.

Le token est le **mot de passe** qui autorise un nœud à rejoindre le cluster.
Il est ignoré par Git (voir `.gitignore`) pour ne jamais être versionné.

> `K3S_KUBECONFIG_MODE="644"` rend le fichier de configuration lisible par
> l'utilisateur `vagrant`, ce qui évite de taper `sudo` devant chaque `kubectl`.

### Lancer et vérifier

```bash
cd p1
vagrant up                 # crée les 2 VM (le serveur d'abord)
vagrant ssh hclaudeS       # connexion SSH sans mot de passe
kubectl get nodes -o wide
```

Résultat attendu : les deux nœuds en `Ready`.

```
NAME        STATUS   ROLES                  INTERNAL-IP
hclaudeS    Ready    control-plane,master   192.168.56.110
hclaudeSW   Ready    <none>                 192.168.56.111
```

---

## 5. Partie 2 : trois applications derrière un Ingress

### Objectif

Une seule VM (`hclaudeS`, 192.168.56.110) fait tourner **trois sites web**.
Le site affiché dépend du **nom de domaine** (l'en-tête HTTP `Host`) utilisé
pour appeler cette même IP :

| Requête | Application servie | Réplicas |
|---|---|---|
| `Host: app1.com` | app1 | 1 |
| `Host: app2.com` | app2 | **3** |
| `Host: app3.com` ou n'importe quoi d'autre | app3 (défaut) | 1 |

### Les briques Kubernetes utilisées

C'est ici qu'on découvre les objets de base de Kubernetes. Ils sont tous
déclarés en YAML dans [p2/confs/](p2/confs/).

```
   navigateur  ──Host: app2.com──▶  Ingress (Traefik)
                                        │  route selon le Host
                                        ▼
                                   Service app2-svc        (adresse stable)
                                        │  répartit la charge
                            ┌───────────┼───────────┐
                            ▼           ▼           ▼
                          Pod         Pod         Pod    (3 réplicas nginx)
                            ▲
                     Deployment app2-com  (maintient 3 pods vivants)
                            ▲
                     ConfigMap app2-page  (le fichier index.html)
```

- **ConfigMap** ([pages.yaml](p2/confs/pages.yaml)) : stocke le contenu de la
  page `index.html` de chaque appli. Cela évite de construire trois images
  Docker : on utilise l'image `nginx:stable` officielle et on **monte** le
  fichier HTML par-dessus sa page d'accueil.
- **Deployment** ([deployment.yaml](p2/confs/deployment.yaml)) : décrit
  l'application (image, port, volume) et le nombre de **réplicas** souhaité.
  Kubernetes s'assure en permanence que ce nombre de pods tourne.
- **Service** : donne une adresse interne stable à un groupe de pods et fait
  de la répartition de charge entre eux. Type `ClusterIP` = accessible
  uniquement à l'intérieur du cluster.
- **Ingress** : règle de routage HTTP. Traefik (installé par défaut avec K3s)
  lit cette règle et redirige chaque `Host` vers le bon Service. La règle sans
  `host` sert de **valeur par défaut** vers app3.

### Lancer et vérifier

```bash
cd p2
vagrant up
```

Depuis la machine hôte (Traefik écoute sur le port 80 de la VM) :

```bash
curl -H "Host: app1.com" http://192.168.56.110    # → page app1
curl -H "Host: app2.com" http://192.168.56.110    # → page app2
curl http://192.168.56.110                        # → page app3 (défaut)
```

Depuis la VM, pour voir les objets créés :

```bash
vagrant ssh hclaudeS
kubectl get deploy,svc,pods,ingress
kubectl describe ingress apps-ingress
```

On doit voir `app2-com` avec `3/3` pods prêts.

---

## 6. Partie 3 : K3d et Argo CD (GitOps)

### Objectif

Mettre en place un **déploiement continu** : quand on modifie un fichier dans
un dépôt GitHub public, l'application dans le cluster est mise à jour
**automatiquement**, sans toucher au cluster.

```
   développeur ──push──▶ GitHub (h-claude/hclaude-iot)
                              ▲
                              │ surveille (toutes les 3 min) et synchronise
                              │
                   ┌──────────┴─────────────────────────┐
                   │  cluster K3d (dans Docker)         │
                   │                                    │
                   │  namespace argocd ──▶ Argo CD      │
                   │  namespace dev    ──▶ wil-playground│──▶ port 8888
                   └────────────────────────────────────┘
                              ▲
                              │ pull de l'image wil42/playground:v1 ou :v2
                         Docker Hub
```

### Ce que fait le script d'installation

Le script [install.sh](p3/scripts/install.sh) s'exécute dans une VM plus
costaude (4 CPU, 4 Go) et installe tout dans l'ordre :

1. **Docker** (dépôt officiel Debian) : indispensable, K3d tourne dedans.
2. **K3d**, **kubectl** et la **CLI Argo CD**.
3. **Le cluster** : `k3d cluster create` avec deux redirections de ports sur
   le load balancer de K3d :
   - `8080 → 443` pour l'interface web d'Argo CD ;
   - `8888 → 8888` pour l'application.

   Traefik est désactivé car on n'a pas besoin d'Ingress ici : les Services
   de type `LoadBalancer` suffisent.
4. **Les deux namespaces** exigés : `argocd` et `dev`.
5. **Argo CD** via son manifeste officiel, puis deux ajustements :
   - désactivation de la vérification GPG (elle échoue dans une VM sans assez
     d'entropie) ;
   - passage du service `argocd-server` en `LoadBalancer` pour l'exposer.
6. Attente que tous les pods Argo CD soient prêts.
7. **L'Application Argo CD** ([argocd-app.yaml](p3/confs/argocd-app.yaml)) :
   c'est le cœur de la partie. Elle dit à Argo CD :
   - *source* : le dépôt `https://github.com/h-claude/hclaude-iot.git`, branche `HEAD`, racine ;
   - *destination* : ce cluster, namespace `dev` ;
   - *politique* : `automated` avec `prune` (supprime ce qui n'est plus dans Git)
     et `selfHeal` (rétablit ce qu'on modifie à la main sur le cluster).
8. Affichage du **mot de passe admin** d'Argo CD.

### Le dépôt surveillé

Le dépôt [h-claude/hclaude-iot](https://github.com/h-claude/hclaude-iot)
contient un seul fichier `deployment.yaml` : un Deployment et un Service
`LoadBalancer` pour l'image `wil42/playground` (l'application fournie par le
sujet, qui répond sur le port 8888 avec sa version).

### Lancer et vérifier

```bash
cd p3
vagrant up          # long : Docker + cluster + Argo CD (~10 min)
```

Interface Argo CD : <https://localhost:8080> (le port 8080 est redirigé de la
VM vers l'hôte). Identifiant `admin`, mot de passe affiché à la fin du
provisionnement, ou récupérable ainsi :

```bash
vagrant ssh hclaude-vm
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

Vérifier l'application :

```bash
kubectl get ns                      # argocd et dev sont Active
kubectl get pods -n dev             # wil-playground Running
curl http://localhost:8888/         # {"status":"ok","message":"v1"}
```

### Démonstration du GitOps : passer de v1 à v2

C'est la manipulation demandée en soutenance. **On ne touche pas au cluster**,
on modifie seulement Git :

```bash
# dans un clone de h-claude/hclaude-iot
sed -i 's/playground:v1/playground:v2/' deployment.yaml
git commit -am "v2" && git push
```

Argo CD détecte le changement (au plus 3 minutes, ou immédiatement avec le
bouton *Refresh* de l'interface), crée un nouveau pod avec l'image `v2` et
supprime l'ancien :

```bash
curl http://localhost:8888/         # {"status":"ok","message":"v2"}
```

---

## 7. Commandes utiles

```bash
# Vagrant
vagrant up                   # créer / démarrer
vagrant ssh <machine>        # entrer dans la VM
vagrant halt                 # éteindre
vagrant destroy -f           # tout supprimer
vagrant provision            # rejouer les scripts sans recréer la VM

# Kubernetes
kubectl get nodes -o wide
kubectl get all -A                        # tout, dans tous les namespaces
kubectl get pods -n <ns> -w               # suivre les pods en direct
kubectl describe pod <nom> -n <ns>        # comprendre pourquoi un pod ne démarre pas
kubectl logs <pod> -n <ns>
kubectl apply -f fichier.yaml / kubectl delete -f fichier.yaml

# Argo CD (CLI)
argocd login localhost:8080 --insecure
argocd app list
argocd app sync wil-playground
```

---

## 8. Problèmes rencontrés et solutions

| Symptôme | Cause | Solution appliquée |
|---|---|---|
| Le worker (P1) ne rejoint jamais le cluster. | Il démarre avant que le serveur ait écrit son token. | Boucle d'attente sur `/vagrant/shared/token` dans le script. |
| `kubectl` demande `sudo`. | Le kubeconfig est en mode 600. | `K3S_KUBECONFIG_MODE="644"` à l'installation. |
| Les pods `argocd-repo-server` échouent (P3). | La vérification GPG bloque faute d'entropie dans la VM. | Variable `ARGOCD_GPG_ENABLED=false` injectée par `kubectl patch`. |
| `ImagePullBackOff` sur `wil42/playground` sur Mac M1/M2. | L'image n'existe qu'en amd64. | Émulation QEMU (`tonistiigi/binfmt`) activée si l'hôte est arm64. |
| Interface Argo CD inaccessible depuis l'hôte. | Le service est en `ClusterIP` par défaut. | Patch en `LoadBalancer` + port 8080 mappé par K3d et par Vagrant. |

---

## 9. Glossaire

- **Cluster** : ensemble de machines (nœuds) gérées par Kubernetes.
- **Nœud (node)** : une machine du cluster. *Control plane* = celui qui décide ; *worker* = celui qui exécute.
- **Pod** : la plus petite unité déployable, généralement un conteneur.
- **Deployment** : décrit *quoi* faire tourner et *en combien d'exemplaires* ; recrée les pods qui meurent.
- **Réplica** : une copie identique d'un pod, pour la disponibilité et la charge.
- **Service** : adresse stable devant un groupe de pods. `ClusterIP` (interne), `LoadBalancer` (exposé à l'extérieur).
- **Ingress** : règle de routage HTTP par nom de domaine ou chemin, appliquée par un *Ingress Controller* (Traefik).
- **ConfigMap** : paire clé/valeur injectable dans un pod (fichiers, variables).
- **Namespace** : cloison logique dans le cluster pour isoler des ressources (`argocd`, `dev`).
- **Manifeste** : fichier YAML décrivant un objet Kubernetes.
- **GitOps** : pratique où Git est la *source de vérité* : l'état du cluster est déduit du dépôt, jamais modifié à la main.
- **Sync (Argo CD)** : action d'aligner le cluster sur le contenu de Git.
