# hcf-coder

this is a slighty modified <https://github.com/coder/code-server>  
We need to run it in our Kubernetes cluster and we need to mount our working dir via sshfs.
This is how we run it

- The secret is composed with 3 datas:
  - ssh-privatekey
  - ssh-publickey
  - ssh-key-type  
  
## Tools included

- php
- go
- Github Copilot and Copilot-chat
  - note for upgrading copilot chat you need to edit its package.json for allowing current code version (ie replacing ^1.85 by >=1.85 for example)
- rustc
  - for building for windows x86_64 use
    - `CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER=lld-link`
    - `RUSTFLAGS="-Lnative=/usr/share/msvc/crt/lib/x86_64 -Lnative=/usr/share/msvc/sdk/lib/um/x86_64 -Lnative=/usr/share/msvc/sdk/lib/ucrt/x86_64"`
- clang/llvm
- clang-cl / llvm-link: shortcuts $CL $LINK
  - for targetting MSVC x86 use `. /usr/local/bin/msvc-x86.env`
  - for reverting to MSVC x86_64 use `. /usr/local/bin/msvc.env`
- Test Windows compilation can be found in `/usr/share/msvc/test`
```bash
cd /usr/share/msvc/test
./test.sh
```

  the test.sh contains:
```bash
#!/bin/bash
$CL /I include /c src/test.c
$CL /I include /c src/MainWindow.c
$CL /I include /c src/AboutDialog.c

$LINK /subsystem:WINDOWS \
    user32.lib kernel32.lib comctl32.lib \
    test.obj MainWindow.obj AboutDialog.obj \
    /out:test.exe

$CL /I include /c src/simpletest.c
$LINK /subsystem:WINDOWS \
    user32.lib kernel32.lib comctl32.lib uuid.lib \
    simpletest.obj \
    /out:simpletest.exe
```

## Install with helm

```bash
helm repo add highcanfly https://helm-repo.highcanfly.club/
helm repo update highcanfly
helm install --create-namespace --namespace sandbox-code-server hcf-coder highcanfly/hcf-coder --values values.yaml
```

Values contains:

```yaml
DEBUG: false
remoteHost: "1.2.3.4"
remotePort: "22"
remotePath: "/a/remote/dir"
sshPrivatekey: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAaAAAABNlY2RzYS
    1zaGEyLW5pc3RwMjU2AAAACG5pc3RwMjU2AAAAQQSeaq3MxxVQypn4gx3SnFjURTU3K9O1
    Ymxsiyqolvl4mmiYBs7w27yyzPKUU3t00uW41b9iOIfTALvCCbKPb2yEAAAAwLGb0z6xm9
    M+AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBJ5qrczHFVDKmfiD
    HdKcWNRFNTcr07VibGyLKqiW+XiaaJgGzvDbvLLM8pRTe3TS5bjVv2I4h9MAu8IJso9vbI
    QAAAAhAIf1qpIpZbDWjemtj6kXfGPwLuCclj4npvobBzwvymmvAAAAIXJsZW1laWxsQEJs
    aW5nWDcubGVzbXVpZHMud2luZG93cwECAwQFBg==
    -----END OPENSSH PRIVATE KEY-----
sshPublickey: "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBJ5qrczHFVDKmfiDHdKcWNRFNTcr07VibGyLKqiW+XiaaJgGzvDbvLLM8pRTe3TS5bjVv2I4h9MAu8IJso9vbIQ= me@myhost.com"
sshKeyType: ecdsa
# if needed for retrieving two kubeconfig for using getKubeConfig
# any executable thing for generating (even empty) .kube.config to stdout
# example:
# getKubeconfigONE: 'scp user@some-server:/home/user/.kube/config /dev/stdout'
# getKubeconfigTWO: 'curl https://user:password@some-server/kube.config'
ingress:
  ingressClassName: haproxy
  annotations:
    haproxy.org/auth-type: basic-auth
    haproxy.org/auth-secret: code-server/vscode-coder-credentials
  hosts:
    - host: coder.example.org
      clusterIssuer: ca-issuer
users:
  - user: JDEkakhpTVNCaUIkSWF1SkRoM0FoejhiQXVOLzdoZkVDMAo=
  # generated with:
  # openssl passwd -1 24mai2023 | base64
persistence:
  enabled: true
  size: "1Gi"
  accessModes:
    - ReadWriteOnce
```

## Install with kubectl

For example with a local ssh key:

```sh
kubectl create -n $NAMESPACE secret generic ssh-key-secret --from-file=ssh-privatekey=$HOME/.ssh/id_ecdsa --from-file=ssh-publickey=$HOME/.ssh/id_ecdsa.pub --from-literal=ssh-key-type=ecdsa
```

```yaml
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  namespace: sandbox-code-server
  name: secret-reader
rules:
- apiGroups: [""] # "" indicates the core API group
  resources: ["secrets"]  #grants reading namespace pods and secrets
  verbs: ["get", "watch", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: secret-reader
  namespace: sandbox-code-server
subjects:
- kind: ServiceAccount
  name: default # "name" is case sensitive
  namespace: sandbox-code-server
roleRef:
  kind: Role #this must be Role or ClusterRole
  name: secret-reader 
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: v1
kind: Secret
metadata:
  namespace: sandbox-code-server
  name: vscode-coder-credentials
data:
  user: JDEkakhpTVNCaUIkSWF1SkRoM0FoejhiQXVOLzdoZkVDMAo=
  # generated with:
  # openssl passwd -1 24mai2023 | base64
type: Opaque
---
apiVersion: apps/v1
kind: Deployment
metadata:
  namespace: sandbox-code-server
  name: code-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: code-server
  template:
    metadata:
      labels:
        app: code-server
    spec:
      containers:
      - name: code-server
        image: highcanfly/code-server
        # command: ["tail"]
        # args: ["-f","/dev/null"]
        env:
        - name: REMOTEHOST
          value: "1.2.3.4"
        - name: REMOTEPORT
          value: "22"
        - name: REMOTEDIR
          value: /usr/src/hcf-app
        - name: APPNAME
          value: "High Can Fly Code-Server"
        securityContext:
            privileged: true
            capabilities:
              add:
                - SYS_ADMIN
        resources:
          limits:
            memory: "1Gi"
            cpu: "2"
        ports:
        - containerPort: 8080
      imagePullSecrets:
        - name: registry-credentials
---
apiVersion: v1
kind: Service
metadata:
  namespace: sandbox-code-server
  name: code-server-service
spec:
  type: ClusterIP
  selector:
    app: code-server
  ports:
  - port: 8080
    targetPort: 8080
    protocol: TCP
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: vscode-coder
  namespace: sandbox-code-server
  annotations:
    cert-manager.io/cluster-issuer: highcanfly-ca-issuer
    haproxy.org/auth-type: basic-auth
    haproxy.org/auth-secret: sandbox-code-server/vscode-coder-credentials
spec:
  ingressClassName: haproxy
  rules:
    - host: coder.example.org
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: code-server-service
                port:
                  number: 8080
  tls:
  - hosts: [coder.example.org]
    secretName: vscode-cert
```

## Using with Docker

Simply hit:

```sh
docker run -p 8080:8080 highcanfly/code-server:latest
```

And browse <http://localhost:8080> from your browser

## upgrading extensions
go and download the extensions from the marketplace, then copy them to the bin folder
Copilot: https://marketplace.visualstudio.com/items?itemName=GitHub.copilot  
Copilot-chat: https://marketplace.visualstudio.com/items?itemName=GitHub.copilot-chat  
Golang: https://marketplace.visualstudio.com/items?itemName=golang.Go  
Rust-analyser (in amd64 or arm64 subdir): https://marketplace.visualstudio.com/items?itemName=rust-lang.rust-analyzer  
Python: https://marketplace.visualstudio.com/items?itemName=ms-python.python  
Markdown all in one: https://marketplace.visualstudio.com/items?itemName=yzhang.markdown-all-in-one  
Git lens: https://marketplace.visualstudio.com/items?itemName=eamodio.gitlens  

Run the `change-vsix-requirements.sh` script to update the `extensions.json` file for Copilot and Copilot-chat
For validating you can run something like:
```sh
scripts/change-vsix-requirements.sh && mkdir -p tmp && cd tmp && unzip ../bin/GitHub.copilot-chat-*.vsix && cd ..
```

## Building manually

```bash
docker login --username=highcanfly
docker buildx create --use
docker buildx build -f Dockerfile.prebuild --push --platform linux/amd64,linux/arm64 --tag highcanfly/devserver-prebuild:1.99.3 --tag highcanfly/devserver-prebuild:latest  .
docker buildx build --push --platform linux/amd64,linux/arm64 --tag highcanfly/code-server:1.99.3 --tag highcanfly/code-server:latest  .

```
