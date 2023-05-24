#!/bin/bash
/usr/bin/secret2sshkey --secret ssh-key-secret --ssh-dir /root/.ssh
chmod -R go-rwx /root/.ssh
sshfs -p $REMOTEPORT -o AddressFamily=inet,StrictHostKeyChecking=accept-new  root@$REMOTEHOST:$REMOTEDIR /home/coder/workdir/
/usr/bin/entrypoint.sh --auth none --bind-addr 0.0.0.0:8080 .
