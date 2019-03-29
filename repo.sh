DISTRIB=$1
VERSION=$2
DKIMAGE="$DISTRIB:repo"
DKNAME="'$DISTRIB''$VERSION'-docker"
WORKDIR="/opt/os/scripts"

# ########################### #
# Check script compability.   #
# ########################### #
function check_comp () {
case "$DISTRIB.$VERSION" in
  centos.[6-7])
    CENTOS_SALTREPO="https://repo.saltstack.com/yum/redhat/salt-repo-latest-2.el$VERSION.noarch.rpm"
    CENTOS_PERCONA="https://repo.percona.com/yum/percona-release-latest.noarch.rpm"
    MNTPATH="/opt/os/mirror/"
    MNTDEST="/var/www/html"
  ;;

  ubuntu.all)
    DISTNAME="bionic"
    VERSION="18.04"
    UBUNTU_SALTREPO="https://repo.saltstack.com/apt/ubuntu/18.04/amd64/latest"
    MNTDEST="/var/spool/apt-mirror"
    MNTPATH="/opt/os/mirror/ubuntu"
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
RUN yum install -y yum-utils rsync epel-release createrepo $CENTOS_SALTREPO $CENTOS_PERCONA \
&& rpm --import /etc/pki/rpm-gpg/* && yum clean all && yum -y update
EOT
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
RUN apt -y update && apt -y install apt-utils apt-mirror gnupg wget vim && apt -y upgrade
ADD $UBUNTU_SALTREPO/SALTSTACK-GPG-KEY.pub /tmp/SALTSTACK-GPG-KEY.pub
RUN apt-key add /tmp/SALTSTACK-GPG-KEY.pub
COPY $WORKDIR/ubuntu-mirror.list /etc/apt/mirror.list
EOT
}


# ############################## #
# Timer function.                #
# ############################## #
function take_time  () {
if (( $SECONDS > 3600 )) ; then
    let "hours=SECONDS/3600"
    let "minutes=(SECONDS%3600)/60"
    let "seconds=(SECONDS%3600)%60"
    echo "Completed in $hours hour(s), $minutes minute(s) and $seconds second(s)"
elif (( $SECONDS > 60 )) ; then
    let "minutes=(SECONDS%3600)/60"
    let "seconds=(SECONDS%3600)%60"
    echo "Completed in $minutes minute(s) and $seconds second(s)"
else
    echo "Completed in $SECONDS seconds"
fi
}


# ################### #
# Script starts here. #
# ################### #
cd $WORKDIR
check_comp
$DISTRIB"_docker"

docker build -t $DKIMAGE -f $DKNAME .
docker run -v $MNTPATH:$MNTDEST --name $DKNAME -t -d $DKIMAGE

# Create our repositorys.
case $DISTRIB in

  ubuntu)
    SECONDS=0
    docker exec $DKNAME apt-mirror
    take_time
  ;;

  centos)
    SECONDS=0
    DPATH="/var/www/html/centos/$VERSION"
    mkdir -p $DPATH

    # Download base packages
    centos_repo base $DPATH
    centos_repo centosplus $DPATH
    centos_repo extras $DPATH
    centos_repo updates $DPATH
    centos_repo epel $DPATH

    # Download percona repo
#    centos_repo percona-release-noarch $DPATH
#    centos_repo percona-release-x86_64 $DPATH

    # Download salt-stack repo.
    centos_repo salt-latest $DPATH

    # Copy GPG keys for the repositorys.
    docker exec $DKNAME /bin/sh -c 'mkdir -p '$DPATH'/GPG-keys/'
    docker exec $DKNAME /bin/sh -c 'rsync -avp /etc/pki/rpm-gpg/* '$DPATH'/GPG-keys/'
    take_time
  ;;
esac

# Clean up dockers and files.
docker stop $DKNAME
docker system prune -f --all
rm -f $WORKDIR/$DKNAME
