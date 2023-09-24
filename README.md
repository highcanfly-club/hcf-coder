# hcf-coder

this is a slighty modified https://github.com/coder/code-server  
We need to run it in our Kubernetes cluster and we need to mount our working dir via sshfs. 
This is how we run it
- The secret is composed with 3 datas:
  * ssh-privatekey
  * ssh-publickey
  * ssh-key-type  
  
# Tools included
- php
- go
- rustc
- clang/llvm
- clang-cl / llvm-link: shortcuts $CL $LINK
  - for targetting MSVC x86 use . /usr/local/bin/msvc-x86.env
  
# Install with helm
```
helm repo add highcanfly https://helm-repo.highcanfly.club/
  helm repo update highcanfly
  helm install --create-namespace --namespace sandbox-code-server hcf-coder highcanfly/hcf-coder --values values.yaml
```
Values containes:
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

# Install with kubectl
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

# Helm chart
It can be deployed with a basic helm chart.  
```bash
helm repo add highcanfly https://helm-repo.highcanfly.club/
helm repo update
helm install --namespace sandbox hcf-coder highcanfly/hcf-coder --values _values.yaml
```

With _values.yaml something like **namespace is hardcoded in ingress.annotations**:
```yaml
remoteHost: "192.168.0.1"
remotePath: "/srv/www"
sshPrivatekey: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAaAAAABNlY2RzYS
    1zaGEyLW5pc3RwMjU2AAAACG5pc3RwMjU2AAAAQQTJ98GpmVJ0xE1KtHciG7SCy5zN+sGz
    NA2dFznfM/a3XIF0i9GARjmdweyt4zcSWHqkN1DwVzkQ0yqRQWS0dhAZAAAAsEiE6rFIhO
    qxAAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBMn3wamZUnTETUq0
    dyIbtILLnM36wbM0DZ0XOd8z9rdcgXSL0YBGOZ3B7K3jNxJYeqQ3UPBXORDTKpFBZLR2EB
    kAAAAhAPpcZtCzORWCy7Ren/yAoURQBtRhiXzvsLCLDmT5OE9bAAAAEXJsZW1laWxsQEdJ
    R0FUQUJYAQIDBAUG
    -----END OPENSSH PRIVATE KEY-----
sshPublickey: "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBMn3wamZUnTETUq0dyIbtILLnM36wbM0DZ0XOd8z9rdcgXSL0YBGOZ3B7K3jNxJYeqQ3UPBXORDTKpFBZLR2EBk= ronan@example.org"
sshKeyType: ecdsa
ingress:
  ingressClassName: haproxy
  annotations:
    haproxy.org/auth-type: basic-auth
    haproxy.org/auth-secret: sandbox/vscode-coder-credentials
  hosts:
    - host: coder.exaple.org
      clusterIssuer: ca-issuer
users:
  - user1: JDEkZGNsN2s3WkYkQ2FCTEhKTmpxYy9INjR3OTlRd3JEMAo= #openssl passwd -1 1septembre2023 | base64
  - user2: JDEkMVFjR1BIYS8kY0hHSy9KSzlRSWQwT3A3NlV0MU42Lwo= #openssl passwd -1 01septembre2023 | base64
```