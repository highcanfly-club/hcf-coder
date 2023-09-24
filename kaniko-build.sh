#!/bin/bash
# Tiltfile looks like:
# os. putenv ( 'DOCKER_USERNAME' , 'registry-user' )
# os. putenv ( 'DOCKER_PASSWORD' , 'password' )
# os. putenv ( 'DOCKER_EMAIL' , 'none@example.org' )
# os. putenv ( 'DOCKER_REGISTRY' , 'registry.example.org' )
# Namespace='sandbox-hcfp'
# os.putenv('NAMESPACE',Namespace)
# allow_k8s_contexts('kubernetes-admin')
# k8s_yaml(helm('./k8s/helm/hcfmailerplus', name='hcfmailer-plus', namespace=Namespace, values='dev-values.yaml'))
# custom_build('highcanfly/hcfmailer-plus','./kaniko-build.sh',['./autocert', './scripts'],skips_local_docker=True)

#kubectl create secret generic registry-credentials --from-file=.dockerconfigjson=$HOME/.docker/config.json --type=kubernetes.io/dockerconfigjson
#
#   EXPECTED_REF=serveur/highcanfly_hcfmailer-plus:tilt-build-1683738819
#   EXPECTED_IMAGE=highcanfly_hcfmailer-plus
#   EXPECTED_TAG=tilt-build-1683738819
#   REGISTRY_HOST=server.fqdn
#   EXPECTED_REGISTRY=server.fqdn
echo "NAMESPACE=$NAMESPACE"
KANIKO_POD=$(kubectl -n $NAMESPACE get pods | grep "kaniko" | cut -d' ' -f1)
BAD_RANDOM=$(echo $RANDOM-$RANDOM-$RANDOM-$RANDOM | openssl dgst -sha1 )
kubectl create namespace $NAMESPACE
#kubectl create -n $NAMESPACE secret generic ssh-key-secret --from-file=ssh-privatekey=$HOME/.ssh/id_ecdsa --from-file=ssh-publickey=$HOME/.ssh/id_ecdsa.pub --from-literal=ssh-key-type=ecdsa
echo "CURRENT KANIKO POD is kaniko-$BAD_RANDOM"
kubectl -n $NAMESPACE delete pod --wait=false $KANIKO_POD 2>/dev/null
tar -cv --exclude "node_modules" --exclude "dkim.rsa" --exclude "private" --exclude "k8s" --exclude ".git" --exclude ".github" --exclude-vcs --exclude ".docker" --exclude "_sensitive_datas" -f - . | gzip -9 | kubectl run -n $NAMESPACE kaniko-$BAD_RANDOM \
  --rm --stdin=true \
  --image=highcanfly/kaniko:latest --restart=Never \
  --overrides='{
  "apiVersion": "v1",
  "spec": {
    "containers": [
      {
        "name": "kaniko",
        "image": "highcanfly/kaniko:latest",
        "imagePullPolicy": "Always",
        "stdin": true,
        "stdinOnce": true,
        "args": [
          "-v","info",
          "--dockerfile=Dockerfile'$EXT'",
          "--context=tar://stdin",
          "--skip-tls-verify",
          "--destination='$EXPECTED_REF'",
          "--image-fs-extract-retry=3",
          "--push-retry=3",
          "--cache=true",
          "--cache-ttl=24h",
          "--cache-repo='$DOCKER_REGISTRY-cache'"
        ]
      }
    ],
    "restartPolicy": "Never"
  }
}'

#kubectl delete -n $NAMESPACE secret/registry-credentials
