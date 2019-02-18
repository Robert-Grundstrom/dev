DISTRIB=$1
VERSION=$2
DKIMAGE="$DISTRIB:repo"
DKNAME="$DISTRIB-docker"
WORKDIR=$(pwd)

# ########################### #
# Check script compability.   #
# ########################### #
function check_version () {
case "$DISTRIB.$VERSION" in
  centos.[6-7])
    CENTOS_SALTREPO="https://repo.saltstack.com/yum/redhat/salt-repo-latest-2.el$VERSION.noarch.rpm"
    CENTOS_PERCONA="https://repo.percona.com/yum/percona-release-latest.noarch.rpm"
    MNTPATH="/var/www/html/"
    MNTDEST="/var/www/html"
  ;;
  ubuntu.14.04)
    DISTNAME="thrusty"
    UBUNTU_SALTREPO="https://repo.saltstack.com/apt/ubuntu/$VERSION/latest"
    MNTDEST="/var/www/html"
  ;;
  ubuntu.16.04)
    DISTNAME="xenial"
    UBUNTU_SALTREPO="https://repo.saltstack.com/apt/ubuntu/$VERSION/latest"
    MNTDEST="/var/www/html"
  ;;
  ubuntu.18.04)
    DISTNAME="bionic"
    UBUNTU_SALTREPO="https://repo.saltstack.com/apt/ubuntu/$VERSION/latest"
    MNTDEST="/var/www/html"
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
mkdir -p $MNTPATH
cat << EOT >> $WORKDIR/$DKNAME
FROM $DISTRIB:$VERSION
RUN yum install -y yum-utils epel-release createrepo
RUN yum install -y $CENTOS_SALTREPO $CENTOS_PERCONA
RUN rpm --import /etc/pki/rpm-gpg/*
RUN yum -y update
EOT
}

# ############################ #
# Build our centos repository. #
# ############################ #
function centos_repo () {
   REPOID=$1
   DPATH=$2
   docker exec $DKNAME reposync -g -l -d -m --repoid=$REPOID --newest-only --download-metadata --download_path=$DPATH
   docker exec $DKNAME /bin/sh -c 'rm -f $(/usr/bin/repomanage -ock 3 '$MNTDEST/$REPOID')'
   docker exec $DKNAME createrepo -g $MNTDEST/base/comps.xml $MNTDEST/$REPOID
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

# Move to our work directory and check syntax
# and set variables.
cd $WORKDIR
check_version

# Build the docker file for our docker image.
$DISTRIB"_docker"
docker build -t $DKIMAGE -f $DKNAME .
docker run -v $MNTPATH:$MNTDEST --name $DKNAME -t -d $DKIMAGE

# Create our repositorys.
case $DISTRIB in
  ubuntu)
# WIP e.g. insert code here!
  ;;
  centos)
    DPATH="/$MNTDEST/$DISTRIB/$VERSION/"
#    centos_repo base $DPATH
#    centos_repo centosplus $DPATH
#    centos_repo extras $DPATH
#    centos_repo updates $DPATH
#    centos_repo epel $DPATH

    DPATH="/$MNTDEST/$DISTRIB/"
    centos_repo salt-latest $DPATH/salt
    centos_repo percona-release-x86_64 $DPATH/percona
    centos_repo percona-release-noarch $DPATH/percona
  ;;
esac

# Stop the docker.
docker stop $DKNAME

# Clean up dockers and files.
docker system prune -f --all
rm -f $WORKDIR/$DKNAME
