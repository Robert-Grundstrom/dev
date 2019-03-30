DISTRIB=$1
VERSION=$2
DKIMAGE=$DISTRIB$VERSION":repo"
DKNAME=$DISTRIB$VERSION"-docker"
WORKDIR="/opt/os/scripts"


# ########################### #
# Check script compability.   #
# ########################### #
function check_comp () {
case "$DISTRIB.$VERSION" in

  centos.[6-7])
    CENTOS_SALTREPO="https://repo.saltstack.com/yum/redhat/salt-repo-latest-2.el$VERSION.noarch.rpm"
    MNTPATH="/opt/os/mirror/"
    MNTDEST="/var/www/html"
  ;;

  ubuntu.all)
    DISTNAME="bionic"
    VERSION="18.04"
    UBUNTU_SALTREPO="https://repo.saltstack.com/apt/ubuntu/18.04/amd64/latest"
    MNTDEST="/var/spool"
    MNTPATH="/opt/os/mirror"
  ;;

  *)
cat << EOF
Warning unknown distribution or version!
Supported distributions and versions for
this script is:
- ubuntu all
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
cat << EOT > $WORKDIR/$DKNAME
FROM $DISTRIB:$VERSION
RUN yum install -y yum-utils rsync epel-release createrepo $CENTOS_SALTREPO
RUN rpm --import /etc/pki/rpm-gpg/*
RUN yum clean all && yum -y update
EOT
}


# ################### #
# Build docker image. #
# ################### #
function build_docker () {
  SECONDS=0
  echo -n "Building docker image..."
  docker build -q -t $DKIMAGE -f $DKNAME .
  take_time
}


# ############################ #
# Build our centos repository. #
# ############################ #
function centos_repo () {
   REPOID=$1
   DPATH=$2
   docker exec $DKNAME reposync -g -l -d -m --repoid=$REPOID --newest-only --download-metadata --download_path=$DPATH
   echo ""
   docker exec $DKNAME /bin/sh -c 'rm -f $(/usr/bin/repomanage -ock 5 '$DPATH/$REPOID') 2>&1 /dev/null'
   touch $DPATH/$REPOID/comps.xml
   docker exec $DKNAME createrepo -g comps.xml $DPATH/$REPOID
}


# ############################## #
# Create docker file for Ubuntu. #
# ############################## #
function ubuntu_docker () {
cat << EOT > $WORKDIR/$DKNAME
FROM $DISTRIB:$VERSION
RUN apt -y update && apt -y install apt-utils apt-mirror gnupg wget && apt -y upgrade
RUN mkdir -p $MNTDEST/apt-mirror $MNTDEST/salt-latest
ADD $UBUNTU_SALTREPO/SALTSTACK-GPG-KEY.pub /tmp/SALTSTACK-GPG-KEY.pub
RUN apt-key add /tmp/SALTSTACK-GPG-KEY.pub
COPY ./ubuntu-mirror.list /etc/apt/mirror.list
EOT
}


# ############################## #
# Create salt-stack repo Ubuntu. #
# ############################## #
function ubuntu_repo () {
  SECONDS=0
  echo "# ######################## #"
  echo "# Fetching Ubuntu repos... #"
  echo "# ######################## #"
  docker run -v $MNTPATH/ubuntu:$MNTDEST/apt-mirror -v $MNTPATH/ubuntu-salt:$MNTDEST/ubuntu-salt --name $DKNAME -t -d $DKIMAGE
  docker exec $DKNAME apt-mirror
  take_time

  SECONDS=0
  echo "# ########################### #"
  echo "# Fetching Saltstack repos... #"
  echo "# ########################### #"
  URL="https://repo.saltstack.com/apt/ubuntu"
  SALTMNT=$MNTDEST"/ubuntu-salt"
  docker exec -d $DKNAME /bin/sh -c 'nohup wget -P '$SALTMNT'/12.04/ -m -N -nH --cut-dirs=3 -np -R "index.*" '$URL'/12.04/ &'
  docker exec -d $DKNAME /bin/sh -c 'nohup wget -P '$SALTMNT'/14.04/ -m -N -nH --cut-dirs=3 -np -R "index.*" '$URL'/14.04/ &'
  docker exec -d $DKNAME /bin/sh -c 'nohup wget -P '$SALTMNT'/16.04/ -m -N -nH --cut-dirs=3 -np -R "index.*" '$URL'/16.04/ &'
  docker exec -d $DKNAME /bin/sh -c 'nohup wget -P '$SALTMNT'/18.04/ -m -N -nH --cut-dirs=3 -np -R "index.*" '$URL'/18.04/ &'
  docker exec -d $DKNAME /bin/sh -c 'nohup /var/spool/apt-mirror/var/clean.sh'
  docker exec $DKNAME /bin/sh -c 'wait'
  take_time
}


# ############################## #
# Timer function.                #
# ############################## #
function take_time  () {
if (( $SECONDS > 3600 )) ; then
    let "hours=SECONDS/3600"
    let "minutes=(SECONDS%3600)/60"
    let "seconds=(SECONDS%3600)%60"
    echo -e "Completed in $hours hour(s), $minutes minute(s) and $seconds second(s)\n\n\n"
elif (( $SECONDS > 60 )) ; then
    let "minutes=(SECONDS%3600)/60"
    let "seconds=(SECONDS%3600)%60"
    echo -e "Completed in $minutes minute(s) and $seconds second(s)\n\n\n"
else
    echo -e "Completed in $SECONDS seconds\n\n\n"
fi
}


# ######### #
# Clean up. #
# ######### #
function do_cleanup () {
  SECONDS=0
  echo "# ################################## #"
  echo "# Setting user and file permissions. #"
  echo "# ################################## #"
  find /opt/os/mirror/ -type d -print0 | xargs -0 chmod 655
  find /opt/os/mirror/ -type f -print0 | xargs -0 chmod 644
  chown -R root: /opt/os/mirror/*
  docker stop $DKNAME
  docker system prune -f --all
  rm -f $WORKDIR/$DKNAME
  take_time
}


# ################### #
# Script starts here. #
# ################### #
cd $WORKDIR
check_comp

# Create our repositorys.
case $DISTRIB in

  ubuntu)
    ubuntu_docker
    build_docker
    ubuntu_repo
  ;;

  centos)
    centos_docker
    build_docker
    SECONDS=0
    docker run -v $MNTPATH:$MNTDEST --name $DKNAME -t -d $DKIMAGE
    DPATH="/var/www/html/centos/$VERSION"
    mkdir -p $DPATH

    # Download base packages
    centos_repo base $DPATH
    centos_repo centosplus $DPATH
    centos_repo extras $DPATH
    centos_repo updates $DPATH
    centos_repo epel $DPATH

    # Download salt-stack repo.
    centos_repo salt-latest $DPATH

    # Copy GPG keys for the repositorys.
    docker exec $DKNAME /bin/sh -c 'mkdir -p '$DPATH'/GPG-keys/'
    docker exec $DKNAME /bin/sh -c 'rsync -avp /etc/pki/rpm-gpg/* '$DPATH'/GPG-keys/'
    take_time
  ;;
esac

# Clean up dockers and files.
do_cleanup
