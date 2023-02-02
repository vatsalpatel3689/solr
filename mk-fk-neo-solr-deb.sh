#!/bin/bash -e

export LOCAL_DIR=fk-neo-solr

PACKAGE="fk-neo-solr"
export PACKAGE=$PACKAGE

REPO_SERVICE_HOST="10.24.0.41"
REPO_SERVICE_PORT="8080"
PIPELINE_LABEL=`date +%s`
pwd
ls

echo "Calling make deb script"

function die() {
  echo "Error: $1" >&2
  exit 1
}

[ -z "$LOCAL_DIR" ] && die "No base dir specified"
[ -z "$PACKAGE" ] && die "No package name specified"

SOLR_VERSION="9.1.0"
BUILD_VERSION_NUMBER="$SOLR_VERSION-$PIPELINE_LABEL"

# Create base directories for debian packaging
DEB_DIR="deb"

[ ! -d "$DEB_DIR" ] && mkdir -p "$DEB_DIR"
[ ! -d "$DEB_DIR/usr/share/$PACKAGE/lib" ] && mkdir -p "$DEB_DIR/usr/share/$PACKAGE/lib"
[ ! -d "$DEB_DIR/usr/share/$PACKAGE/nagios" ] && mkdir -p "$DEB_DIR/usr/share/$PACKAGE/nagios"
[ ! -d "$DEB_DIR/usr/share/$PACKAGE/offlinemodels/" ] && mkdir -p "$DEB_DIR/usr/share/$PACKAGE/offlinemodels/"

# PAAS directories
[ ! -d "$DEB_DIR/etc/cron.d" ] && mkdir -p "$DEB_DIR/etc/cron.d"
[ ! -d "$DEB_DIR/etc/default" ] && mkdir -p "$DEB_DIR/etc/default"
[ ! -d "$DEB_DIR/etc/cosmos-jmx" ] && mkdir -p "$DEB_DIR/etc/cosmos-jmx"
[ ! -d "$DEB_DIR/etc/rsyslog.d" ] && mkdir -p "$DEB_DIR/etc/rsyslog.d"
[ ! -d "$DEB_DIR/etc/confd/conf.d" ] && mkdir -p "$DEB_DIR/etc/confd/conf.d"
[ ! -d "$DEB_DIR/etc/confd/templates" ] && mkdir -p "$DEB_DIR/etc/confd/templates"

echo "step --- 2"
pwd
ls

# project directory
PROJECT_DIR="package/$PACKAGE"

echo "Cat Files start"
cat ${PROJECT_DIR}/DEBIAN/control
cat ${PROJECT_DIR}/DEBIAN/postinst
echo "Cat Files end"

# copy DEBIAN files
cp -r ${PROJECT_DIR}/DEBIAN ${DEB_DIR}/DEBIAN

echo "step -- 3"
pwd
ls

echo "step -- 4"
pwd
ls

echo "step -- 5"
pwd
ls -lrth


echo "step -- 6"
pwd
ls -lrth

# Create .tgz file with binaries and copy it to corresponding debian directory.
cp ${PROJECT_DIR}/usr/share/${PACKAGE}/solr-9.1.0-FK-2.tgz deb/usr/share/${PACKAGE}/lib/

# Copy nagios files
cp ${PROJECT_DIR}/usr/share/${PACKAGE}/nagios/* ${DEB_DIR}/usr/share/${PACKAGE}/nagios/

# Copy cron files
cp ${PROJECT_DIR}/etc/cron.d/* ${DEB_DIR}/etc/cron.d/

# Copy cosmos config files
cp ${PROJECT_DIR}/etc/default/cosmos-role ${DEB_DIR}/etc/default/
cp ${PROJECT_DIR}/etc/cosmos-jmx/${PACKAGE}.json ${DEB_DIR}/etc/cosmos-jmx/

# Copy log service config files.
cp ${PROJECT_DIR}/etc/rsyslog.d/40-${PACKAGE}.conf ${DEB_DIR}/etc/rsyslog.d/

# Copy confd related files
cp ${PROJECT_DIR}/etc/confd/conf.d/* ${DEB_DIR}/etc/confd/conf.d/
cp ${PROJECT_DIR}/etc/confd/templates/* ${DEB_DIR}/etc/confd/templates/
cp ${PROJECT_DIR}/offlinemodels/* ${DEB_DIR}/usr/share/${PACKAGE}/offlinemodels/


chmod 755 ${DEB_DIR}/usr/share/${PACKAGE}/offlinemodels/
echo "Updating CONTROL file ..."
sed -i -e "s/_PACKAGE_/${PACKAGE}/"  -i.bak $DEB_DIR/DEBIAN/control
sed -i -e "s/_VERSION_/${BUILD_VERSION_NUMBER}/"  -i.bak $DEB_DIR/DEBIAN/control

echo "control file start"
 cat $DEB_DIR/DEBIAN/control
 echo "control file end"

rm $DEB_DIR/DEBIAN/control.bak

echo "Updating POSTINST file ..."
sed -i -e "s/_PACKAGE_/${PACKAGE}/" -i.bak $DEB_DIR/DEBIAN/postinst
sed -i -e "s/_VERSION_/${BUILD_VERSION_NUMBER}/" -i.bak $DEB_DIR/DEBIAN/postinst
sed -i -e "s/_USER_/${PACKAGE}/" -i.bak $DEB_DIR/DEBIAN/postinst

rm $DEB_DIR/DEBIAN/postinst.bak

chmod 00755 ${DEB_DIR}/DEBIAN/postinst

echo "postinst file"
cat $DEB_DIR/DEBIAN/postinst
echo "postinst file end"

VERSION=${BUILD_VERSION_NUMBER}
ARCH=all

echo "Building deb file ${PACKAGE}_${VERSION}_${ARCH}.deb..."
chmod 00775 $DEB_DIR/*
dpkg-deb -b ${DEB_DIR} ${PACKAGE}_${VERSION}_${ARCH}.deb

echo "Done."
echo "step - 7"
pwd
ls -lrth

echo "Uploading Debian to repo service"
REPO_NAME="fk-neo-solr"
ENV="fk-neo-solr-debian-stretch"
reposervice --host $REPO_SERVICE_HOST --port $REPO_SERVICE_PORT pubrepo --repo ${REPO_NAME} --appkey test --debs ${PACKAGE}_*.deb

echo "JOB DONE !!"

echo "Updating env details"

echo "step - 8"
pwd
ls

rm -rf files
mkdir files

echo "step - 9"
pwd
ls

echo "Executing GET request to get the head version of given package"
curl -X GET -H 'Content-Type: application/json' http://10.24.0.41:8080/repo/$PACKAGE/HEAD?appkey=test > ./files/output.txt
url_with_id=`cat ./files/output.txt | jq '.url'`
id=$(basename $url_with_id)
echo "id is: $id"


repo_ver=`echo $id | tr -d '"'`
echo "head version of $PACKAGE is: $repo_ver"

echo "Executing GET request to get latest env defination"
curl -X GET -H 'Content-Type: application/json' http://10.24.0.41:8080/env/$ENV/HEAD?appkey=test >> ./files/getResponse.json
echo "Latest env defination is: "
cat ./files/getResponse.json

len=`cat ./files/getResponse.json| jq '.repoReferences | length'`
echo "\nNumber of repos defined in env: $len"

function getJsonVal () {
    echo "repo name is: $PACKAGE"
    echo "count is: $len"
    echo "repo ver is: $repo_ver"

for ((i=0;i<$len;i++))
    do
        name=`cat ./files/getResponse.json | jq '.repoReferences['${i}'].repoName'`
        echo "name is: $name"
        if [ $name == \"$PACKAGE\" ]; then
               echo "i is: $i"
               cat ./files/getResponse.json | jq '((select(.repoReferences['${i}'].repoName == "'${PACKAGE}'") | .repoReferences['${i}'].repoVersion) |= '${repo_ver}')' > ./files/new_env.json
               cat ./files/new_env.json | jq '.repoReferences' > ./files/input.json
               echo "Json input using with updated repo version is:"
               cat ./files/input.json
               return
    fi
    done
}
cat ./files/getResponse.json | getJsonVal $PACKAGE $len

cd ./files

echo "Executing PUT request on env with input having updated repo version of the given package"
curl -X PUT -D putReqOutput.txt -H 'Content-Type: application/json' "http://10.24.0.41:8080/env/$ENV?appkey=test" -v -d @input.json &> /tmp/update_env_err.txt

grep -i "HTTP/1.1 404 Not Found" < /tmp/update_env_err.txt
if [ `echo $?` -eq 0 ]
then
    cat /tmp/update_env_err.txt
    echo "Probabale reason for failure is, repo-name's entry is missing in ENV file"
    exit -1;
fi

cd ..

http_code=`grep "HTTP/1.1" ./files/putReqOutput.txt | cut -d " " -f2`
echo "HTTP Status code is $http_code"
if [ $http_code = 201 ]; then
    echo "Successfully updated latest repo environment!!"
else
    echo "PUT Request Failed for enviornment update!!!"
    exit 1

fi
