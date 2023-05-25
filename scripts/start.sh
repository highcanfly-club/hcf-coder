#!/bin/bash
mkdir -p /root/.ssh
SECRET=$(/usr/bin/secret2sshkey --secret ssh-key-secret --ssh-dir /root/.ssh)
echo $SECRET
IDENTITY=`echo $SECRET | awk -F ' ' '{print $3}' | awk -F '=' '{print $2}'`
echo "Using IDENTITY=$IDENTITY"
chmod -R go-rwx /root/.ssh
echo "mount root@$REMOTEHOST:$REMOTEDIR in /home/coder/workdir/"
echo "root@$REMOTEHOST:$REMOTEDIR /home/coder/workdir/  fuse.sshfs noauto,x-systemd.automount,_netdev,users,idmap=user,AddressFamily=inet,StrictHostKeyChecking=accept-new,IdentityFile=$IDENTITY,port=$REMOTEPORT,allow_other,reconnect 0 0" >> /etc/fstab
#sshfs -p $REMOTEPORT -o AddressFamily=inet,StrictHostKeyChecking=accept-new  root@$REMOTEHOST:$REMOTEDIR /home/coder/workdir/
/bin/mount /home/coder/workdir/
/usr/bin/entrypoint.sh --auth none --bind-addr 0.0.0.0:8080 .