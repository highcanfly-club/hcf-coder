Namespace='sandbox-code-server'
load('ext://helm_resource', 'helm_resource', 'helm_repo')

default_registry('ttl.sh/sanbox-code-server-17az238')
Registry='ttl.sh/sanbox-code-server-17az238'

os.putenv ( 'DOCKER_REGISTRY' , Registry ) 
os.putenv('NAMESPACE',Namespace)

allow_k8s_contexts('kubernetesOCI')

custom_build('highcanfly/code-server','./kaniko-build.sh',[
  './secret2sshkey','./scripts'
],skips_local_docker=True, 
  live_update=[
    sync('./secret2sshkey', '/home/coder/'),
    sync('./scripts','/tmp/')
])

helm_resource('code-server', 
              './helm/hcf-coder', 
              image_deps=['highcanfly/code-server'],
              image_keys=[('image.repository', 'image.tag')],
              namespace=Namespace,
              flags=['--values=./_values.yaml'])
