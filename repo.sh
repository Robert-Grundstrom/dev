DISTRIB=$1
VERSION=$2
MNTPATH="/var/www/html/$DISTRIB-$VERSION"
MNTDEST="/var/www/html"
DKIMAGE="$DISTRIB:repo"
DKNAME="$DISTRIB-docker"
CENTOS_SALTREPO="https://repo.saltstack.com/yum/redhat/salt-repo-latest-2.el$VERSION.noarch.rpm"
UBUNTU_SALTREPO="https://repo.saltstack.com/apt/ubuntu/$VERSION/latest"
WORKDIR=$(pwd)

# ############################## #
# Create docker file for CentOS. #
# ############################## #
function centos_docker () {
cat <<EOT>> $WORKDIR/$DKNAME
FROM $DISTRIB:$VERSION
RUN yum install -y yum-utils epel-release createrepo
RUN yum install -y $CENTOS_SALTREPO
RUN rpm --import /etc/pki/rpm-gpg/*
RUN yum -y update
EOT
}

# ############################ #
# Build our centos repository. #
# ############################ #
function centos_repo () {
   REPOID=$1
   docker exec $DKNAME reposync -g -l -d -m --repoid=$REPOID --newest-only --download-metadata --download_path=$MNTDEST/
   docker exec $DKNAME rm -f $(/usr/bin/repomanage -ock3 $MNTDEST/$REPOID/)
   docker exec $DKNAME createrepo -g $MNTDEST/base/comps.xml $MNTDEST/$REPOID/
}

# ############################## #
# Create docker file for Ubuntu. #
# ############################## #
function ubuntu_docker () {
case $VERSION in
14.04)
  DISTNAME="thrusty"
  ;;
16.04)
  DISTNAME="xenial"
  ;;
18.04)
  DISTNAME="bionic"
  ;;
*)
  echo "Warning unknown version!"
  echo "Avaible versions are 14.04, 16.04, 18.04"
  exit 1
  ;;
esac

cat <<EOT>> $WORKDIR/$DKNAME
FROM $DISTRIB:$VERSION
RUN echo "deb $UBUNTU_SALTREPO $DISTNAME main" > /etc/apt/source.list.d/saltstack-latest
ADD $UBUNTU_SALTREPO/SALTSTACK-GPG-KEY.pub /tmp/SALTSTACK-GPG-KEY.pub
RUN apt-key add /tmp/SALTSTACK-GPG-KEY.pub
RUN apt update
RUN apt -y intstall apt-mirror
RUN apt -y upgrade
EOT
}

# ################### #
# Script starts here. #
# ################### #
cd $WORKDIR
$DISTRIB"_docker"

docker build -t $DKIMAGE -f $DKNAME .
docker run -v $MNTPATH:$MNTDEST --name $DKNAME -t -d $DKIMAGE

# Create our repositorys.
case $DISTRIB in
  ubuntu)

  ;;
centos)
  centos_repo base
  centos_repo centosplus
  centos_repo extras
  centos_repo updates
  centos_repo epel
  centos_repo salt-latest
  ;;
*)
  echo "Warning unknown distribution!"
  echo "Avaible destributions is centos or ubuntu"
  exit 1
  ;;
esac

# Stop the docker.
docker stop $DKNAME

# Clean up dockers and files.
docker system prune -f --all
rm -f $WORKDIR/$DKNAME
