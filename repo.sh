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
echo "FROM $DISTRIB:$VERSION" > $WORKDIR/$DKNAME
echo "" >> $WORKDIR/$DKNAME
echo "RUN yum install -y yum-utils epel-release createrepo" >> $WORKDIR/$DKNAME
echo "RUN yum install -y $SALTREPO" >> $WORKDIR/$DKNAME
echo "RUN rpm --import /etc/pki/rpm-gpg/*" >> $WORKDIR/$DKNAME
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
echo "FROM $DISTRIB:$VERSION" > $WORKDIR/$DKNAME
echo "" >> $WORKDIR/$DKNAME
echo "ADD $UBUNTU_SALTREPO/SALTSTACK-GPG-KEY.pub /tmp/SALTSTACK-GPG-KEY.pub" >> $WORKDIR/$DKNAME
echo "RUN sudo apt-key add /tmp/SALTSTACK-GPG-KEY.pub" >> $WORKDIR/$DKNAME

case $VERSION in
14.04)
  echo 'RUN echo "deb '$UBUNTU_SALTREPO' thrusty main" > /etc/apt/source.list.d/saltstack-latest' >> $WORKDIR/$DKNAME
  ;;
16.04)
  echo 'RUN echo "deb '$UBUNTU_SALTREPO' xenial main" > /etc/apt/source.list.d/saltstack-latest' >> $WORKDIR/$DKNAME
  ;;
18.04)
  echo 'RUN echo "deb '$UBUNTU_SALTREPO' bionic main" > /etc/apt/source.list.d/saltstack-latest' >> $WORKDIR/$DKNAME
  ;;
*)
  echo "Warning unknown version!"
  exit 1
  ;;
esac

echo "RUN apt update" >> $WORKDIR/$DKNAME
echo "RUN apt -y intstall apt-mirror" >> $WORKDIR/$DKNAME
echo "RUN apt -y upgrade" >> $WORKDIR/$DKNAME
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
  exit 1
  ;;
esac

# Stop the docker.
docker stop $DKNAME

# Clean up dockers and files.
docker system prune -f --all
rm -f $WORKDIR/$DKNAME
