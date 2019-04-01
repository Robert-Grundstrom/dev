#!/bin/bash
# Variables
DISTRIB=$1                                      # Distribution
VERSION=$2                                      # Version
DKIMAGE=$DISTRIB$VERSION":repo"                 # Docker Image name
DKNAME=$DISTRIB$VERSION"-docker"                # Docker file name
WORKDIR="/opt/os/scripts"                       # Script location
UBUNTU_MNTDIR="/var/spool/apt-mirror/"          # Were Ubuntu downloads its repos
UBUNTU_SALTDIR="/var/spool/ubuntu-salt/"        # Ubuntu Saltstack repo download
CENTOS_MNTDIR="/var/www/html/centos/"           # Were CentOS downloads its repos
HOST_MNTDIR="/opt/os/mirror/"                   # Mount point on the host.

# Salt stack URLs
CENTOS_SALTREPO="https://repo.saltstack.com/yum/redhat/salt-repo-latest-2.el$VERSION.noarch.rpm"
UBUNTU_SALTREPO="https://repo.saltstack.com/apt/ubuntu/18.04/amd64/latest"

# ########################### #
# Check script compability.   #
# ########################### #
function check_comp () {
case "$DISTRIB.$VERSION" in

  centos.[6-7])
    echo "Building $DISTRIB $VERSION."
  ;;

  ubuntu.all)
    echo "Building $DISTRIB $VERSION."
    echo "Using ubuntu-mirror.list config in script folder."
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
   REPOID=$1            # What repository to download.
   DOWNLOAD_DIR=$2      # Download path for the docker.

   # Tell docker image to download the repository.
   docker exec $DKNAME reposync -g -l -d -m --repoid=$REPOID --newest-only --download-metadata --download_path=$DOWNLOAD_DIR
   echo ""

   # Clean up of old packets if needed.
   docker exec $DKNAME /bin/sh -c 'rm -f $(/usr/bin/repomanage -ock 5 '$DOWNLOAD_DIR/$REPOID') 2>&1 /dev/null'

   # Build the repository
   touch $DOWNLOAD_DIR/$REPOID/comps.xml
   docker exec $DKNAME createrepo -g comps.xml $DOWNLOAD_DIR/$REPOID
}


# ############################## #
# Create docker file for Ubuntu. #
# ############################## #
function ubuntu_docker () {
cat << EOT > $WORKDIR/$DKNAME
FROM ubuntu:18.04
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
  docker run -v $HOST_MNTDIR/ubuntu:$UBUNTU_MNTDIR -v $HOST_MNTDIR/ubuntu-salt/:$UBUNTU_SALTDIR --name $DKNAME -t -d $DKIMAGE
  docker exec $DKNAME apt-mirror
  take_time

  SECONDS=0
  echo "# ########################### #"
  echo "# Fetching Saltstack repos... #"
  echo "# ########################### #"
  URL="https://repo.saltstack.com/apt/ubuntu"

  # Download Saltstack repository. Broken down to increase download speed.
  docker exec -d $DKNAME /bin/sh -c 'nohup wget -P '$UBUNTU_SALTDIR'12.04/ -m -N -nH --cut-dirs=3 -np -R "index.*" '$URL'/12.04/ &'
  docker exec -d $DKNAME /bin/sh -c 'nohup wget -P '$UBUNTU_SALTDIR'14.04/ -m -N -nH --cut-dirs=3 -np -R "index.*" '$URL'/14.04/ &'
  docker exec -d $DKNAME /bin/sh -c 'nohup wget -P '$UBUNTU_SALTDIR'16.04/ -m -N -nH --cut-dirs=3 -np -R "index.*" '$URL'/16.04/ &'
  docker exec -d $DKNAME /bin/sh -c 'nohup wget -P '$UBUNTU_SALTDIR'18.04/ -m -N -nH --cut-dirs=3 -np -R "index.*" '$URL'/18.04/ &'

  docker exec -d $DKNAME /bin/sh -c 'nohup /var/spool/apt-mirror/var/clean.sh'  # Cleaning up Ubuntu repository.
  docker exec $DKNAME /bin/sh -c 'wait'                                         # Wait until all wget commands have finished.
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
  find $HOST_MNTDIR -type d -print0 | xargs -0 chmod 655        # Set mode 655 for all directorys.
  find $HOST_MNTDIR -type f -print0 | xargs -0 chmod 644        # Set mode 644 for all files.
  chown -R root: /opt/os/mirror/*                               # Set user as root and group as root.
  docker stop $DKNAME                                           # Stop the docker image
  docker system prune -f --all                                  # Cleanup all docker images
  rm -f $WORKDIR/$DKNAME                                        # Remove the docker file.
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
    ubuntu_docker       # Build our docker file.
    build_docker        # Build our docker image.
    ubuntu_repo         # Download Ubuntu repository and Saltstack repository.
  ;;

  centos)
    centos_docker       # Build our docker file.
    build_docker        # Build our docker image.
    docker run -v $HOST_MNTDIR/centos/:$CENTOS_MNTDIR --name $DKNAME -t -d $DKIMAGE     # Run our docker and mount filesystems.
    DOWNLOAD_DIR=$CENTOS_MNTDIR$VERSION                                         # Set download directory

    # Download base packages
    centos_repo base $DOWNLOAD_DIR              # Download base repository.
    centos_repo centosplus $DOWNLOAD_DIR        # Download centosplus repository.
    centos_repo extras $DOWNLOAD_DIR            # Download extras repository.
    centos_repo updates $DOWNLOAD_DIR           # Download updates repository.
    centos_repo epel $DOWNLOAD_DIR              # Download epel repository.
    centos_repo salt-latest $DOWNLOAD_DIR       # Download Saltstack repository.

    # Copy GPG keys for the repositorys.
    docker exec $DKNAME /bin/sh -c 'mkdir -p '$DOWNLOAD_DIR'/GPG-keys/'
    docker exec $DKNAME /bin/sh -c 'rsync -avp /etc/pki/rpm-gpg/* '$DOWNLOAD_DIR'/GPG-keys/'
  ;;
esac

# Clean up dockers and files.
do_cleanup
