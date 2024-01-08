#!/bin/bash
WORKDIR=${BASEDIR}/workdir/
mkdir -p ${BASEDIR}/.ssh
mkdir -p $WORKDIR
cd $WORKDIR/..
SECRET=$(/usr/bin/secret2sshkey --secret ssh-key-secret --ssh-dir ${BASEDIR}/.ssh)
echo $SECRET
IDENTITY=`echo $SECRET | awk -F ' ' '{print $3}' | awk -F '=' '{print $2}'`
echo "Using IDENTITY=$IDENTITY"
chmod -R go-rwx ${BASEDIR}/.ssh
echo "mount root@$REMOTEHOST:$REMOTEDIR in $WORKDIR"
echo "root@$REMOTEHOST:$REMOTEDIR $WORKDIR  fuse.sshfs noauto,x-systemd.automount,_netdev,users,idmap=user,AddressFamily=inet,StrictHostKeyChecking=accept-new,IdentityFile=$IDENTITY,port=$REMOTEPORT,allow_other,reconnect 0 0" >> /etc/fstab
#sshfs -p $REMOTEPORT -o AddressFamily=inet,StrictHostKeyChecking=accept-new  root@$REMOTEHOST:$REMOTEDIR $WORKDIR
/bin/mount $WORKDIR
if [ ! -f ${BASEDIR}/.vscode/settings.json ]
then
    mkdir -p ${BASEDIR}/.vscode && echo '{"workbench.colorTheme": "Visual Studio Dark"}' | tee ${BASEDIR}/.vscode/settings.json
fi

LINKS=".local .cargo .bash_history .bashrc .profile .gitconfig .config .rustup go"
for LINK in $LINKS ; do
    if [ ! -e "${BASEDIR}/${LINK}" ] ; then
        echo "Linking ${BASEDIR}/${LINK}"
        ln -svf /vscode/${LINK} ${BASEDIR}/${LINK} || true
    fi
done

/usr/bin/entrypoint.sh --auth none --disable-telemetry --bind-addr 0.0.0.0:8080 --app-name \"$APPNAME\" .