DISTRIB=$1
VERSION=$2
MNTPATH="/var/www/html/centos$VERSION"
MNTDEST="/var/www/html"
DKIMAGE="centos:repo"
DKNAME="centos-docker"
DKFILE="centos-docker"
SALTREPO="https://repo.saltstack.com/yum/redhat/salt-repo-latest-2.el$VERSION.noarch.rpm"
WORKDIR=$(pwd)

function create-docker () {
echo "FROM centos:$VERSION" > $WORKDIR/$DKNAME
echo "" >> $WORKDIR/$DKNAME
echo "RUN yum install -y yum-utils epel-release createrepo" >> $WORKDIR/$DKNAME
echo "RUN yum install -y $SALTREPO" >> $WORKDIR/$DKNAME
echo "RUN rpm --import /etc/pki/rpm-gpg/*" >> $WORKDIR/$DKNAME
}

function centos-repo () {
   REPOID=$1
   docker exec $DKNAME reposync -g -l -d -m --repoid=$REPOID --newest-only --download-metadata --download_path=$MNTDEST/
   docker exec $DKNAME rm -f $(/usr/bin/repomanage --keep=3 --old $MNTDEST/$REPOID/)
   docker exec $DKNAME createrepo -g $MNTDEST/base/comps.xml $MNTDEST/$REPOID/
}
cd $WORKDIR
create-docker

docker build -t $DKIMAGE -f $DKNAME .
docker run -v $MNTPATH:$MNTDEST --name $DKNAME -t -d $DKIMAGE

# Create our repositorys.
centos-repo base
centos-repo centosplus
centos-repo extras
centos-repo updates
centos-repo epel
centos-repo salt-latest

# Stop the docker.
docker stop $DKNAME

# Clean up.
docker system prune -f --all
rm -f $WORKDIR/$DKNAME
