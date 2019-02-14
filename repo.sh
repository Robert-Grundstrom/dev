DISTRIB=$1
VERSION=$2
MNTDEST="/var/www/html"
DKIMAGE="$DISTRIB:repo"
DKNAME="$DISTRIB-docker"
CENTOS_SALTREPO="https://repo.saltstack.com/yum/redhat/salt-repo-latest-2.el$VERSION.noarch.rpm"
UBUNTU_SALTREPO="https://repo.saltstack.com/apt/ubuntu/$VERSION/latest"
WORKDIR=$(pwd)

# ########################### #
# Check script compability.   #
# ########################### #
function check_version () {
case "$DISTRIB.$VERSION" in
  centos.6)
    echo "OK" > /dev/null
  ;;
  centos.7)
    echo "OK" > /dev/null
  ;;
  ubuntu.14.04)
    DISTNAME="thrusty"
  ;;
  ubuntu.16.04)
    DISTNAME="xenial"
  ;;
  ubuntu.18.04)
    DISTNAME="bionic"
  ;;
  *)
cat << EOF
Warning unknown distribution or version!
Supported distributions and versions for
this script is:
- ubuntu 14.04
- ubuntu 16.04
- ubuntu 18.04
- centos 6
- centos 7

command syntax:
./create-repo <distribution> <version>
EOF
exit 1
  ;;
esac
}

# ############################## #
# Create docker file for CentOS. #
# ############################## #
function centos_docker () {
MNTPATH="/var/www/html/$DISTRIB/$VERSION"
mkdir -p $MNTPATH 1&2> /dev/null
cat << EOT >> $WORKDIR/$DKNAME
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
}

function centos_clean_build () {
    docker exec $DKNAME /bin/sh -c 'rm -f $(/usr/bin/repomanage -ock 3 '$MNTDEST')'
    docker exec $DKNAME createrepo -g $MNTDEST/base/comps.xml $MNTDEST
    docker exec $DKNAME mkdir -p $MNTDEST/rpm-gpg/
    docker exec $DKNAME cp -r /etc/pki/rpm-gpg/* $MNTDEST/rpm-gpg/
}

# ############################## #
# Create docker file for Ubuntu. #
# ############################## #
function ubuntu_docker () {
cat << EOT >> $WORKDIR/$DKNAME
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

# Move to our work directory and check syntax.
cd $WORKDIR
check_version

# Build the docker file for our docker image.
$DISTRIB"_docker"
docker build -t $DKIMAGE -f $DKNAME .

# Run our priviously build docker container.
docker run -v $MNTPATH:$MNTDEST --name $DKNAME -t -d $DKIMAGE

# Create our repositorys.
case $DISTRIB in
  ubuntu)
# WIP e.g. insert code here!
  ;;
  centos)
    centos_repo base
    centos_repo centosplus
    centos_repo extras
    centos_repo updates
    centos_repo epel
    centos_repo salt-latest
    centos_clean_build
  ;;
esac

# Stop the docker.
docker stop $DKNAME

# Clean up dockers and files.
docker system prune -f --all
rm -f $WORKDIR/$DKNAME
