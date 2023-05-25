# hcf-coder

this is a slighty modified https://github.com/coder/code-server  
We need to run it in our Kubernetes cluster and we need to mount our working dir via sshfs. 
This is how we run it
- The secret is composed with 3 datas:
  * ssh-privatekey
  * ssh-publickey
  * ssh-key-type
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