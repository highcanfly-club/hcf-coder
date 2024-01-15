# secret2sshkey

This will create an executable named secret2sshkey.

## Using secret2sshkey in a Kubernetes Cluster

`secret2sshkey` is designed to be used within a Kubernetes cluster. It accesses Kubernetes secrets, and the access depends on the configuration of your Kubernetes cluster.

Here is a sample Kubernetes deployment that includes the necessary permissions:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: secret2sshkey-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: secret2sshkey
  template:
    metadata:
      labels:
        app: secret2sshkey
    spec:
      containers:
        - name: secret2sshkey
          image: <your-image>
          command: ["./secret2sshkey"]
      serviceAccountName: secret2sshkey
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: secret2sshkey
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: secret-reader
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "watch", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-secrets
subjects:
  - kind: ServiceAccount
    name: secret2sshkey
roleRef:
  kind: Role
  name: secret-reader
  apiGroup: rbac.authorization.k8s.io
```

This deployment creates a Deployment for `secret2sshkey`, a ServiceAccount with the same name, a Role that allows reading secrets, and a RoleBinding that assigns the role to the service account. Replace <your-image> with the Docker image that contains the `secret2sshkey` executable.

Please note that the actual configuration might vary depending on your specific use case and security requirements.
