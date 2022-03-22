#!/usr/bin/env bash
umask 0022
#LOGFILE GENERATOR
remove_old_log()
{

LOG=/var/log/$(basename -- "$0" .sh ).log
if [  -e "$LOG" ] ; then
         rm -rf $LOG
fi

}
write_log()
{
  while read text
  do
LOGTIME=`date "+%Y-%m-%d %H:%M:%S"`
LOG=/var/log/$(basename -- "$0" .sh ).log
if [ ! -e "$LOG" ] ; then
         touch $LOG
         chmod 744 $LOG
fi
     echo $LOGTIME": $text" | tee -a $LOG;

  done


}
#DEPENDENCY CHECKS
##################################
dependency_check_rpm()
{
if ! [ -x "$(command -v unzip)" ]; then
echo "Unzip not installed"
yum install unzip wget curl -y
echo "Installing Unzip"
else
echo "Unzip Installed"
fi
if ! [ -x "$(command -v rsync)" ]; then
echo "Rsync not installed"
yum install rsync -y
echo "Installing Rsync"
else
echo "Rsync Installed"
fi
if ! [ -x "$(command -v java)" ]; then
echo "Java not installed"
yum install java-1.8.0-openjdk -y
echo "Installing Java"
else
echo "Java Installed"
fi
}

dependency_check_deb()
{
if ! [ -x "$(command -v unzip)" ]; then
echo "Unzip not installed"
apt-get install unzip wget curl -y
echo "Installing Unzip"
else
echo "Unzip Installed"
fi

if ! [ -x "$(command -v java)" ]; then
echo "Java not installed"
sudo apt-get install software-properties-common  -y
sudo apt-get update -y
sudo apt-get install openjdk-8-jre -y
echo "Installing Java"
else
version=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
echo version "$version"
if [[ "$version" > "1.7" ]]; then
    echo  "Java version OK"  >> /var/log/solr_installer.log 2>&1
else
    echo  "Java version is less than 1.7. Please upgrade you JRE version."  >> /var/log/solr_installer.log  2>&1
    exit 0
fi
fi
}
#FILECLOUD SERVICE RESTART
##################################
restart_services()
{
if [[ -n "$(command -v yum)" ]]; then
echo "Restarting Services..." 2>&1 | write_log
cd
  service httpd restart 3> /dev/null
	service httpd status 2>&1 | write_log
	service fcorchestrator restart 3> /dev/null
	service fcorchestrator status 2>&1 | write_log
	if ! [ -x "$(command -v mongo)" ]; then
  echo 'MongoDB is not installed.' 2>&1 | write_log > /dev/null
  else
	service mongod restart 3> /dev/null
	service mongod status 2>&1 | write_log
  fi
	service crond restart 3> /dev/null
	service crond status 2>&1 | write_log
	service fcdocconverter restart 2>&1 | write_log
	service fcdocconverter status 2>&1 | write_log
fi

if [[ -n "$(command -v apt-get)" ]]; then
echo "Restarting Services..." 2>&1 | write_log
    cd
    service apache2 restart 3> /dev/null
		service apache2 status 2>&1 | write_log
		service fcorchestrator restart 3> /dev/null
		service fcorchestrator status 2>&1 | write_log
	  if ! [ -x "$(command -v mongo)" ]; then
    echo 'MongoDB is not installed.' 2>&1 | write_log > /dev/null
    else
	  service mongod restart 3> /dev/null
	  service mongod status 2>&1 | write_log
    fi
		service cron restart 3> /dev/null
		service cron status 2>&1 | write_log
		service fcdocconverter restart 2>&1 | write_log
		service fcdocconverter status 2>&1 | write_log
fi
}
#FILECLOUD DATABASE VERSION UPGRADE FUNCTION
##################################
update_clouddb()
{
wget --no-check-certificate http://127.0.0.1/install/update.php?mode=db 2>&1 | write_log
rm -rf update.php\?mode\=db
}

#FILECLOUD UPGRADE URLS
##################################
FC_INSTALL_DIR=/opt/app/configure/fcinstall
RPM_INSTALLER_URL="https://patch.codelathe.com/tonidocloud/live/installer/file_cloud_rpm.tgz"
DEB_INSTALLER_URL="https://patch.codelathe.com/tonidocloud/live/installer/file_cloud_deb.tgz"


#FILECLOUDCP FUNCTION
##################################
binary_file()
{
BINARY_URL="http://patch.codelathe.com/tonidocloud/live/installer/filecloudcp"
sudo curl --location $BINARY_URL -o /usr/bin/filecloudcp > /dev/null
sudo chmod 744 /usr/bin/filecloudcp
}

fwserule()
{
if ! [ -x "$(command -v semanage)" ]; then
yum install policycoreutils-python -y
fi
semanage fcontext -a -t httpd_sys_rw_content_t /opt/fileclouddata.*  2>&1  | write_log
semanage fcontext -a -t httpd_sys_rw_content_t /var/www/html.*  2>&1  | write_log
restorecon -Rv /var/www/html  2>&1  | write_log
setsebool -P httpd_can_network_connect_db 1  2>&1  | write_log
setsebool -P httpd_can_network_connect 1  2>&1  | write_log
setsebool -P httpd_builtin_scripting 1  2>&1  | write_log
setsebool -P httpd_can_network_connect_db 1  2>&1  | write_log
setsebool -P httpd_can_network_connect 1  2>&1  | write_log
setsebool -P httpd_builtin_scripting 1  2>&1  | write_log # Enabled by default
setsebool -P httpd_execmem 1  2>&1  | write_log
setsebool -P httpd_use_nfs 1  2>&1  | write_log

if ! [ -x "$(command -v firewall-cmd)" ]; then
iptables -A INPUT -p tcp -m tcp --dport 80 -j ACCEPT  2>&1  | write_log
iptables -A INPUT -p tcp -m tcp --dport 443 -j ACCEPT  2>&1  | write_log
iptables-save
else
firewall-cmd --add-service=http --zone=public --permanent  # Use only if HTTPS not enabled : This enables access on unsecure HTTP port 80
firewall-cmd --add-service=https --zone=public --permanent
firewall-cmd --reload

fi
}

fc_package_verification()
{

if [ -n "$(command -v apt)" ]; then

echo "Downloading the verification XML file" | write_log
wget -O $FC_INSTALL_DIR/tmp/cloudinstall/file_cloud_deb.xml https://patch.codelathe.com/tonidocloud/live/installer/file_cloud_deb.xml | write_log
cat > $FC_INSTALL_DIR/tmp/cloudinstall/packagevalidator.php << \EOF
<?php
/**
 * Copyright (c) 2021 CodeLathe. All rights Reserved.
 * This file is part of FileCloud  http://www.getfilecloud.com
 */

/**
 * @param $msg
 */
function console($msg)
{
    echo "$msg" . PHP_EOL;
}

/**
 * @param $signatureIndex
 * @return string
 */
function getVerificationPublicKey($signatureIndex): string
{
    $key = '';
    if ($signatureIndex == 1) {
        $key = <<<EOD
-----BEGIN PUBLIC KEY-----
MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA1ongl9H+iSf5EtH5eHD5
/kJhQ5nbG1qABCAaSFiEsVkrt/rjhRlekFvLoO+3AOuGxWvxXZrVCMRM0iYcGBoX
01bw/AxOMbzC2Z4vLRZqJVQ8BOJNbxcGozUZETsRMOtnAGguWCbriI+Pkhk8TeJ8
ZOlWcXBKU2ksGh03sApX6B6fSj7roBejTDq17k5aehQEkLrn2WK4Iopl/kd3npzu
5Cgb7U5Z33WTrSAdbZrgKwZvtGswMXow6duInW/yie1hLXJpvI4zAn8j0vq7OQS+
BvQ0ksm3CMaeg7PaegRxT2hoMTLZxeCCvcwPIZaQjDjxTSOnZLB2dRG98xb8BM2v
vW/riUgO3SH4BFI9a8u80cYUTPvzlb4fgq6caIrwz8WaThwWi8AZPGag+/2m3yE9
K49uFF6EaB035M+5MSTEQThjGYLHC6ejOBhXW1qCEyYgyQ57ijz8t+OiLLnt53l+
jNA8bOrPShrxwDwDL4FkRG60iFU54kj3WMb+CqooTipyrxioCexOqPbBPxar/ct2
jsEcZJ1hU0zep/JFQBudJ0qQU9yvO6ZAUt81gCsw+4ezvC2xOfKh8s94g44o1Aul
xyYPhE2qGV4lWYPh3dxhn6BlAuIXM6Mn+7pssmWAvT8DRZUeiy7hRhZ/w5f1dHNv
HfdgGbhtpvx8BgQBuvFfKtMCAwEAAQ==
-----END PUBLIC KEY-----
EOD;
    }
    return $key;
}

/**
 * @param string $verificationXml
 * @param string $zipFile
 */
function validate(string $verificationXml, string $zipFile)
{
    $result = [];
    $cloudXml = simplexml_load_file($verificationXml);
    $verificationData = $cloudXml->VerificationData;
    $signatureIndex = $cloudXml->SignatureData->SignatureIndex;
    $signatureValue = $cloudXml->SignatureData->SignatureValue;
    $checksum = $cloudXml->VerificationData->CheckSum;
    $fileSize = $cloudXml->VerificationData->FileSize;
    if ($signatureIndex == 0) {
        console("Unsupported verification file");
        exit(1);
    }

    $verificationPublicKey = getVerificationPublicKey($signatureIndex);
    $base64DecodedSignature = base64_decode($signatureValue);
    $ok = openssl_verify(
        $verificationData->asXML(),
        $base64DecodedSignature,
        $verificationPublicKey,
        OPENSSL_ALGO_SHA1
    );
    if ($ok != 1) {
        console("Invalid verification file");
        exit(1);
    }

    $downloadedFileCheckSum = sha1_file($zipFile);
    $downloadedFileSize = filesize($zipFile);
    if ($checksum != $downloadedFileCheckSum || $fileSize != $downloadedFileSize) {
        console("Downloaded package is corrupted");
        exit(1);
    }
    console("Package validated successfully.");
    exit(0);
}

if (php_sapi_name() == 'cli') {
    $longopts = [
        'package:', //path to package to be verified
        'signaturexml:', //path to xml file with signature
    ];
    $options = getopt('', $longopts);

    if(!isset($options['package'])){
        console("Missing path to the package that needs be signed. Use --package option to specify path");
        exit(1);
    }

    if(!isset($options['signaturexml'])){
        console("Missing path to the xml containing package signature. Use --signaturexml option to specify path");
        exit(1);
    }

    //get the package path
    $packagepath = $options['package'];
    if(!file_exists($packagepath)){
        console("Package not accessible: $packagepath");
        exit(1);
    }

    //get the package path
    $signaturexml = $options['signaturexml'];
    if(!file_exists($signaturexml)){
        console("Signature XML not accessible: $signaturexml");
        exit(1);
    }


    //verify it
    validate($signaturexml, $packagepath);

}
EOF

/usr/bin/php -f $FC_INSTALL_DIR/tmp/cloudinstall/packagevalidator.php --package $FC_INSTALL_DIR/tmp/cloudinstall/file_cloud_deb.tgz --signaturexml  $FC_INSTALL_DIR/tmp/cloudinstall/file_cloud_deb.xml  | write_log

if [ $? -eq 0 ] ; then
echo "Package validated successfully,Continuing Installation"  | write_log
else
echo "Filecloud Package Validation Failed, Please contact support team at support@codelathe.com"  | write_log
exit 0
fi

fi

if [ -n "$(command -v yum)" ]; then

echo "Downloading the verification XML file" | write_log
wget -O $FC_INSTALL_DIR/tmp/cloudinstall/file_cloud_rpm.xml https://patch.codelathe.com/tonidocloud/1ive/installer/file_cloud_rpm.xml | write_log
cat > $FC_INSTALL_DIR/tmp/cloudinstall/packagevalidator.php << \EOF
<?php
/**
 * Copyright (c) 2021 CodeLathe. All rights Reserved.
 * This file is part of FileCloud  http://www.getfilecloud.com
 */

/**
 * @param $msg
 */
function console($msg)
{
    echo "$msg" . PHP_EOL;
}

/**
 * @param $signatureIndex
 * @return string
 */
function getVerificationPublicKey($signatureIndex): string
{
    $key = '';
    if ($signatureIndex == 1) {
        $key = <<<EOD
-----BEGIN PUBLIC KEY-----
MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA1ongl9H+iSf5EtH5eHD5
/kJhQ5nbG1qABCAaSFiEsVkrt/rjhRlekFvLoO+3AOuGxWvxXZrVCMRM0iYcGBoX
01bw/AxOMbzC2Z4vLRZqJVQ8BOJNbxcGozUZETsRMOtnAGguWCbriI+Pkhk8TeJ8
ZOlWcXBKU2ksGh03sApX6B6fSj7roBejTDq17k5aehQEkLrn2WK4Iopl/kd3npzu
5Cgb7U5Z33WTrSAdbZrgKwZvtGswMXow6duInW/yie1hLXJpvI4zAn8j0vq7OQS+
BvQ0ksm3CMaeg7PaegRxT2hoMTLZxeCCvcwPIZaQjDjxTSOnZLB2dRG98xb8BM2v
vW/riUgO3SH4BFI9a8u80cYUTPvzlb4fgq6caIrwz8WaThwWi8AZPGag+/2m3yE9
K49uFF6EaB035M+5MSTEQThjGYLHC6ejOBhXW1qCEyYgyQ57ijz8t+OiLLnt53l+
jNA8bOrPShrxwDwDL4FkRG60iFU54kj3WMb+CqooTipyrxioCexOqPbBPxar/ct2
jsEcZJ1hU0zep/JFQBudJ0qQU9yvO6ZAUt81gCsw+4ezvC2xOfKh8s94g44o1Aul
xyYPhE2qGV4lWYPh3dxhn6BlAuIXM6Mn+7pssmWAvT8DRZUeiy7hRhZ/w5f1dHNv
HfdgGbhtpvx8BgQBuvFfKtMCAwEAAQ==
-----END PUBLIC KEY-----
EOD;
    }
    return $key;
}

/**
 * @param string $verificationXml
 * @param string $zipFile
 */
function validate(string $verificationXml, string $zipFile)
{
    $result = [];
    $cloudXml = simplexml_load_file($verificationXml);
    $verificationData = $cloudXml->VerificationData;
    $signatureIndex = $cloudXml->SignatureData->SignatureIndex;
    $signatureValue = $cloudXml->SignatureData->SignatureValue;
    $checksum = $cloudXml->VerificationData->CheckSum;
    $fileSize = $cloudXml->VerificationData->FileSize;
    if ($signatureIndex == 0) {
        console("Unsupported verification file");
        exit(1);
    }

    $verificationPublicKey = getVerificationPublicKey($signatureIndex);
    $base64DecodedSignature = base64_decode($signatureValue);
    $ok = openssl_verify(
        $verificationData->asXML(),
        $base64DecodedSignature,
        $verificationPublicKey,
        OPENSSL_ALGO_SHA1
    );
    if ($ok != 1) {
        console("Invalid verification file");
        exit(1);
    }

    $downloadedFileCheckSum = sha1_file($zipFile);
    $downloadedFileSize = filesize($zipFile);
    if ($checksum != $downloadedFileCheckSum || $fileSize != $downloadedFileSize) {
        console("Downloaded package is corrupted");
        exit(1);
    }
    console("Package validated successfully.");
    exit(0);
}

if (php_sapi_name() == 'cli') {
    $longopts = [
        'package:', //path to package to be verified
        'signaturexml:', //path to xml file with signature
    ];
    $options = getopt('', $longopts);

    if(!isset($options['package'])){
        console("Missing path to the package that needs be signed. Use --package option to specify path");
        exit(1);
    }

    if(!isset($options['signaturexml'])){
        console("Missing path to the xml containing package signature. Use --signaturexml option to specify path");
        exit(1);
    }

    //get the package path
    $packagepath = $options['package'];
    if(!file_exists($packagepath)){
        console("Package not accessible: $packagepath");
        exit(1);
    }

    //get the package path
    $signaturexml = $options['signaturexml'];
    if(!file_exists($signaturexml)){
        console("Signature XML not accessible: $signaturexml");
        exit(1);
    }


    //verify it
    validate($signaturexml, $packagepath);

}
EOF

/usr/bin/php -f $FC_INSTALL_DIR/tmp/cloudinstall/packagevalidator.php --package $FC_INSTALL_DIR/tmp/cloudinstall/file_cloud_rpm.tgz --signaturexml  $FC_INSTALL_DIR/tmp/cloudinstall/file_cloud_rpm.xml  | write_log

if [ $? -eq 0 ] ; then
echo "Package validated successfully,Continuing Installation"  | write_log
else
echo "Filecloud Package Validation Failed, Please contact support team at support@codelathe.com"  | write_log
exit 0
fi

fi

}
###################################################################################################################
###############################################FILECLOUD SOLR INSTALLER############################################
###################################################################################################################


solr_installer()
{

echo -e ""
echo -e "###############################"
echo -e "### INSTALLING SOLR         ###"
echo -e "###############################"

if [ -n "$(command -v yum)" ]; then
 dependency_check_rpm
fi
if [ -n "$(command -v apt-get)" ]; then
 dependency_check_deb
fi

sudo mkdir -p $FC_UPGRADE_PATH/tmp/solrinstall 2>&1 | write_log

SOLR_URL="https://patch.codelathe.com/tonidocloud/live/3rdparty/solr/solr-8.8.2.tgz"


SOLR_DOWNLOAD_DIR=$FC_UPGRADE_PATH/tmp/solrinstall
 {
    for ((i = 0 ; i <= 100 ; i+=50)); do
        sleep 1
        echo $i
    done
} | whiptail --gauge "Setting up FileCloud Solr Installer" 7 60 0

echo  "Downloading Solr zip"
cd ${SOLR_DOWNLOAD_DIR}
  {
sudo wget -N "$SOLR_URL"  2>&1 | \
 stdbuf -o0 awk '/[.] +[0-9][0-9]?[0-9]?%/ { print substr($0,63,3) }'
} | whiptail --gauge "Downloading Latest Solr " 7 60 0

echo  "Downloaded Solr zip"
tar -xzvf solr-8.8.2.tgz solr-8.8.2/bin/install_solr_service.sh 2>&1
sudo cp solr-8.8.2/bin/install_solr_service.sh $FC_UPGRADE_PATH/tmp/solrinstall/ 2>&1

sudo bash ./install_solr_service.sh $FC_UPGRADE_PATH/tmp/solrinstall/solr-8.8.2.tgz -d /opt/solrfcdata/var/solr 2>&1

service solr stop
mv /opt/solr-8.8.2/server/etc/jetty-http.xml /opt/solr-8.8.2/server/etc/jetty-http.xml_old 2>&1
cat >/opt/solr-8.8.2/server/etc/jetty-http.xml<<'EOF'
<?xml version="1.0"?>
<!DOCTYPE Configure PUBLIC "-//Jetty//Configure//EN" "http://www.eclipse.org/jetty/configure_9_0.dtd">

<!-- ============================================================= -->
<!-- Configure the Jetty Server instance with an ID "Server"       -->
<!-- by adding a HTTP connector.                                   -->
<!-- This configuration must be used in conjunction with jetty.xml -->
<!-- ============================================================= -->
<Configure id="Server" class="org.eclipse.jetty.server.Server">

  <!-- =========================================================== -->
  <!-- Add a HTTP Connector.                                       -->
  <!-- Configure an o.e.j.server.ServerConnector with a single     -->
  <!-- HttpConnectionFactory instance using the common httpConfig  -->
  <!-- instance defined in jetty.xml                               -->
  <!--                                                             -->
  <!-- Consult the javadoc of o.e.j.server.ServerConnector and     -->
  <!-- o.e.j.server.HttpConnectionFactory for all configuration    -->
  <!-- that may be set here.                                       -->
  <!-- =========================================================== -->
  <Call name="addConnector">
    <Arg>
      <New class="org.eclipse.jetty.server.ServerConnector">
        <Arg name="server"><Ref refid="Server" /></Arg>
        <Arg name="acceptors" type="int"><Property name="solr.jetty.http.acceptors" default="-1"/></Arg>
        <Arg name="selectors" type="int"><Property name="solr.jetty.http.selectors" default="-1"/></Arg>
        <Arg name="factories">
          <Array type="org.eclipse.jetty.server.ConnectionFactory">
            <Item>
              <New class="org.eclipse.jetty.server.HttpConnectionFactory">
                <Arg name="config"><Ref refid="httpConfig" /></Arg>
              </New>
            </Item>
          </Array>
        </Arg>
        <Set name="host"><Property name="jetty.host" default="127.0.0.1" /></Set>
        <Set name="port"><Property name="jetty.port" default="8983" /></Set>
        <Set name="idleTimeout"><Property name="solr.jetty.http.idleTimeout" default="120000"/></Set>
        <Set name="soLingerTime"><Property name="solr.jetty.http.soLingerTime" default="-1"/></Set>
        <Set name="acceptorPriorityDelta"><Property name="solr.jetty.http.acceptorPriorityDelta" default="0"/></Set>
        <Set name="acceptQueueSize"><Property name="solr.jetty.http.acceptQueueSize" default="0"/></Set>
      </New>
    </Arg>
  </Call>

</Configure>
EOF


echo "solr hard nofile 65535" >> /etc/security/limits.conf  > /dev/null
echo "solr soft nofile 65535" >> /etc/security/limits.conf  > /dev/null
echo "solr soft nproc 65535" >> /etc/security/limits.conf > /dev/null
echo "solr hard nproc 65535" >> /etc/security/limits.conf  > /dev/null
sudo mkdir -p /opt/solrfcdata/var/solr/data/fccore | write_log > /dev/null
sudo rsync -r /var/www/html/thirdparty/solarium/fcskel/ /opt/solrfcdata/var/solr/data/fccore/  | write_log > /dev/null
sudo chown solr.solr /opt/solrfcdata/var/solr/data/fccore -Rf | write_log > /dev/null
cd   > /dev/null
rm -rvf $FC_UPGRADE_PATH/tmp/solrinstall | write_log > /dev/null
echo 'Solr Download directory is cleaned' | write_log > /dev/null

}

###################################################################################################################
###############################################FILECLOUD MONGODB INSTALLER#########################################
###################################################################################################################

mongodb_installer()
{

if [[ -n "$(command -v apt-get)" ]]; then

OS_RELEASE=`lsb_release -sc`

if [[ "$OS_RELEASE" = "xenial" ]]; then
wget -qO - https://www.mongodb.org/static/pgp/server-4.2.asc | sudo apt-key add - 2>&1 | write_log
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/4.2 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-4.2.list 2>&1  | write_log
apt-get update -y 2>&1 | write_log
apt-get install -y mongodb-org  2>&1  | write_log
systemctl enable mongod 2>&1 | write_log
echo "status: $?" >> /var/log/test.txt
systemctl start mongod 2>&1 | write_log
echo "status: $?" >> /var/log/test.txt
systemctl restart apache2 2>&1 | write_log
fi

if [[ "$OS_RELEASE" = "bionic" ]]; then
wget -qO - https://www.mongodb.org/static/pgp/server-4.2.asc | sudo apt-key add - 2>&1 | write_log
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu bionic/mongodb-org/4.2 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-4.2.list 2>&1  | write_log
apt-get update -y 2>&1 | write_log
apt-get install -y mongodb-org  2>&1  | write_log
systemctl enable mongod 2>&1 | write_log
echo "status: $?" >> /var/log/test.txt
systemctl start mongod 2>&1 | write_log
echo "status: $?" >> /var/log/test.txt
systemctl restart apache2 2>&1 | write_log
fi

if [[ "$OS_RELEASE" = "focal" ]]; then
wget -qO - https://www.mongodb.org/static/pgp/server-4.2.asc | sudo apt-key add - 2>&1 | write_log
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu bionic/mongodb-org/4.2 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-4.2.list 2>&1  | write_log
apt-get update -y 2>&1 | write_log
apt-get install -y mongodb-org  2>&1  | write_log
systemctl enable mongod 2>&1 | write_log
systemctl start mongod 2>&1 | write_log
systemctl restart apache2 2>&1 | write_log
fi

if [[ "$OS_RELEASE" = "stretch" ]]; then
wget -qO - https://www.mongodb.org/static/pgp/server-4.2.asc | sudo apt-key add - 2>&1 | write_log
echo "deb http://repo.mongodb.org/apt/debian stretch/mongodb-org/4.2 main" | sudo tee /etc/apt/sources.list.d/mongodb-org-4.2.list 2>&1  | write_log
apt-get update -y 2>&1 | write_log
apt-get install -y mongodb-org  2>&1  | write_log
systemctl enable mongod 2>&1 | write_log
systemctl start mongod 2>&1 | write_log
systemctl restart apache2 2>&1 | write_log
fi
if [[ "$OS_RELEASE" = "buster" ]]; then
wget -qO - https://www.mongodb.org/static/pgp/server-4.2.asc | sudo apt-key add - 2>&1 | write_log
echo "deb http://repo.mongodb.org/apt/debian buster/mongodb-org/4.2 main" | sudo tee /etc/apt/sources.list.d/mongodb-org-4.2.list 2>&1  | write_log
apt-get update -y 2>&1 | write_log
apt-get install -y mongodb-org  2>&1  | write_log
systemctl enable mongod 2>&1 | write_log
systemctl start mongod 2>&1 | write_log
systemctl restart apache2 2>&1 | write_log
fi
fi

if [[ -n "$(command -v yum)" ]]; then
cat <<EOF > /etc/yum.repos.d/mongodb-org-4.2.repo
[mongodb-org-4.2]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/\$releasever/mongodb-org/4.2/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-4.2.asc
EOF
yum update -y
yum install -y mongodb-org
systemctl enable mongod 2>&1 | write_log
systemctl start mongod 2>&1 | write_log
fi

}


#FILECLOUDCRON FUNCTION
##################################
filecloud_cron()
{
echo "Adding CronJob" | write_log
if [[ -n "$(command -v yum)" ]]; then
 echo "*/5 * * * * php /var/www/html/src/Scripts/cron.php"  | crontab -u apache - 2>/dev/null
 crontab -u apache -l
fi

if [[ -n "$(command -v apt-get)" ]]; then
echo "*/5 * * * * php /var/www/html/src/Scripts/cron.php" | crontab -u www-data -  2>/dev/null
crontab -u www-data -l
fi
}

fc_permission_fix()
{
echo "Setting up File/Folder permissions" 2>&1 | write_log

find /var/www/html -type d -exec chmod 0755 {} \;
find /var/www/html -type f -exec chmod 0644 {} \;

echo "Setting up User permissions" 2>&1 | write_log

if [ -n "$(command -v yum)" ]; then

 find /var/www/html -exec chown apache.apache {} \;
fi

if [ -n "$(command -v apt-get)" ]; then

find /var/www/html -exec chown www-data.www-data {} \;
fi

}

######################FILECLOUD NODEJS SETUP FUNCTION################################################
nodejs_setup()
{
if [[ -n "$(command -v yum)" ]]; then
curl -sL https://rpm.nodesource.com/setup_15.x | sudo bash - | write_log
yum update -y | write_log
echo " Installing  Filecloud node server" | write_log
yum install nodejs -y | write_log
mkdir -p /opt/fcnodejs
cd /opt/fcnodejs
echo " Downloading Filecloud node modules" | write_log
wget https://patch.codelathe.com/tonidocloud/live/3rdparty/node_modules/node_modules.zip
echo " Unzipping  Filecloud node modules" | write_log
unzip -q node_modules.zip | write_log
rm -rf /opt/fcnodejs/node_modules.zip
fi
if [[ -n "$(command -v apt)" ]]; then
curl -sL https://deb.nodesource.com/setup_15.x | sudo bash - | write_log
apt update -y | write_log
echo " Installing  Filecloud node server" | write_log
apt install -y nodejs | write_log
mkdir -p /opt/fcnodejs
cd /opt/fcnodejs
echo " Downloading Filecloud node modules" | write_log
wget https://patch.codelathe.com/tonidocloud/live/3rdparty/node_modules/node_modules.zip
echo " Unzipping  Filecloud node modules" | write_log
unzip -q node_modules.zip | write_log
rm -rf /opt/fcnodejs/node_modules.zip

fi
}
filecloud_orch()
{

#FILECLOUD NODEJS SERVICE  FUNCTION FOR RPM
##########################################
if [[ -n "$(command -v yum)" ]]; then

echo "Configuring Message Queue Services" | write_log
echo "Creating systemd service unit for Filecloud QUEUE service.." 2>&1 | write_log
cat > /etc/systemd/system/fcorchestrator.service <<'EOF'
[Unit]
Description= Filecloud Queue service
After=httpd.service

[Service]
Type=simple
PIDFile=/run/fcorchestrator.pid
ExecStart=/bin/sh -c '/usr/bin/node /var/www/html/src/Scripts/fcorchestrator.js'
ExecReload=/bin/kill -s HUP $MAINPID
ExecStop=/bin/kill -s QUIT $MAINPID
WorkingDirectory=/var/www/html/src/Scripts/
PrivateTmp=yes
User=apache
Restart=always
SuccessExitStatus=143

[Install]
WantedBy=multi-user.target
EOF

echo "Enabling and starting fcorchestrator" 2>&1 | write_log
systemctl daemon-reload 2>&1 | write_log
systemctl enable fcorchestrator 2>&1 | write_log
fi


#FILECLOUD NODEJS SERVICE FUNCTION FOR DEB
##########################################
if [[ -n "$(command -v apt-get)" ]]; then
echo "Creating systemd service unit for Filecloud QUEUE Server.." 2>&1 | write_log
cat > /etc/systemd/system/fcorchestrator.service <<'EOF'
[Unit]
Description= Filecloud Queue service
After=httpd.service

[Service]
Type=simple
PIDFile=/run/fcorchestrator.pid
ExecStart=/bin/sh -c '/usr/bin/node /var/www/html/src/Scripts/fcorchestrator.js'
ExecReload=/bin/kill -s HUP $MAINPID
ExecStop=/bin/kill -s QUIT $MAINPID
WorkingDirectory=/var/www/html/src/Scripts/
PrivateTmp=yes
User=www-data
Restart=always
SuccessExitStatus=143

[Install]
WantedBy=multi-user.target
EOF

echo "Enabling and starting fcorchestrator" 2>&1 | write_log
systemctl daemon-reload 2>&1 | write_log
systemctl enable fcorchestrator 2>&1 | write_log
fi


}


docconvertor_installer()
{
 if [[ -n "$(command -v yum)" ]]; then
yum remove libreoffice* -y
set -euo pipefail
if [[ -d  /usr/lib/libreoffice ]]; then
echo "Libreoffice DIR exists"
rm -rvf /usr/lib/libreoffice
else
echo "NO Libreoffice DIR exists"
fi
# Grab LibreOffice 6.0.1 -- version in centos repo does not work.
mkdir -p ${FC_INSTALL_DIR}/tmp/libreoffice 2>&1 | write_log
yum install libXinerama cairo cups-libs -y 2>&1 | write_log
cd ${FC_INSTALL_DIR}/tmp/libreoffice

{
URL2="https://patch.codelathe.com/tonidocloud/live/libreoffice/LibreOffice_7.1.7_Linux_x86-64_rpm.tar.gz"
wget -N "$URL2" -O LibreOffice.tar.gz 2>&1 | \
 stdbuf -o0 awk '/[.] +[0-9][0-9]?[0-9]?%/ { print substr($0,63,3) }'
} | whiptail --gauge "Downloading FileCloud DOCCONVERTOR" 7 60 0

tar xvf LibreOffice.tar.gz 2>&1 | write_log
cd ${FC_INSTALL_DIR}/tmp/libreoffice/LibreOffice_7.1.7.2_Linux_x86-64_rpm/RPMS 2>&1 | write_log
echo "Installing LibreOffice ..." 2>&1 | write_log
set +e
rpm -ivh ${FC_INSTALL_DIR}/tmp/libreoffice/LibreOffice_7.1.7.2_Linux_x86-64_rpm/RPMS/*.rpm 2>&1 | write_log
set -e
ln -sfn /usr/bin/libreoffice7.1 /usr/bin/libreoffice 2>&1 | write_log
ln -sfn /opt/libreoffice7.1 /usr/lib/libreoffice 2>&1 | write_log
echo "Removing LibreOffice temp files" 2>&1 | write_log
rm -rf ${FC_INSTALL_DIR}/tmp/libreoffice 2>&1 | write_log
echo "Downloading FileCloud Document Converter wrapper.." 2>&1 | write_log
mkdir -p /opt/app/fcdocconverter/
curl --location 'https://patch.codelathe.com/tonidocloud/live/3rdparty/fcdocconverter/FCDocConverter.jar' -o /opt/app/fcdocconverter/FCDocConverter.jar 2>&1 | write_log
 echo "Creating systemd service unit for FCDocConverter.." 2>&1 | write_log
 cat > /etc/systemd/system/fcdocconverter.service <<EOL
        [Unit]
        Description=FileCloud Doc Converter service
        After=network.target httpd.service

        [Service]
        Type=simple
        ExecStart=/bin/sh -c '/usr/bin/env  HOME=/var/www/html  java -Djava.library.path="/usr/lib/libreoffice/program/" -jar /opt/app/fcdocconverter/FCDocConverter.jar'
        WorkingDirectory=/opt/app/fcdocconverter
        PrivateTmp=no
        User=apache
        Restart=always
        SuccessExitStatus=143

        [Install]
        WantedBy=multi-user.target
EOL
echo "Enabling and starting fcdocconverter." 2>&1 | write_log
systemctl daemon-reload 2>&1 | write_log
systemctl enable fcdocconverter 2>&1 | write_log
#systemctl restart fcdocconverter 2>&1 | write_log
fi
if [[ -n "$(command -v apt)" ]]; then
apt-get purge libreoffice* -y
if [[ -d  /usr/lib/libreoffice ]]; then
echo "Libreoffice DIR exists"
rm -rvf /usr/lib/libreoffice
else
echo "NO Libreoffice DIR exists"
fi

sudo mkdir -p ${FC_INSTALL_DIR}/tmp/libreoffice 2>&1 | write_log
sudo apt-get install libxinerama1 libcairo2 libglu1-mesa libcups2 libsm6 -y 2>&1 | write_log
cd ${FC_INSTALL_DIR}/tmp/libreoffice
                        {
    URL1="https://patch.codelathe.com/tonidocloud/live/libreoffice/LibreOffice_7.1.7_Linux_x86-64_deb.tar.gz"

sudo wget -N "$URL1" -O LibreOffice.tar.gz 2>&1 | \
 stdbuf -o0 awk '/[.] +[0-9][0-9]?[0-9]?%/ { print substr($0,63,3) }'
} | whiptail --gauge "Downloading FileCloud DOCCONVERTOR" 7 60 0
sudo tar xvf LibreOffice.tar.gz 2>&1 | write_log
cd ${FC_INSTALL_DIR}/tmp/libreoffice/LibreOffice_7.1.7.2_Linux_x86-64_deb/DEBS
echo "Installing LibreOffice ..." 2>&1 | write_log
set +e
sudo dpkg -R --install ${FC_INSTALL_DIR}/tmp/libreoffice/LibreOffice_7.1.7.2_Linux_x86-64_deb/DEBS/ 2>&1 | write_log
set -e
echo "Removing LibreOffice temp files" 2>&1 | write_log
rm -rf ${FC_INSTALL_DIR}/tmp/libreoffice  | write_log
ln -sfn /usr/local/bin/libreoffice7.1 /usr/bin/libreoffice 2>&1 | write_log
ln -sfn /opt/libreoffice7.1 /usr/lib/libreoffice 2>&1 | write_log
echo "Downloading FileCloud Document Converter wrapper.." 2>&1 | write_log
mkdir -p /opt/app/fcdocconverter/
curl --location 'https://patch.codelathe.com/tonidocloud/live/3rdparty/fcdocconverter/FCDocConverter.jar' -o /opt/app/fcdocconverter/FCDocConverter.jar 2>&1 | write_log
 echo "Creating systemd service unit for FCDocConverter.." 2>&1 | write_log
 cat > /etc/systemd/system/fcdocconverter.service <<EOL
        [Unit]
        Description=FileCloud Doc Converter service
        After=network.target httpd.service

        [Service]
        Type=simple
        ExecStart=/bin/sh -c '/usr/bin/env  HOME=/var/www/html  java -Djava.library.path="/usr/lib/libreoffice/program/" -jar /opt/app/fcdocconverter/FCDocConverter.jar'
        WorkingDirectory=/opt/app/fcdocconverter
        PrivateTmp=no
        User=www-data
        Restart=always
        SuccessExitStatus=143

        [Install]
        WantedBy=multi-user.target
EOL
echo "Enabling and starting fcdocconverter." 2>&1 | write_log
systemctl daemon-reload 2>&1 | write_log
systemctl enable fcdocconverter 2>&1 | write_log
#systemctl restart fcdocconverter 2>&1 | write_log
fi

}
###################################################################################################################
##################################FILECLOUD DEB PACKAGE INSTALLER STARTS HERE######################################
###################################################################################################################


##FILECLOUD DEB PACKAGE XENIAL###
deb_package_installer_xenial()
{

### Add all repositories ############################
sudo rm /var/lib/apt/lists/lock | write_log
sudo rm /var/cache/apt/archives/lock | write_log
sudo rm /var/lib/dpkg/lock* | write_log
sudo dpkg --configure -a | write_log

echo -e "\n### Adding PHP repository ###############\n" 2>&1 | write_log > /dev/null
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
sudo apt-get install software-properties-common -y
sudo apt-get install language-pack-en -y
LC_ALL=C.UTF-8 sudo add-apt-repository ppa:ondrej/php -y 2>&1 | write_log > /dev/null
LC_ALL=C.UTF-8 add-apt-repository ppa:ondrej/apache2 -y  2>&1 | write_log > /dev/null

### Install Webserver ###################################

echo -e "\n### Installing apache #############\n" 2>&1 | write_log > /dev/null
sudo apt-get update -y 2>&1 | write_log > /dev/null
sudo apt-get install unzip curl rsync python  -y  2>&1 | write_log > /dev/null
sudo apt-get install apache2 build-essential libsslcommon2-dev libssl-dev pkg-config memcached apt-transport-https  language-pack-en  -y 2>&1 | write_log


### Install PHP 7.1 #################################

echo -e "\n### Installing PHP 7.2 #############\n" 2>&1 | write_log > /dev/null
sudo apt-get install php7.4 php7.4-cli php7.4-common php7.4-dev php-pear -y 2>&1 | write_log


sudo apt-key list |  grep "expired: " |  sed -ne 's|pub .*/\([^ ]*\) .*|\1|gp' |  xargs -n1 sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 2>&1 | write_log
apt-get update -y 2>&1 | write_log

echo -e "\n### Installing PHP extensions ######\n" 2>&1 | write_log
apt-get install php7.4-json php7.4-opcache php7.4-mbstring php7.4-zip php7.4-memcache php7.4-xml php7.4-bcmath libapache2-mod-php7.4 php7.4-gd php7.4-curl php7.4-ldap php7.4-gmp php7.4-mongodb php7.4-intl php7.4-mongodb libreadline-dev php-pecl-http  libxml2-dev -y 2>&1 | write_log

apt-get upgrade -y 2>&1 | write_log

set +e

echo "* Enabling Apache PHP 7.4 module..." 2>&1 | write_log
sudo a2dismod php7.2 2>&1 | write_log
sudo a2enmod php7.4 2>&1 | write_log


echo "* Enabling Apache SSL and Header module..." 2>&1 | write_log

a2enmod headers
a2enmod ssl

echo "* Restarting Apache..." 2>&1 | write_log
sudo service apache2 restart 2>&1 | write_log > /dev/null

set +e
echo "* Switching CLI PHP to 7.4..." 2>&1 | write_log
sudo update-alternatives --set php /usr/bin/php7.4 2>&1 | write_log > /dev/null
sudo update-alternatives --set phar /usr/bin/phar7.4 2>&1 | write_log > /dev/null
sudo update-alternatives --set phar.phar /usr/bin/phar.phar7.4 2>&1 | write_log > /dev/null
sudo update-alternatives --set phpize /usr/bin/phpize7.4 2>&1 | write_log > /dev/null
sudo update-alternatives --set php-config /usr/bin/php-config7.4 2>&1 | write_log > /dev/null

echo "* Switch to PHP 7.4 complete." 2>&1 | write_log
set -e


mkdir -p /etc/php/7.4/apache2/conf.d/
find /etc/php/7.4/cli/conf.d/ -type l -exec unlink {} \;
find /etc/php/7.4/apache2/conf.d/ -type l -exec unlink {} \;
#CREATING PHP EXTENSION
echo "extension=bcmath.so" > /etc/php/7.4/mods-available/bcmath.ini
echo "extension=calendar.so" > /etc/php/7.4/mods-available/calendar.ini
echo "extension=ctype.so" > /etc/php/7.4/mods-available/ctype.ini
echo "extension=curl.so" > /etc/php/7.4/mods-available/curl.ini
echo "extension=dom.so" > /etc/php/7.4/mods-available/dom.ini
echo "extension=exif.so" > /etc/php/7.4/mods-available/exif.ini
echo "extension=fileinfo.so" > /etc/php/7.4/mods-available/fileinfo.ini
echo "extension=ftp.so" > /etc/php/7.4/mods-available/ftp.ini
echo "extension=gd.so" > /etc/php/7.4/mods-available/gd.ini
echo "extension=gettext.so" > /etc/php/7.4/mods-available/gettext.ini
echo "extension=gmp.so" > /etc/php/7.4/mods-available/gmp.ini
echo "extension=iconv.so" > /etc/php/7.4/mods-available/iconv.ini
echo "extension=intl.so" > /etc/php/7.4/mods-available/intl.ini
echo "extension=json.so" > /etc/php/7.4/mods-available/json.ini
echo "extension=ldap.so" > /etc/php/7.4/mods-available/ldap.ini
echo "extension=mbstring.so" > /etc/php/7.4/mods-available/mbstring.ini
echo "extension=memcache.so" > /etc/php/7.4/mods-available/memcache.ini
echo "extension=mongodb.so" > /etc/php/7.4/mods-available/mongodb.ini
echo "zend_extension=opcache.so" > /etc/php/7.4/mods-available/opcache.ini
echo "extension=pdo.so" > /etc/php/7.4/mods-available/pdo.ini
echo "extension=phar.so" > /etc/php/7.4/mods-available/phar.ini
echo "extension=posix.so" > /etc/php/7.4/mods-available/posix.ini
echo "extension=readline.so" > /etc/php/7.4/mods-available/readline.ini
echo "extension=shmop.so" > /etc/php/7.4/mods-available/shmop.ini
echo "extension=simplexml.so" > /etc/php/7.4/mods-available/simplexml.ini
echo "extension=sockets.so" > /etc/php/7.4/mods-available/sockets.ini
echo "extension=sysvmsg.so" > /etc/php/7.4/mods-available/sysvmsg.ini
echo "extension=sysvsem.so" > /etc/php/7.4/mods-available/sysvsem.ini
echo "extension=sysvshm.so" > /etc/php/7.4/mods-available/sysvshm.ini
echo "extension=tokenizer.so" > /etc/php/7.4/mods-available/tokenizer.ini
#echo "extension=wddx.so" > /etc/php/7.4/mods-available/wddx.ini
echo "extension=xml.so" > /etc/php/7.4/mods-available/xml.ini
echo "extension=xmlreader.so" > /etc/php/7.4/mods-available/xmlreader.ini
echo "extension=xmlwriter.so" > /etc/php/7.4/mods-available/xmlwriter.ini
echo "extension=xsl.so" > /etc/php/7.4/mods-available/xsl.ini
echo "extension=zip.so" > /etc/php/7.4/mods-available/zip.ini

#CLI SYMLINKS

ln -sfn /etc/php/7.4/mods-available/bcmath.ini /etc/php/7.4/cli/conf.d/20-bcmath.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/calendar.ini /etc/php/7.4/cli/conf.d/20-calendar.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/ctype.ini /etc/php/7.4/cli/conf.d/20-ctype.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/curl.ini /etc/php/7.4/cli/conf.d/20-curl.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/dom.ini /etc/php/7.4/cli/conf.d/20-dom.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/exif.ini /etc/php/7.4/cli/conf.d/20-exif.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/fileinfo.ini /etc/php/7.4/cli/conf.d/20-fileinfo.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/ftp.ini /etc/php/7.4/cli/conf.d/20-ftp.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/gd.ini /etc/php/7.4/cli/conf.d/20-gd.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/gettext.ini  /etc/php/7.4/cli/conf.d/20-gettext.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/gmp.ini /etc/php/7.4/cli/conf.d/20-gmp.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/iconv.ini /etc/php/7.4/cli/conf.d/20-iconv.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/intl.ini /etc/php/7.4/cli/conf.d/20-intl.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/json.ini /etc/php/7.4/cli/conf.d/20-json.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/ldap.ini /etc/php/7.4/cli/conf.d/20-ldap.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/mbstring.ini /etc/php/7.4/cli/conf.d/20-mbstring.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/memcache.ini /etc/php/7.4/cli/conf.d/20-memcache.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/mongodb.ini /etc/php/7.4/cli/conf.d/20-mongodb.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/opcache.ini /etc/php/7.4/cli/conf.d/20-opcache.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/pdo.ini /etc/php/7.4/cli/conf.d/20-pdo.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/phar.ini /etc/php/7.4/cli/conf.d/20-phar.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/posix.ini /etc/php/7.4/cli/conf.d/20-posix.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/readline.ini /etc/php/7.4/cli/conf.d/20-readline.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/shmop.ini /etc/php/7.4/cli/conf.d/20-shmop.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/simplexml.ini  /etc/php/7.4/cli/conf.d/20-simplexml.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sockets.ini /etc/php/7.4/cli/conf.d/20-sockets.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sysvmsg.ini /etc/php/7.4/cli/conf.d/20-sysvmsg.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sysvsem.ini /etc/php/7.4/cli/conf.d/20-sysvsem.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sysvshm.ini /etc/php/7.4/cli/conf.d/sysvshm.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/tokenizer.ini /etc/php/7.4/cli/conf.d/20-tokenizer.ini 2>&1 | write_log
#ln -sfn /etc/php/7.4/mods-available/wddx.ini /etc/php/7.4/cli/conf.d/20-wddx.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xml.ini /etc/php/7.4/cli/conf.d/15-xml.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xmlreader.ini /etc/php/7.4/cli/conf.d/20-xmlreader.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xmlwriter.ini /etc/php/7.4/cli/conf.d/20-xmlwriter.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xsl.ini /etc/php/7.4/cli/conf.d/20-xsl.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/zip.ini /etc/php/7.4/cli/conf.d/20-zip.ini 2>&1 | write_log
#ln -sfn /etc/php/7.4/mods-available/zmq.ini /etc/php/7.4/cli/conf.d/20-zmq.ini 2>&1 | write_log
#APACHE SYMLINKS
ln -sfn /etc/php/7.4/mods-available/bcmath.ini /etc/php/7.4/apache2/conf.d/20-bcmath.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/calendar.ini /etc/php/7.4/apache2/conf.d/20-calendar.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/ctype.ini /etc/php/7.4/apache2/conf.d/20-ctype.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/curl.ini /etc/php/7.4/apache2/conf.d/20-curl.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/dom.ini /etc/php/7.4/apache2/conf.d/20-dom.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/exif.ini /etc/php/7.4/apache2/conf.d/20-exif.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/fileinfo.ini /etc/php/7.4/apache2/conf.d/20-fileinfo.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/ftp.ini /etc/php/7.4/apache2/conf.d/20-ftp.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/gd.ini /etc/php/7.4/apache2/conf.d/20-gd.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/gettext.ini  /etc/php/7.4/apache2/conf.d/20-gettext.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/gmp.ini /etc/php/7.4/apache2/conf.d/20-gmp.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/iconv.ini /etc/php/7.4/apache2/conf.d/20-iconv.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/intl.ini /etc/php/7.4/apache2/conf.d/20-intl.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/json.ini /etc/php/7.4/apache2/conf.d/20-json.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/ldap.ini /etc/php/7.4/apache2/conf.d/20-ldap.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/mbstring.ini /etc/php/7.4/apache2/conf.d/20-mbstring.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/memcache.ini /etc/php/7.4/apache2/conf.d/20-memcache.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/mongodb.ini /etc/php/7.4/apache2/conf.d/20-mongodb.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/opcache.ini /etc/php/7.4/apache2/conf.d/20-opcache.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/pdo.ini /etc/php/7.4/apache2/conf.d/20-pdo.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/phar.ini /etc/php/7.4/apache2/conf.d/20-phar.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/posix.ini /etc/php/7.4/apache2/conf.d/20-posix.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/readline.ini /etc/php/7.4/apache2/conf.d/20-readline.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/shmop.ini /etc/php/7.4/apache2/conf.d/20-shmop.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/simplexml.ini  /etc/php/7.4/apache2/conf.d/20-simplexml.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sockets.ini /etc/php/7.4/apache2/conf.d/20-sockets.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sysvmsg.ini /etc/php/7.4/apache2/conf.d/20-sysvmsg.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sysvsem.ini /etc/php/7.4/apache2/conf.d/20-sysvsem.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sysvshm.ini /etc/php/7.4/apache2/conf.d/sysvshm.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/tokenizer.ini /etc/php/7.4/apache2/conf.d/20-tokenizer.ini 2>&1 | write_log
#ln -sfn /etc/php/7.4/mods-available/wddx.ini /etc/php/7.4/apache2/conf.d/20-wddx.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xml.ini /etc/php/7.4/apache2/conf.d/15-xml.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xmlreader.ini /etc/php/7.4/apache2/conf.d/20-xmlreader.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xmlwriter.ini /etc/php/7.4/apache2/conf.d/20-xmlwriter.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xsl.ini /etc/php/7.4/apache2/conf.d/20-xsl.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/zip.ini /etc/php/7.4/apache2/conf.d/20-zip.ini 2>&1 | write_log


apt-get -y install libmcrypt-dev 2>&1 | write_log
apt-get install php7.4-mcrypt -y | write_log
echo "extension=mcrypt.so" > /etc/php/7.4/mods-available/mcrypt.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/mcrypt.ini /etc/php/7.4/apache2/conf.d/20-mcrypt.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/mcrypt.ini /etc/php/7.4/cli/conf.d/20-mcrypt.ini 2>&1 | write_log


### Install MongoDB driver for PHP 7.2 ##############

echo -e "\n### Installing MongoDB PHP driver ##\n" 2>&1 | write_log
sudo apt-get install php-mongodb -y 2>&1 | write_log


### Verify installs #################################

echo -e "" 2>&1 | write_log > /dev/null
echo -e "###############################" 2>&1 | write_log > /dev/null
echo -e "### VERIFY THE OUTPUT BELOW ###" 2>&1 | write_log > /dev/null
echo -e "###############################" 2>&1 | write_log > /dev/null
echo -e "\n### PHP ###############\n" 2>&1 | write_log > /dev/null
echo -e "$(php -v)" 2>&1 | write_log > /dev/null

rm -rvf ${FC_INSTALL_DIR}/ioncubeinstall 2>&1 | write_log > /dev/null

}

###FILECLOUD DEB PACKAGE BIONIC###

deb_package_installer_bionic()
{

### Add all repositories ############################
sudo rm /var/lib/apt/lists/lock | write_log
sudo rm /var/cache/apt/archives/lock | write_log
sudo rm /var/lib/dpkg/lock* | write_log
sudo dpkg --configure -a | write_log

echo -e "\n### Adding PHP repository ###############\n" 2>&1 | write_log > /dev/null
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
sudo apt-get install software-properties-common -y
sudo apt-get install language-pack-en -y
LC_ALL=C.UTF-8 sudo add-apt-repository ppa:ondrej/php -y 2>&1 | write_log > /dev/null
LC_ALL=C.UTF-8 add-apt-repository ppa:ondrej/apache2 -y  2>&1 | write_log > /dev/null

### Install Webserver ###################################

echo -e "\n### Installing apache #############\n" 2>&1 | write_log > /dev/null
sudo apt-get update -y 2>&1 | write_log > /dev/null
sudo apt-get install unzip curl rsync python  -y  2>&1 | write_log > /dev/null
sudo apt-get install apache2 build-essential libsslcommon2-dev libssl-dev pkg-config memcached apt-transport-https  language-pack-en  -y 2>&1 | write_log


### Install PHP 7.1 #################################

sudo apt-get install php7.4 php7.4-cli php7.4-common php7.4-dev php-pear -y 2>&1 | write_log


sudo apt-key list |  grep "expired: " |  sed -ne 's|pub .*/\([^ ]*\) .*|\1|gp' |  xargs -n1 sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 2>&1 | write_log
apt-get update -y 2>&1 | write_log

echo -e "\n### Installing PHP extensions ######\n" 2>&1 | write_log
apt-get install php7.4-json php7.4-opcache php7.4-mbstring php7.4-zip php7.4-memcache php7.4-xml php7.4-bcmath libapache2-mod-php7.4 php7.4-gd php7.4-curl php7.4-ldap php7.4-gmp php7.4-mongodb php7.4-intl php7.4-mongodb libreadline-dev php-pecl-http  libxml2-dev -y 2>&1 | write_log

apt-get upgrade -y 2>&1 | write_log

set +e

echo "* Enabling Apache PHP 7.4 module..." 2>&1 | write_log
sudo a2dismod php7.2 2>&1 | write_log
sudo a2enmod php7.4 2>&1 | write_log


echo "* Enabling Apache SSL and Header module..." 2>&1 | write_log

a2enmod headers
a2enmod ssl

echo "* Restarting Apache..." 2>&1 | write_log
sudo service apache2 restart 2>&1 | write_log > /dev/null

set +e
echo "* Switching CLI PHP to 7.4..." 2>&1 | write_log
sudo update-alternatives --set php /usr/bin/php7.4 2>&1 | write_log > /dev/null
sudo update-alternatives --set phar /usr/bin/phar7.4 2>&1 | write_log > /dev/null
sudo update-alternatives --set phar.phar /usr/bin/phar.phar7.4 2>&1 | write_log > /dev/null
sudo update-alternatives --set phpize /usr/bin/phpize7.4 2>&1 | write_log > /dev/null
sudo update-alternatives --set php-config /usr/bin/php-config7.4 2>&1 | write_log > /dev/null

echo "* Switch to PHP 7.4 complete." 2>&1 | write_log
set -e


mkdir -p /etc/php/7.4/apache2/conf.d/
find /etc/php/7.4/cli/conf.d/ -type l -exec unlink {} \;
find /etc/php/7.4/apache2/conf.d/ -type l -exec unlink {} \;
#CREATING PHP EXTENSION
echo "extension=bcmath.so" > /etc/php/7.4/mods-available/bcmath.ini
echo "extension=calendar.so" > /etc/php/7.4/mods-available/calendar.ini
echo "extension=ctype.so" > /etc/php/7.4/mods-available/ctype.ini
echo "extension=curl.so" > /etc/php/7.4/mods-available/curl.ini
echo "extension=dom.so" > /etc/php/7.4/mods-available/dom.ini
echo "extension=exif.so" > /etc/php/7.4/mods-available/exif.ini
echo "extension=fileinfo.so" > /etc/php/7.4/mods-available/fileinfo.ini
echo "extension=ftp.so" > /etc/php/7.4/mods-available/ftp.ini
echo "extension=gd.so" > /etc/php/7.4/mods-available/gd.ini
echo "extension=gettext.so" > /etc/php/7.4/mods-available/gettext.ini
echo "extension=gmp.so" > /etc/php/7.4/mods-available/gmp.ini
echo "extension=iconv.so" > /etc/php/7.4/mods-available/iconv.ini
echo "extension=intl.so" > /etc/php/7.4/mods-available/intl.ini
echo "extension=json.so" > /etc/php/7.4/mods-available/json.ini
echo "extension=ldap.so" > /etc/php/7.4/mods-available/ldap.ini
echo "extension=mbstring.so" > /etc/php/7.4/mods-available/mbstring.ini
echo "extension=memcache.so" > /etc/php/7.4/mods-available/memcache.ini
echo "extension=mongodb.so" > /etc/php/7.4/mods-available/mongodb.ini
echo "zend_extension=opcache.so" > /etc/php/7.4/mods-available/opcache.ini
echo "extension=pdo.so" > /etc/php/7.4/mods-available/pdo.ini
echo "extension=phar.so" > /etc/php/7.4/mods-available/phar.ini
echo "extension=posix.so" > /etc/php/7.4/mods-available/posix.ini
echo "extension=readline.so" > /etc/php/7.4/mods-available/readline.ini
echo "extension=shmop.so" > /etc/php/7.4/mods-available/shmop.ini
echo "extension=simplexml.so" > /etc/php/7.4/mods-available/simplexml.ini
echo "extension=sockets.so" > /etc/php/7.4/mods-available/sockets.ini
echo "extension=sysvmsg.so" > /etc/php/7.4/mods-available/sysvmsg.ini
echo "extension=sysvsem.so" > /etc/php/7.4/mods-available/sysvsem.ini
echo "extension=sysvshm.so" > /etc/php/7.4/mods-available/sysvshm.ini
echo "extension=tokenizer.so" > /etc/php/7.4/mods-available/tokenizer.ini
#echo "extension=wddx.so" > /etc/php/7.4/mods-available/wddx.ini
echo "extension=xml.so" > /etc/php/7.4/mods-available/xml.ini
echo "extension=xmlreader.so" > /etc/php/7.4/mods-available/xmlreader.ini
echo "extension=xmlwriter.so" > /etc/php/7.4/mods-available/xmlwriter.ini
echo "extension=xsl.so" > /etc/php/7.4/mods-available/xsl.ini
echo "extension=zip.so" > /etc/php/7.4/mods-available/zip.ini

#CLI SYMLINKS

ln -sfn /etc/php/7.4/mods-available/bcmath.ini /etc/php/7.4/cli/conf.d/20-bcmath.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/calendar.ini /etc/php/7.4/cli/conf.d/20-calendar.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/ctype.ini /etc/php/7.4/cli/conf.d/20-ctype.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/curl.ini /etc/php/7.4/cli/conf.d/20-curl.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/dom.ini /etc/php/7.4/cli/conf.d/20-dom.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/exif.ini /etc/php/7.4/cli/conf.d/20-exif.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/fileinfo.ini /etc/php/7.4/cli/conf.d/20-fileinfo.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/ftp.ini /etc/php/7.4/cli/conf.d/20-ftp.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/gd.ini /etc/php/7.4/cli/conf.d/20-gd.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/gettext.ini  /etc/php/7.4/cli/conf.d/20-gettext.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/gmp.ini /etc/php/7.4/cli/conf.d/20-gmp.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/iconv.ini /etc/php/7.4/cli/conf.d/20-iconv.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/intl.ini /etc/php/7.4/cli/conf.d/20-intl.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/json.ini /etc/php/7.4/cli/conf.d/20-json.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/ldap.ini /etc/php/7.4/cli/conf.d/20-ldap.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/mbstring.ini /etc/php/7.4/cli/conf.d/20-mbstring.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/memcache.ini /etc/php/7.4/cli/conf.d/20-memcache.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/mongodb.ini /etc/php/7.4/cli/conf.d/20-mongodb.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/opcache.ini /etc/php/7.4/cli/conf.d/20-opcache.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/pdo.ini /etc/php/7.4/cli/conf.d/20-pdo.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/phar.ini /etc/php/7.4/cli/conf.d/20-phar.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/posix.ini /etc/php/7.4/cli/conf.d/20-posix.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/readline.ini /etc/php/7.4/cli/conf.d/20-readline.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/shmop.ini /etc/php/7.4/cli/conf.d/20-shmop.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/simplexml.ini  /etc/php/7.4/cli/conf.d/20-simplexml.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sockets.ini /etc/php/7.4/cli/conf.d/20-sockets.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sysvmsg.ini /etc/php/7.4/cli/conf.d/20-sysvmsg.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sysvsem.ini /etc/php/7.4/cli/conf.d/20-sysvsem.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sysvshm.ini /etc/php/7.4/cli/conf.d/sysvshm.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/tokenizer.ini /etc/php/7.4/cli/conf.d/20-tokenizer.ini 2>&1 | write_log
#ln -sfn /etc/php/7.4/mods-available/wddx.ini /etc/php/7.4/cli/conf.d/20-wddx.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xml.ini /etc/php/7.4/cli/conf.d/15-xml.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xmlreader.ini /etc/php/7.4/cli/conf.d/20-xmlreader.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xmlwriter.ini /etc/php/7.4/cli/conf.d/20-xmlwriter.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xsl.ini /etc/php/7.4/cli/conf.d/20-xsl.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/zip.ini /etc/php/7.4/cli/conf.d/20-zip.ini 2>&1 | write_log
#ln -sfn /etc/php/7.4/mods-available/zmq.ini /etc/php/7.4/cli/conf.d/20-zmq.ini 2>&1 | write_log
#APACHE SYMLINKS
ln -sfn /etc/php/7.4/mods-available/bcmath.ini /etc/php/7.4/apache2/conf.d/20-bcmath.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/calendar.ini /etc/php/7.4/apache2/conf.d/20-calendar.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/ctype.ini /etc/php/7.4/apache2/conf.d/20-ctype.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/curl.ini /etc/php/7.4/apache2/conf.d/20-curl.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/dom.ini /etc/php/7.4/apache2/conf.d/20-dom.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/exif.ini /etc/php/7.4/apache2/conf.d/20-exif.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/fileinfo.ini /etc/php/7.4/apache2/conf.d/20-fileinfo.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/ftp.ini /etc/php/7.4/apache2/conf.d/20-ftp.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/gd.ini /etc/php/7.4/apache2/conf.d/20-gd.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/gettext.ini  /etc/php/7.4/apache2/conf.d/20-gettext.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/gmp.ini /etc/php/7.4/apache2/conf.d/20-gmp.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/iconv.ini /etc/php/7.4/apache2/conf.d/20-iconv.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/intl.ini /etc/php/7.4/apache2/conf.d/20-intl.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/json.ini /etc/php/7.4/apache2/conf.d/20-json.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/ldap.ini /etc/php/7.4/apache2/conf.d/20-ldap.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/mbstring.ini /etc/php/7.4/apache2/conf.d/20-mbstring.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/memcache.ini /etc/php/7.4/apache2/conf.d/20-memcache.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/mongodb.ini /etc/php/7.4/apache2/conf.d/20-mongodb.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/opcache.ini /etc/php/7.4/apache2/conf.d/20-opcache.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/pdo.ini /etc/php/7.4/apache2/conf.d/20-pdo.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/phar.ini /etc/php/7.4/apache2/conf.d/20-phar.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/posix.ini /etc/php/7.4/apache2/conf.d/20-posix.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/readline.ini /etc/php/7.4/apache2/conf.d/20-readline.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/shmop.ini /etc/php/7.4/apache2/conf.d/20-shmop.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/simplexml.ini  /etc/php/7.4/apache2/conf.d/20-simplexml.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sockets.ini /etc/php/7.4/apache2/conf.d/20-sockets.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sysvmsg.ini /etc/php/7.4/apache2/conf.d/20-sysvmsg.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sysvsem.ini /etc/php/7.4/apache2/conf.d/20-sysvsem.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sysvshm.ini /etc/php/7.4/apache2/conf.d/sysvshm.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/tokenizer.ini /etc/php/7.4/apache2/conf.d/20-tokenizer.ini 2>&1 | write_log
#ln -sfn /etc/php/7.4/mods-available/wddx.ini /etc/php/7.4/apache2/conf.d/20-wddx.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xml.ini /etc/php/7.4/apache2/conf.d/15-xml.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xmlreader.ini /etc/php/7.4/apache2/conf.d/20-xmlreader.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xmlwriter.ini /etc/php/7.4/apache2/conf.d/20-xmlwriter.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xsl.ini /etc/php/7.4/apache2/conf.d/20-xsl.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/zip.ini /etc/php/7.4/apache2/conf.d/20-zip.ini 2>&1 | write_log


apt-get -y install libmcrypt-dev 2>&1 | write_log
apt-get install php7.4-mcrypt -y | write_log
echo "extension=mcrypt.so" > /etc/php/7.4/mods-available/mcrypt.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/mcrypt.ini /etc/php/7.4/apache2/conf.d/20-mcrypt.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/mcrypt.ini /etc/php/7.4/cli/conf.d/20-mcrypt.ini 2>&1 | write_log


### Install MongoDB driver for PHP 7.2 ##############

echo -e "\n### Installing MongoDB PHP driver ##\n" 2>&1 | write_log
sudo apt-get install php-mongodb -y 2>&1 | write_log


### Verify installs #################################

echo -e "" 2>&1 | write_log > /dev/null
echo -e "###############################" 2>&1 | write_log > /dev/null
echo -e "### VERIFY THE OUTPUT BELOW ###" 2>&1 | write_log > /dev/null
echo -e "###############################" 2>&1 | write_log > /dev/null
echo -e "\n### PHP ###############\n" 2>&1 | write_log > /dev/null
echo -e "$(php -v)" 2>&1 | write_log > /dev/null

rm -rvf ${FC_INSTALL_DIR}/ioncubeinstall 2>&1 | write_log > /dev/null

}

###FILECLOUD DEB PACKAGE BIONIC###

deb_package_installer_focal()
{

### Add all repositories ############################
sudo rm /var/lib/apt/lists/lock | write_log
sudo rm /var/cache/apt/archives/lock | write_log
sudo rm /var/lib/dpkg/lock* | write_log
sudo dpkg --configure -a | write_log

echo -e "\n### Adding PHP repository ###############\n" 2>&1 | write_log > /dev/null
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
sudo apt-get install software-properties-common -y
sudo apt-get install language-pack-en -y
LC_ALL=C.UTF-8 sudo add-apt-repository ppa:ondrej/php -y 2>&1 | write_log > /dev/null
LC_ALL=C.UTF-8 add-apt-repository ppa:ondrej/apache2 -y  2>&1 | write_log > /dev/null

### Install Webserver ###################################

echo -e "\n### Installing apache #############\n" 2>&1 | write_log > /dev/null
sudo apt-get update -y 2>&1 | write_log > /dev/null
sudo apt-get install unzip curl rsync python  -y  2>&1 | write_log > /dev/null
sudo apt-get install apache2 build-essential  libssl-dev pkg-config memcached apt-transport-https  language-pack-en  -y 2>&1 | write_log


### Install PHP 7.1 #################################

sudo apt-get install php7.4 php7.4-cli php7.4-common php7.4-dev php-pear -y 2>&1 | write_log


sudo apt-key list |  grep "expired: " |  sed -ne 's|pub .*/\([^ ]*\) .*|\1|gp' |  xargs -n1 sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 2>&1 | write_log
apt-get update -y 2>&1 | write_log

echo -e "\n### Installing PHP extensions ######\n" 2>&1 | write_log
apt-get install php7.4-json php7.4-opcache php7.4-mbstring php7.4-zip php7.4-memcache php7.4-xml php7.4-bcmath libapache2-mod-php7.4 php7.4-gd php7.4-curl php7.4-ldap php7.4-gmp php7.4-mongodb php7.4-intl php7.4-mongodb libreadline-dev php-pecl-http  libxml2-dev -y 2>&1 | write_log

apt-get upgrade -y 2>&1 | write_log

set +e

echo "* Enabling Apache PHP 7.4 module..." 2>&1 | write_log
sudo a2dismod php7.2 2>&1 | write_log
sudo a2enmod php7.4 2>&1 | write_log


echo "* Enabling Apache SSL and Header module..." 2>&1 | write_log

a2enmod headers
a2enmod ssl

echo "* Restarting Apache..." 2>&1 | write_log
sudo service apache2 restart 2>&1 | write_log > /dev/null

set +e
echo "* Switching CLI PHP to 7.4..." 2>&1 | write_log
sudo update-alternatives --set php /usr/bin/php7.4 2>&1 | write_log > /dev/null
sudo update-alternatives --set phar /usr/bin/phar7.4 2>&1 | write_log > /dev/null
sudo update-alternatives --set phar.phar /usr/bin/phar.phar7.4 2>&1 | write_log > /dev/null
sudo update-alternatives --set phpize /usr/bin/phpize7.4 2>&1 | write_log > /dev/null
sudo update-alternatives --set php-config /usr/bin/php-config7.4 2>&1 | write_log > /dev/null

echo "* Switch to PHP 7.4 complete." 2>&1 | write_log
set -e


mkdir -p /etc/php/7.4/apache2/conf.d/
find /etc/php/7.4/cli/conf.d/ -type l -exec unlink {} \;
find /etc/php/7.4/apache2/conf.d/ -type l -exec unlink {} \;
#CREATING PHP EXTENSION
echo "extension=bcmath.so" > /etc/php/7.4/mods-available/bcmath.ini
echo "extension=calendar.so" > /etc/php/7.4/mods-available/calendar.ini
echo "extension=ctype.so" > /etc/php/7.4/mods-available/ctype.ini
echo "extension=curl.so" > /etc/php/7.4/mods-available/curl.ini
echo "extension=dom.so" > /etc/php/7.4/mods-available/dom.ini
echo "extension=exif.so" > /etc/php/7.4/mods-available/exif.ini
echo "extension=fileinfo.so" > /etc/php/7.4/mods-available/fileinfo.ini
echo "extension=ftp.so" > /etc/php/7.4/mods-available/ftp.ini
echo "extension=gd.so" > /etc/php/7.4/mods-available/gd.ini
echo "extension=gettext.so" > /etc/php/7.4/mods-available/gettext.ini
echo "extension=gmp.so" > /etc/php/7.4/mods-available/gmp.ini
echo "extension=iconv.so" > /etc/php/7.4/mods-available/iconv.ini
echo "extension=intl.so" > /etc/php/7.4/mods-available/intl.ini
echo "extension=json.so" > /etc/php/7.4/mods-available/json.ini
echo "extension=ldap.so" > /etc/php/7.4/mods-available/ldap.ini
echo "extension=mbstring.so" > /etc/php/7.4/mods-available/mbstring.ini
echo "extension=memcache.so" > /etc/php/7.4/mods-available/memcache.ini
echo "extension=mongodb.so" > /etc/php/7.4/mods-available/mongodb.ini
echo "zend_extension=opcache.so" > /etc/php/7.4/mods-available/opcache.ini
echo "extension=pdo.so" > /etc/php/7.4/mods-available/pdo.ini
echo "extension=phar.so" > /etc/php/7.4/mods-available/phar.ini
echo "extension=posix.so" > /etc/php/7.4/mods-available/posix.ini
echo "extension=readline.so" > /etc/php/7.4/mods-available/readline.ini
echo "extension=shmop.so" > /etc/php/7.4/mods-available/shmop.ini
echo "extension=simplexml.so" > /etc/php/7.4/mods-available/simplexml.ini
echo "extension=sockets.so" > /etc/php/7.4/mods-available/sockets.ini
echo "extension=sysvmsg.so" > /etc/php/7.4/mods-available/sysvmsg.ini
echo "extension=sysvsem.so" > /etc/php/7.4/mods-available/sysvsem.ini
echo "extension=sysvshm.so" > /etc/php/7.4/mods-available/sysvshm.ini
echo "extension=tokenizer.so" > /etc/php/7.4/mods-available/tokenizer.ini
#echo "extension=wddx.so" > /etc/php/7.4/mods-available/wddx.ini
echo "extension=xml.so" > /etc/php/7.4/mods-available/xml.ini
echo "extension=xmlreader.so" > /etc/php/7.4/mods-available/xmlreader.ini
echo "extension=xmlwriter.so" > /etc/php/7.4/mods-available/xmlwriter.ini
echo "extension=xsl.so" > /etc/php/7.4/mods-available/xsl.ini
echo "extension=zip.so" > /etc/php/7.4/mods-available/zip.ini

#CLI SYMLINKS

ln -sfn /etc/php/7.4/mods-available/bcmath.ini /etc/php/7.4/cli/conf.d/20-bcmath.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/calendar.ini /etc/php/7.4/cli/conf.d/20-calendar.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/ctype.ini /etc/php/7.4/cli/conf.d/20-ctype.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/curl.ini /etc/php/7.4/cli/conf.d/20-curl.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/dom.ini /etc/php/7.4/cli/conf.d/20-dom.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/exif.ini /etc/php/7.4/cli/conf.d/20-exif.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/fileinfo.ini /etc/php/7.4/cli/conf.d/20-fileinfo.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/ftp.ini /etc/php/7.4/cli/conf.d/20-ftp.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/gd.ini /etc/php/7.4/cli/conf.d/20-gd.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/gettext.ini  /etc/php/7.4/cli/conf.d/20-gettext.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/gmp.ini /etc/php/7.4/cli/conf.d/20-gmp.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/iconv.ini /etc/php/7.4/cli/conf.d/20-iconv.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/intl.ini /etc/php/7.4/cli/conf.d/20-intl.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/json.ini /etc/php/7.4/cli/conf.d/20-json.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/ldap.ini /etc/php/7.4/cli/conf.d/20-ldap.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/mbstring.ini /etc/php/7.4/cli/conf.d/20-mbstring.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/memcache.ini /etc/php/7.4/cli/conf.d/20-memcache.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/mongodb.ini /etc/php/7.4/cli/conf.d/20-mongodb.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/opcache.ini /etc/php/7.4/cli/conf.d/20-opcache.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/pdo.ini /etc/php/7.4/cli/conf.d/20-pdo.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/phar.ini /etc/php/7.4/cli/conf.d/20-phar.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/posix.ini /etc/php/7.4/cli/conf.d/20-posix.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/readline.ini /etc/php/7.4/cli/conf.d/20-readline.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/shmop.ini /etc/php/7.4/cli/conf.d/20-shmop.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/simplexml.ini  /etc/php/7.4/cli/conf.d/20-simplexml.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sockets.ini /etc/php/7.4/cli/conf.d/20-sockets.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sysvmsg.ini /etc/php/7.4/cli/conf.d/20-sysvmsg.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sysvsem.ini /etc/php/7.4/cli/conf.d/20-sysvsem.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sysvshm.ini /etc/php/7.4/cli/conf.d/sysvshm.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/tokenizer.ini /etc/php/7.4/cli/conf.d/20-tokenizer.ini 2>&1 | write_log
#ln -sfn /etc/php/7.4/mods-available/wddx.ini /etc/php/7.4/cli/conf.d/20-wddx.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xml.ini /etc/php/7.4/cli/conf.d/15-xml.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xmlreader.ini /etc/php/7.4/cli/conf.d/20-xmlreader.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xmlwriter.ini /etc/php/7.4/cli/conf.d/20-xmlwriter.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xsl.ini /etc/php/7.4/cli/conf.d/20-xsl.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/zip.ini /etc/php/7.4/cli/conf.d/20-zip.ini 2>&1 | write_log
#ln -sfn /etc/php/7.4/mods-available/zmq.ini /etc/php/7.4/cli/conf.d/20-zmq.ini 2>&1 | write_log
#APACHE SYMLINKS
ln -sfn /etc/php/7.4/mods-available/bcmath.ini /etc/php/7.4/apache2/conf.d/20-bcmath.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/calendar.ini /etc/php/7.4/apache2/conf.d/20-calendar.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/ctype.ini /etc/php/7.4/apache2/conf.d/20-ctype.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/curl.ini /etc/php/7.4/apache2/conf.d/20-curl.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/dom.ini /etc/php/7.4/apache2/conf.d/20-dom.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/exif.ini /etc/php/7.4/apache2/conf.d/20-exif.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/fileinfo.ini /etc/php/7.4/apache2/conf.d/20-fileinfo.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/ftp.ini /etc/php/7.4/apache2/conf.d/20-ftp.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/gd.ini /etc/php/7.4/apache2/conf.d/20-gd.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/gettext.ini  /etc/php/7.4/apache2/conf.d/20-gettext.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/gmp.ini /etc/php/7.4/apache2/conf.d/20-gmp.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/iconv.ini /etc/php/7.4/apache2/conf.d/20-iconv.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/intl.ini /etc/php/7.4/apache2/conf.d/20-intl.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/json.ini /etc/php/7.4/apache2/conf.d/20-json.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/ldap.ini /etc/php/7.4/apache2/conf.d/20-ldap.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/mbstring.ini /etc/php/7.4/apache2/conf.d/20-mbstring.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/memcache.ini /etc/php/7.4/apache2/conf.d/20-memcache.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/mongodb.ini /etc/php/7.4/apache2/conf.d/20-mongodb.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/opcache.ini /etc/php/7.4/apache2/conf.d/20-opcache.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/pdo.ini /etc/php/7.4/apache2/conf.d/20-pdo.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/phar.ini /etc/php/7.4/apache2/conf.d/20-phar.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/posix.ini /etc/php/7.4/apache2/conf.d/20-posix.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/readline.ini /etc/php/7.4/apache2/conf.d/20-readline.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/shmop.ini /etc/php/7.4/apache2/conf.d/20-shmop.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/simplexml.ini  /etc/php/7.4/apache2/conf.d/20-simplexml.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sockets.ini /etc/php/7.4/apache2/conf.d/20-sockets.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sysvmsg.ini /etc/php/7.4/apache2/conf.d/20-sysvmsg.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sysvsem.ini /etc/php/7.4/apache2/conf.d/20-sysvsem.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sysvshm.ini /etc/php/7.4/apache2/conf.d/sysvshm.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/tokenizer.ini /etc/php/7.4/apache2/conf.d/20-tokenizer.ini 2>&1 | write_log
#ln -sfn /etc/php/7.4/mods-available/wddx.ini /etc/php/7.4/apache2/conf.d/20-wddx.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xml.ini /etc/php/7.4/apache2/conf.d/15-xml.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xmlreader.ini /etc/php/7.4/apache2/conf.d/20-xmlreader.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xmlwriter.ini /etc/php/7.4/apache2/conf.d/20-xmlwriter.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xsl.ini /etc/php/7.4/apache2/conf.d/20-xsl.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/zip.ini /etc/php/7.4/apache2/conf.d/20-zip.ini 2>&1 | write_log


apt-get -y install libmcrypt-dev 2>&1 | write_log
apt-get install php7.4-mcrypt -y | write_log
echo "extension=mcrypt.so" > /etc/php/7.4/mods-available/mcrypt.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/mcrypt.ini /etc/php/7.4/apache2/conf.d/20-mcrypt.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/mcrypt.ini /etc/php/7.4/cli/conf.d/20-mcrypt.ini 2>&1 | write_log


### Install MongoDB driver for PHP 7.2 ##############

echo -e "\n### Installing MongoDB PHP driver ##\n" 2>&1 | write_log
sudo apt-get install php-mongodb -y 2>&1 | write_log


### Verify installs #################################

echo -e "" 2>&1 | write_log > /dev/null
echo -e "###############################" 2>&1 | write_log > /dev/null
echo -e "### VERIFY THE OUTPUT BELOW ###" 2>&1 | write_log > /dev/null
echo -e "###############################" 2>&1 | write_log > /dev/null
echo -e "\n### PHP ###############\n" 2>&1 | write_log > /dev/null
echo -e "$(php -v)" 2>&1 | write_log > /dev/null

rm -rvf ${FC_INSTALL_DIR}/ioncubeinstall 2>&1 | write_log > /dev/null

}

###FILECLOUD DEB PACKAGE STRETCH###

deb_package_installer_stretch()
{

### Add all repositories ############################
sudo rm /var/lib/apt/lists/lock | write_log
sudo rm /var/cache/apt/archives/lock | write_log
sudo rm /var/lib/dpkg/lock* | write_log
sudo dpkg --configure -a | write_log

echo -e "\n### Adding PHP repository ###############\n" 2>&1 | write_log > /dev/null
sudo apt-get update -y
sudo apt-get install ca-certificates apt-transport-https lsb-release -y
sudo apt-get install software-properties-common -y
wget -q https://packages.sury.org/php/apt.gpg -O- | sudo apt-key add - 2>&1 | write_log > /dev/null
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/php.list 2>&1 | write_log

### Install Webserver ###################################

echo -e "\n### Installing apache #############\n" 2>&1 | write_log > /dev/null
sudo apt-get update -y 2>&1 | write_log > /dev/null
sudo apt-get install unzip curl rsync python  -y  2>&1 | write_log > /dev/null
sudo apt-get install apache2 build-essential libssl-dev pkg-config memcached -y 2>&1 | write_log


### Install PHP 7.1 #################################

sudo apt-get install php7.4 php7.4-cli php7.4-common php7.4-dev php-pear -y 2>&1 | write_log


#sudo apt-key list |  grep "expired: " |  sed -ne 's|pub .*/\([^ ]*\) .*|\1|gp' |  xargs -n1 sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 2>&1 | write_log
apt-get update -y 2>&1 | write_log

echo -e "\n### Installing PHP extensions ######\n" 2>&1 | write_log
apt-get install php7.4-json php7.4-opcache php7.4-mbstring php7.4-zip php7.4-memcache php7.4-xml php7.4-bcmath libapache2-mod-php7.4 php7.4-gd php7.4-curl php7.4-ldap php7.4-gmp php7.4-mongodb php7.4-intl php7.4-mongodb libreadline-dev php-pecl-http  libxml2-dev -y 2>&1 | write_log

apt-get upgrade -y 2>&1 | write_log

set +e

echo "* Enabling Apache PHP 7.4 module..." 2>&1 | write_log
sudo a2dismod php7.2 2>&1 | write_log
sudo a2enmod php7.4 2>&1 | write_log


echo "* Enabling Apache SSL and Header module..." 2>&1 | write_log

a2enmod headers
a2enmod ssl

echo "* Restarting Apache..." 2>&1 | write_log
sudo service apache2 restart 2>&1 | write_log > /dev/null

set +e
echo "* Switching CLI PHP to 7.4..." 2>&1 | write_log
sudo update-alternatives --set php /usr/bin/php7.4 2>&1 | write_log > /dev/null
sudo update-alternatives --set phar /usr/bin/phar7.4 2>&1 | write_log > /dev/null
sudo update-alternatives --set phar.phar /usr/bin/phar.phar7.4 2>&1 | write_log > /dev/null
sudo update-alternatives --set phpize /usr/bin/phpize7.4 2>&1 | write_log > /dev/null
sudo update-alternatives --set php-config /usr/bin/php-config7.4 2>&1 | write_log > /dev/null

echo "* Switch to PHP 7.4 complete." 2>&1 | write_log
set -e


mkdir -p /etc/php/7.4/apache2/conf.d/
find /etc/php/7.4/cli/conf.d/ -type l -exec unlink {} \;
find /etc/php/7.4/apache2/conf.d/ -type l -exec unlink {} \;
#CREATING PHP EXTENSION
echo "extension=bcmath.so" > /etc/php/7.4/mods-available/bcmath.ini
echo "extension=calendar.so" > /etc/php/7.4/mods-available/calendar.ini
echo "extension=ctype.so" > /etc/php/7.4/mods-available/ctype.ini
echo "extension=curl.so" > /etc/php/7.4/mods-available/curl.ini
echo "extension=dom.so" > /etc/php/7.4/mods-available/dom.ini
echo "extension=exif.so" > /etc/php/7.4/mods-available/exif.ini
echo "extension=fileinfo.so" > /etc/php/7.4/mods-available/fileinfo.ini
echo "extension=ftp.so" > /etc/php/7.4/mods-available/ftp.ini
echo "extension=gd.so" > /etc/php/7.4/mods-available/gd.ini
echo "extension=gettext.so" > /etc/php/7.4/mods-available/gettext.ini
echo "extension=gmp.so" > /etc/php/7.4/mods-available/gmp.ini
echo "extension=iconv.so" > /etc/php/7.4/mods-available/iconv.ini
echo "extension=intl.so" > /etc/php/7.4/mods-available/intl.ini
echo "extension=json.so" > /etc/php/7.4/mods-available/json.ini
echo "extension=ldap.so" > /etc/php/7.4/mods-available/ldap.ini
echo "extension=mbstring.so" > /etc/php/7.4/mods-available/mbstring.ini
echo "extension=memcache.so" > /etc/php/7.4/mods-available/memcache.ini
echo "extension=mongodb.so" > /etc/php/7.4/mods-available/mongodb.ini
echo "zend_extension=opcache.so" > /etc/php/7.4/mods-available/opcache.ini
echo "extension=pdo.so" > /etc/php/7.4/mods-available/pdo.ini
echo "extension=phar.so" > /etc/php/7.4/mods-available/phar.ini
echo "extension=posix.so" > /etc/php/7.4/mods-available/posix.ini
echo "extension=readline.so" > /etc/php/7.4/mods-available/readline.ini
echo "extension=shmop.so" > /etc/php/7.4/mods-available/shmop.ini
echo "extension=simplexml.so" > /etc/php/7.4/mods-available/simplexml.ini
echo "extension=sockets.so" > /etc/php/7.4/mods-available/sockets.ini
echo "extension=sysvmsg.so" > /etc/php/7.4/mods-available/sysvmsg.ini
echo "extension=sysvsem.so" > /etc/php/7.4/mods-available/sysvsem.ini
echo "extension=sysvshm.so" > /etc/php/7.4/mods-available/sysvshm.ini
echo "extension=tokenizer.so" > /etc/php/7.4/mods-available/tokenizer.ini
#echo "extension=wddx.so" > /etc/php/7.4/mods-available/wddx.ini
echo "extension=xml.so" > /etc/php/7.4/mods-available/xml.ini
echo "extension=xmlreader.so" > /etc/php/7.4/mods-available/xmlreader.ini
echo "extension=xmlwriter.so" > /etc/php/7.4/mods-available/xmlwriter.ini
echo "extension=xsl.so" > /etc/php/7.4/mods-available/xsl.ini
echo "extension=zip.so" > /etc/php/7.4/mods-available/zip.ini

#CLI SYMLINKS

ln -sfn /etc/php/7.4/mods-available/bcmath.ini /etc/php/7.4/cli/conf.d/20-bcmath.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/calendar.ini /etc/php/7.4/cli/conf.d/20-calendar.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/ctype.ini /etc/php/7.4/cli/conf.d/20-ctype.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/curl.ini /etc/php/7.4/cli/conf.d/20-curl.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/dom.ini /etc/php/7.4/cli/conf.d/20-dom.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/exif.ini /etc/php/7.4/cli/conf.d/20-exif.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/fileinfo.ini /etc/php/7.4/cli/conf.d/20-fileinfo.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/ftp.ini /etc/php/7.4/cli/conf.d/20-ftp.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/gd.ini /etc/php/7.4/cli/conf.d/20-gd.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/gettext.ini  /etc/php/7.4/cli/conf.d/20-gettext.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/gmp.ini /etc/php/7.4/cli/conf.d/20-gmp.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/iconv.ini /etc/php/7.4/cli/conf.d/20-iconv.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/intl.ini /etc/php/7.4/cli/conf.d/20-intl.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/json.ini /etc/php/7.4/cli/conf.d/20-json.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/ldap.ini /etc/php/7.4/cli/conf.d/20-ldap.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/mbstring.ini /etc/php/7.4/cli/conf.d/20-mbstring.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/memcache.ini /etc/php/7.4/cli/conf.d/20-memcache.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/mongodb.ini /etc/php/7.4/cli/conf.d/20-mongodb.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/opcache.ini /etc/php/7.4/cli/conf.d/20-opcache.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/pdo.ini /etc/php/7.4/cli/conf.d/20-pdo.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/phar.ini /etc/php/7.4/cli/conf.d/20-phar.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/posix.ini /etc/php/7.4/cli/conf.d/20-posix.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/readline.ini /etc/php/7.4/cli/conf.d/20-readline.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/shmop.ini /etc/php/7.4/cli/conf.d/20-shmop.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/simplexml.ini  /etc/php/7.4/cli/conf.d/20-simplexml.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sockets.ini /etc/php/7.4/cli/conf.d/20-sockets.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sysvmsg.ini /etc/php/7.4/cli/conf.d/20-sysvmsg.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sysvsem.ini /etc/php/7.4/cli/conf.d/20-sysvsem.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sysvshm.ini /etc/php/7.4/cli/conf.d/sysvshm.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/tokenizer.ini /etc/php/7.4/cli/conf.d/20-tokenizer.ini 2>&1 | write_log
#ln -sfn /etc/php/7.4/mods-available/wddx.ini /etc/php/7.4/cli/conf.d/20-wddx.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xml.ini /etc/php/7.4/cli/conf.d/15-xml.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xmlreader.ini /etc/php/7.4/cli/conf.d/20-xmlreader.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xmlwriter.ini /etc/php/7.4/cli/conf.d/20-xmlwriter.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xsl.ini /etc/php/7.4/cli/conf.d/20-xsl.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/zip.ini /etc/php/7.4/cli/conf.d/20-zip.ini 2>&1 | write_log
#ln -sfn /etc/php/7.4/mods-available/zmq.ini /etc/php/7.4/cli/conf.d/20-zmq.ini 2>&1 | write_log
#APACHE SYMLINKS
ln -sfn /etc/php/7.4/mods-available/bcmath.ini /etc/php/7.4/apache2/conf.d/20-bcmath.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/calendar.ini /etc/php/7.4/apache2/conf.d/20-calendar.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/ctype.ini /etc/php/7.4/apache2/conf.d/20-ctype.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/curl.ini /etc/php/7.4/apache2/conf.d/20-curl.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/dom.ini /etc/php/7.4/apache2/conf.d/20-dom.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/exif.ini /etc/php/7.4/apache2/conf.d/20-exif.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/fileinfo.ini /etc/php/7.4/apache2/conf.d/20-fileinfo.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/ftp.ini /etc/php/7.4/apache2/conf.d/20-ftp.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/gd.ini /etc/php/7.4/apache2/conf.d/20-gd.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/gettext.ini  /etc/php/7.4/apache2/conf.d/20-gettext.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/gmp.ini /etc/php/7.4/apache2/conf.d/20-gmp.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/iconv.ini /etc/php/7.4/apache2/conf.d/20-iconv.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/intl.ini /etc/php/7.4/apache2/conf.d/20-intl.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/json.ini /etc/php/7.4/apache2/conf.d/20-json.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/ldap.ini /etc/php/7.4/apache2/conf.d/20-ldap.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/mbstring.ini /etc/php/7.4/apache2/conf.d/20-mbstring.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/memcache.ini /etc/php/7.4/apache2/conf.d/20-memcache.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/mongodb.ini /etc/php/7.4/apache2/conf.d/20-mongodb.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/opcache.ini /etc/php/7.4/apache2/conf.d/20-opcache.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/pdo.ini /etc/php/7.4/apache2/conf.d/20-pdo.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/phar.ini /etc/php/7.4/apache2/conf.d/20-phar.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/posix.ini /etc/php/7.4/apache2/conf.d/20-posix.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/readline.ini /etc/php/7.4/apache2/conf.d/20-readline.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/shmop.ini /etc/php/7.4/apache2/conf.d/20-shmop.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/simplexml.ini  /etc/php/7.4/apache2/conf.d/20-simplexml.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sockets.ini /etc/php/7.4/apache2/conf.d/20-sockets.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sysvmsg.ini /etc/php/7.4/apache2/conf.d/20-sysvmsg.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sysvsem.ini /etc/php/7.4/apache2/conf.d/20-sysvsem.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sysvshm.ini /etc/php/7.4/apache2/conf.d/sysvshm.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/tokenizer.ini /etc/php/7.4/apache2/conf.d/20-tokenizer.ini 2>&1 | write_log
#ln -sfn /etc/php/7.4/mods-available/wddx.ini /etc/php/7.4/apache2/conf.d/20-wddx.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xml.ini /etc/php/7.4/apache2/conf.d/15-xml.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xmlreader.ini /etc/php/7.4/apache2/conf.d/20-xmlreader.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xmlwriter.ini /etc/php/7.4/apache2/conf.d/20-xmlwriter.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xsl.ini /etc/php/7.4/apache2/conf.d/20-xsl.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/zip.ini /etc/php/7.4/apache2/conf.d/20-zip.ini 2>&1 | write_log


apt-get -y install libmcrypt-dev 2>&1 | write_log
apt-get install php7.4-mcrypt -y | write_log
echo "extension=mcrypt.so" > /etc/php/7.4/mods-available/mcrypt.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/mcrypt.ini /etc/php/7.4/apache2/conf.d/20-mcrypt.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/mcrypt.ini /etc/php/7.4/cli/conf.d/20-mcrypt.ini 2>&1 | write_log


### Install MongoDB driver for PHP 7.2 ##############

echo -e "\n### Installing MongoDB PHP driver ##\n" 2>&1 | write_log
sudo apt-get install php-mongodb -y 2>&1 | write_log


### Verify installs #################################

echo -e "" 2>&1 | write_log > /dev/null
echo -e "###############################" 2>&1 | write_log > /dev/null
echo -e "### VERIFY THE OUTPUT BELOW ###" 2>&1 | write_log > /dev/null
echo -e "###############################" 2>&1 | write_log > /dev/null
echo -e "\n### PHP ###############\n" 2>&1 | write_log > /dev/null
echo -e "$(php -v)" 2>&1 | write_log > /dev/null

rm -rvf ${FC_INSTALL_DIR}/ioncubeinstall 2>&1 | write_log > /dev/null

}


deb_package_installer_buster()
{

### Add all repositories ############################
sudo rm /var/lib/apt/lists/lock | write_log
sudo rm /var/cache/apt/archives/lock | write_log
sudo rm /var/lib/dpkg/lock* | write_log
sudo dpkg --configure -a | write_log

echo -e "\n### Adding PHP repository ###############\n" 2>&1 | write_log > /dev/null
sudo apt-get update -y
sudo apt-get install ca-certificates apt-transport-https lsb-release language-pack-en  -y
sudo apt-get install software-properties-common -y
wget -q https://packages.sury.org/php/apt.gpg -O- | sudo apt-key add - 2>&1 | write_log > /dev/null
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/php.list 2>&1 | write_log

### Install Webserver ###################################

echo -e "\n### Installing apache #############\n" 2>&1 | write_log > /dev/null
sudo apt-get update -y 2>&1 | write_log > /dev/null
sudo apt-get install unzip curl rsync python  -y  2>&1 | write_log > /dev/null
sudo apt-get install apache2 build-essential libsslcommon2-dev libssl-dev pkg-config memcached -y 2>&1 | write_log


### Install PHP 7.1 #################################

sudo apt-get install php7.4 php7.4-cli php7.4-common php7.4-dev php-pear -y 2>&1 | write_log


sudo apt-key list |  grep "expired: " |  sed -ne 's|pub .*/\([^ ]*\) .*|\1|gp' |  xargs -n1 sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 2>&1 | write_log
apt-get update -y 2>&1 | write_log

echo -e "\n### Installing PHP extensions ######\n" 2>&1 | write_log
apt-get install php7.4-json php7.4-opcache php7.4-mbstring php7.4-zip php7.4-memcache php7.4-xml php7.4-bcmath libapache2-mod-php7.4 php7.4-gd php7.4-curl php7.4-ldap php7.4-gmp php7.4-mongodb php7.4-intl php7.4-mongodb libreadline-dev php-pecl-http  libxml2-dev -y 2>&1 | write_log

apt-get upgrade -y 2>&1 | write_log

set +e

echo "* Enabling Apache PHP 7.4 module..." 2>&1 | write_log
sudo a2dismod php7.2 2>&1 | write_log
sudo a2enmod php7.4 2>&1 | write_log


echo "* Enabling Apache SSL and Header module..." 2>&1 | write_log

a2enmod headers
a2enmod ssl

echo "* Restarting Apache..." 2>&1 | write_log
sudo service apache2 restart 2>&1 | write_log > /dev/null

set +e
echo "* Switching CLI PHP to 7.4..." 2>&1 | write_log
sudo update-alternatives --set php /usr/bin/php7.4 2>&1 | write_log > /dev/null
sudo update-alternatives --set phar /usr/bin/phar7.4 2>&1 | write_log > /dev/null
sudo update-alternatives --set phar.phar /usr/bin/phar.phar7.4 2>&1 | write_log > /dev/null
sudo update-alternatives --set phpize /usr/bin/phpize7.4 2>&1 | write_log > /dev/null
sudo update-alternatives --set php-config /usr/bin/php-config7.4 2>&1 | write_log > /dev/null

echo "* Switch to PHP 7.4 complete." 2>&1 | write_log
set -e


mkdir -p /etc/php/7.4/apache2/conf.d/
find /etc/php/7.4/cli/conf.d/ -type l -exec unlink {} \;
find /etc/php/7.4/apache2/conf.d/ -type l -exec unlink {} \;
#CREATING PHP EXTENSION
echo "extension=bcmath.so" > /etc/php/7.4/mods-available/bcmath.ini
echo "extension=calendar.so" > /etc/php/7.4/mods-available/calendar.ini
echo "extension=ctype.so" > /etc/php/7.4/mods-available/ctype.ini
echo "extension=curl.so" > /etc/php/7.4/mods-available/curl.ini
echo "extension=dom.so" > /etc/php/7.4/mods-available/dom.ini
echo "extension=exif.so" > /etc/php/7.4/mods-available/exif.ini
echo "extension=fileinfo.so" > /etc/php/7.4/mods-available/fileinfo.ini
echo "extension=ftp.so" > /etc/php/7.4/mods-available/ftp.ini
echo "extension=gd.so" > /etc/php/7.4/mods-available/gd.ini
echo "extension=gettext.so" > /etc/php/7.4/mods-available/gettext.ini
echo "extension=gmp.so" > /etc/php/7.4/mods-available/gmp.ini
echo "extension=iconv.so" > /etc/php/7.4/mods-available/iconv.ini
echo "extension=intl.so" > /etc/php/7.4/mods-available/intl.ini
echo "extension=json.so" > /etc/php/7.4/mods-available/json.ini
echo "extension=ldap.so" > /etc/php/7.4/mods-available/ldap.ini
echo "extension=mbstring.so" > /etc/php/7.4/mods-available/mbstring.ini
echo "extension=memcache.so" > /etc/php/7.4/mods-available/memcache.ini
echo "extension=mongodb.so" > /etc/php/7.4/mods-available/mongodb.ini
echo "zend_extension=opcache.so" > /etc/php/7.4/mods-available/opcache.ini
echo "extension=pdo.so" > /etc/php/7.4/mods-available/pdo.ini
echo "extension=phar.so" > /etc/php/7.4/mods-available/phar.ini
echo "extension=posix.so" > /etc/php/7.4/mods-available/posix.ini
echo "extension=readline.so" > /etc/php/7.4/mods-available/readline.ini
echo "extension=shmop.so" > /etc/php/7.4/mods-available/shmop.ini
echo "extension=simplexml.so" > /etc/php/7.4/mods-available/simplexml.ini
echo "extension=sockets.so" > /etc/php/7.4/mods-available/sockets.ini
echo "extension=sysvmsg.so" > /etc/php/7.4/mods-available/sysvmsg.ini
echo "extension=sysvsem.so" > /etc/php/7.4/mods-available/sysvsem.ini
echo "extension=sysvshm.so" > /etc/php/7.4/mods-available/sysvshm.ini
echo "extension=tokenizer.so" > /etc/php/7.4/mods-available/tokenizer.ini
#echo "extension=wddx.so" > /etc/php/7.4/mods-available/wddx.ini
echo "extension=xml.so" > /etc/php/7.4/mods-available/xml.ini
echo "extension=xmlreader.so" > /etc/php/7.4/mods-available/xmlreader.ini
echo "extension=xmlwriter.so" > /etc/php/7.4/mods-available/xmlwriter.ini
echo "extension=xsl.so" > /etc/php/7.4/mods-available/xsl.ini
echo "extension=zip.so" > /etc/php/7.4/mods-available/zip.ini

#CLI SYMLINKS

ln -sfn /etc/php/7.4/mods-available/bcmath.ini /etc/php/7.4/cli/conf.d/20-bcmath.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/calendar.ini /etc/php/7.4/cli/conf.d/20-calendar.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/ctype.ini /etc/php/7.4/cli/conf.d/20-ctype.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/curl.ini /etc/php/7.4/cli/conf.d/20-curl.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/dom.ini /etc/php/7.4/cli/conf.d/20-dom.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/exif.ini /etc/php/7.4/cli/conf.d/20-exif.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/fileinfo.ini /etc/php/7.4/cli/conf.d/20-fileinfo.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/ftp.ini /etc/php/7.4/cli/conf.d/20-ftp.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/gd.ini /etc/php/7.4/cli/conf.d/20-gd.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/gettext.ini  /etc/php/7.4/cli/conf.d/20-gettext.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/gmp.ini /etc/php/7.4/cli/conf.d/20-gmp.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/iconv.ini /etc/php/7.4/cli/conf.d/20-iconv.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/intl.ini /etc/php/7.4/cli/conf.d/20-intl.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/json.ini /etc/php/7.4/cli/conf.d/20-json.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/ldap.ini /etc/php/7.4/cli/conf.d/20-ldap.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/mbstring.ini /etc/php/7.4/cli/conf.d/20-mbstring.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/memcache.ini /etc/php/7.4/cli/conf.d/20-memcache.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/mongodb.ini /etc/php/7.4/cli/conf.d/20-mongodb.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/opcache.ini /etc/php/7.4/cli/conf.d/20-opcache.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/pdo.ini /etc/php/7.4/cli/conf.d/20-pdo.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/phar.ini /etc/php/7.4/cli/conf.d/20-phar.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/posix.ini /etc/php/7.4/cli/conf.d/20-posix.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/readline.ini /etc/php/7.4/cli/conf.d/20-readline.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/shmop.ini /etc/php/7.4/cli/conf.d/20-shmop.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/simplexml.ini  /etc/php/7.4/cli/conf.d/20-simplexml.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sockets.ini /etc/php/7.4/cli/conf.d/20-sockets.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sysvmsg.ini /etc/php/7.4/cli/conf.d/20-sysvmsg.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sysvsem.ini /etc/php/7.4/cli/conf.d/20-sysvsem.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sysvshm.ini /etc/php/7.4/cli/conf.d/sysvshm.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/tokenizer.ini /etc/php/7.4/cli/conf.d/20-tokenizer.ini 2>&1 | write_log
#ln -sfn /etc/php/7.4/mods-available/wddx.ini /etc/php/7.4/cli/conf.d/20-wddx.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xml.ini /etc/php/7.4/cli/conf.d/15-xml.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xmlreader.ini /etc/php/7.4/cli/conf.d/20-xmlreader.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xmlwriter.ini /etc/php/7.4/cli/conf.d/20-xmlwriter.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xsl.ini /etc/php/7.4/cli/conf.d/20-xsl.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/zip.ini /etc/php/7.4/cli/conf.d/20-zip.ini 2>&1 | write_log
#ln -sfn /etc/php/7.4/mods-available/zmq.ini /etc/php/7.4/cli/conf.d/20-zmq.ini 2>&1 | write_log
#APACHE SYMLINKS
ln -sfn /etc/php/7.4/mods-available/bcmath.ini /etc/php/7.4/apache2/conf.d/20-bcmath.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/calendar.ini /etc/php/7.4/apache2/conf.d/20-calendar.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/ctype.ini /etc/php/7.4/apache2/conf.d/20-ctype.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/curl.ini /etc/php/7.4/apache2/conf.d/20-curl.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/dom.ini /etc/php/7.4/apache2/conf.d/20-dom.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/exif.ini /etc/php/7.4/apache2/conf.d/20-exif.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/fileinfo.ini /etc/php/7.4/apache2/conf.d/20-fileinfo.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/ftp.ini /etc/php/7.4/apache2/conf.d/20-ftp.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/gd.ini /etc/php/7.4/apache2/conf.d/20-gd.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/gettext.ini  /etc/php/7.4/apache2/conf.d/20-gettext.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/gmp.ini /etc/php/7.4/apache2/conf.d/20-gmp.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/iconv.ini /etc/php/7.4/apache2/conf.d/20-iconv.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/intl.ini /etc/php/7.4/apache2/conf.d/20-intl.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/json.ini /etc/php/7.4/apache2/conf.d/20-json.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/ldap.ini /etc/php/7.4/apache2/conf.d/20-ldap.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/mbstring.ini /etc/php/7.4/apache2/conf.d/20-mbstring.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/memcache.ini /etc/php/7.4/apache2/conf.d/20-memcache.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/mongodb.ini /etc/php/7.4/apache2/conf.d/20-mongodb.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/opcache.ini /etc/php/7.4/apache2/conf.d/20-opcache.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/pdo.ini /etc/php/7.4/apache2/conf.d/20-pdo.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/phar.ini /etc/php/7.4/apache2/conf.d/20-phar.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/posix.ini /etc/php/7.4/apache2/conf.d/20-posix.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/readline.ini /etc/php/7.4/apache2/conf.d/20-readline.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/shmop.ini /etc/php/7.4/apache2/conf.d/20-shmop.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/simplexml.ini  /etc/php/7.4/apache2/conf.d/20-simplexml.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sockets.ini /etc/php/7.4/apache2/conf.d/20-sockets.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sysvmsg.ini /etc/php/7.4/apache2/conf.d/20-sysvmsg.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sysvsem.ini /etc/php/7.4/apache2/conf.d/20-sysvsem.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/sysvshm.ini /etc/php/7.4/apache2/conf.d/sysvshm.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/tokenizer.ini /etc/php/7.4/apache2/conf.d/20-tokenizer.ini 2>&1 | write_log
#ln -sfn /etc/php/7.4/mods-available/wddx.ini /etc/php/7.4/apache2/conf.d/20-wddx.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xml.ini /etc/php/7.4/apache2/conf.d/15-xml.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xmlreader.ini /etc/php/7.4/apache2/conf.d/20-xmlreader.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xmlwriter.ini /etc/php/7.4/apache2/conf.d/20-xmlwriter.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/xsl.ini /etc/php/7.4/apache2/conf.d/20-xsl.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/zip.ini /etc/php/7.4/apache2/conf.d/20-zip.ini 2>&1 | write_log


apt-get -y install libmcrypt-dev 2>&1 | write_log
apt-get install php7.4-mcrypt -y | write_log
echo "extension=mcrypt.so" > /etc/php/7.4/mods-available/mcrypt.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/mcrypt.ini /etc/php/7.4/apache2/conf.d/20-mcrypt.ini 2>&1 | write_log
ln -sfn /etc/php/7.4/mods-available/mcrypt.ini /etc/php/7.4/cli/conf.d/20-mcrypt.ini 2>&1 | write_log


### Install MongoDB driver for PHP 7.2 ##############

echo -e "\n### Installing MongoDB PHP driver ##\n" 2>&1 | write_log
sudo apt-get install php-mongodb -y 2>&1 | write_log


### Verify installs #################################

echo -e "" 2>&1 | write_log > /dev/null
echo -e "###############################" 2>&1 | write_log > /dev/null
echo -e "### VERIFY THE OUTPUT BELOW ###" 2>&1 | write_log > /dev/null
echo -e "###############################" 2>&1 | write_log > /dev/null
echo -e "\n### PHP ###############\n" 2>&1 | write_log > /dev/null
echo -e "$(php -v)" 2>&1 | write_log > /dev/null

rm -rvf ${FC_INSTALL_DIR}/ioncubeinstall 2>&1 | write_log > /dev/null

}

deb_ioncube_installer()
{
  echo -e "\n### Installing IONCUBE PHP driver ##\n" 2>&1 | write_log > /dev/null
echo "* Removing previous Ioncube Downloads..." 2>&1 | write_log
rm -rvf /tmp/ioncubeinstall/ 2>&1 | write_log
mkdir -p ${FC_INSTALL_DIR}/ioncubeinstall && cd "$_"
wget https://patch.codelathe.com/tonidocloud/live/ioncube/ioncube_10_4_5_loaders_lin_x86-64.zip
echo "* Ioncube Downloaded Successfully..." 2>&1 | write_log
unzip ioncube_10_4_5_loaders_lin_x86-64.zip 2>&1 | write_log
echo -e "\n### COPYING IONCUBE ##\n" 2>&1 | write_log > /dev/null
cp -rvf ${FC_INSTALL_DIR}/ioncubeinstall/ioncube /usr/lib/php/7.4/ 2>&1 | write_log > /dev/null
echo "zend_extension = '/usr/lib/php/7.4/ioncube/ioncube_loader_lin_7.4.so'" > /etc/php/7.4/mods-available/01-ioncube.ini 2>&1 | write_log > /dev/null
ln -sfn /etc/php/7.4/mods-available/01-ioncube.ini /etc/php/7.4/apache2/conf.d/  2>&1 | write_log > /dev/null
ln -sfn /etc/php/7.4/mods-available/01-ioncube.ini /etc/php/7.4/cli/conf.d/  2>&1 | write_log > /dev/null
echo -e "\n### IONCUBE PHP driver Installed Successfully##\n" 2>&1 | write_log > /dev/null
}
filecloud_deb_installer()
{
mkdir -p ${FC_INSTALL_DIR}/tmp/cloudinstall
cd ${FC_INSTALL_DIR}/tmp/cloudinstall
{
wget -N "${DEB_INSTALLER_URL}" 2>&1 | \
stdbuf -o0 awk '/[.] +[0-9][0-9]?[0-9]?%/ { print substr($0,63,3) }'
} | whiptail --gauge "Downloading FileCloud" 7 60 0
echo " Running Filecloud Package verifier"  | write_log
echo "status2: $?" >> /var/log/test.txt
fc_package_verification
tar -xzvf file_cloud_deb.tgz 2>&1 | write_log
dpkg -i ./filecloud.deb 2>&1 | write_log
cd
rm -rvf ${FC_INSTALL_DIR}/tmp/cloudinstall 2>&1 | write_log
echo "status2: $?" >> /var/log/test.txt
}

install_fc_deb()
{
os_check_deb=$(lsb_release -c | awk '{print $2}' |  tr -d '"')
supported_os_deb=('xenial','bionic','focal','buster','stretch')
if [[ ${supported_os_deb[*]} =~ ${os_check_deb} ]];then
  echo " Supported OS $os_check_deb found" | write_log
echo "status2: $?" >> /var/log/test.txt
 if [[ $os_check_deb == xenial ]]; then
deb_package_installer_xenial
echo "status2: $?" >> /var/log/test.txt
deb_ioncube_installer
mongodb_installer
echo "$os_name: $?" >> /var/log/test.txt
filecloud_deb_installer
echo "$os_name: $?" >> /var/log/test.txt

fi

if [[ $os_check_deb == bionic ]]; then
deb_package_installer_bionic
deb_ioncube_installer
mongodb_installer
echo "$os_name: $?" >> /var/log/test.txt
filecloud_deb_installer
echo "$os_name: $?" >> /var/log/test.txt
fi

if [[ $os_check_deb == focal ]]; then
deb_package_installer_focal
deb_ioncube_installer
mongodb_installer
echo "$os_name: $?" >> /var/log/test.txt
filecloud_deb_installer
echo "$os_name: $?" >> /var/log/test.txt
fi

if [[ $os_check_deb == buster ]]; then
deb_package_installer_buster
deb_ioncube_installer
mongodb_installer
echo "$os_name: $?" >> /var/log/test.txt
filecloud_deb_installer
echo "$os_name: $?" >> /var/log/test.txt
fi

if [[ $os_name == stretch ]]; then
deb_package_installer_stretch
deb_ioncube_installer
mongodb_installer
echo "$os_name: $?" >> /var/log/test.txt
filecloud_deb_installer
echo "$os_name: $?" >> /var/log/test.txt
fi

fi

}

deb_installer()
{

mkdir -p ${FC_INSTALL_DIR}/tmp
touch ${FC_INSTALL_DIR}/tmp/fcinstall.lck
echo "Installing Depedency Packages" 2>&1 | write_log
install_fc_deb
nodejs_setup
filecloud_orch
docconvertor_installer
restart_services
binary_file
filecloud_cron
fc_permission_fix
chmod -R 777 /var/www/html/thirdparty/prop
update_clouddb
cd
rm -rvf ${FC_INSTALL_DIR}/tmp/cloudinstall 2>&1 | write_log
}

###################################################################################################################
##################################FILECLOUD DEB PACKAGE INSTALLER ENDS HERE########################################
###################################################################################################################

###################################################################################################################
##################################FILECLOUD RPM PACKAGE INSTALLER STARTS HERE######################################
###################################################################################################################

rpm_package_installer()
{
if [[ -n "$(command -v yum)" ]]; then
a=$(cat /etc/os-release |  grep '^ID=' | awk -F\= '{print $2}' | tr -d '"')
 var=$(cat /etc/os-release |  grep '^VERSION_ID' | awk -F\= '{print $2}' | tr -d '"')
 b=${var%\.*}
 os_check_rpm="${a}${b}"


supported_os_rpm=('rhel8','rhel7','centos7')

if [[ ${supported_os_rpm[*]} =~ ${os_check_rpm} ]];then
   if [[ $os_check_rpm == rhel8 ]]; then

echo " Detected RHEL8 installation"
yum update -y
yum install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm -y
yum install https://rpms.remirepo.net/enterprise/remi-release-8.rpm -y
dnf module enable php:remi-7.4 -y
yum install -y httpd mod_ssl php php-common php-gd php-pear php-devel  php-cli php-zip php-devel php-gd php-mcrypt php-mbstring php-curl php-xml php-pear php-bcmath php-json php-mbstring php-xml php-curl php-intl php-ldap php-pecl-memcached php-gmp php-pecl-mongodb gcc make patch memcached openssl-devel wget unzip php74-php-pecl-memcache
echo "Securing Memcache" 2>&1 | write_log
sed -i -e "s/^OPTIONS/#OPTIONS/" /etc/sysconfig/memcached 2>&1 | write_log
echo 'OPTIONS="-l 127.0.0.1 -U 0"' >> /etc/sysconfig/memcached 2>&1 | write_log
systemctl enable memcached 2>&1 | write_log
systemctl start memcached 2>&1 | write_log
cp /opt/remi/php74/root/usr/lib64/php/modules/memcache.so /usr/lib64/php/modules/
echo "extension=memcache.so " > /etc/php.d/memcache.ini
service httpd restart
 fi

 if [[ $os_check_rpm == rhel7 ]]; then
echo " Detected RHEL7 installation"
yum update -y
rm -rf /etc/yum.repos.d/remi.repo
rm -rf /etc/yum.repos.d/webtatic*
rpm -ivh https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm 2>&1 | write_log
rpm --import https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-7 2>&1 | write_log
rpm -ivh https://rpms.remirepo.net/enterprise/remi-release-7.rpm
rpm --import https://rpms.remirepo.net/RPM-GPG-KEY-remi
yum install yum-utils -y
yum-config-manager --enable remi-php74 -y
yum update -y
yum install -y httpd mod_ssl php php-common php-gd php-pear php-devel  php-cli php-zip php-devel php-gd php-mcrypt php-mbstring php-curl php-xml php-pear php-bcmath php-json php-mbstring php-xml php-curl php-intl php-ldap php-pecl-memcached php-gmp php-pecl-mongodb gcc make patch memcached openssl-devel wget unzip php74-php-pecl-memcache
echo "Securing Memcache" 2>&1 | write_log
sed -i -e "s/^OPTIONS/#OPTIONS/" /etc/sysconfig/memcached 2>&1 | write_log
echo 'OPTIONS="-l 127.0.0.1 -U 0"' >> /etc/sysconfig/memcached 2>&1 | write_log
systemctl enable memcached 2>&1 | write_log
systemctl start memcached 2>&1 | write_log
cp /opt/remi/php74/root/usr/lib64/php/modules/memcache.so /usr/lib64/php/modules/
echo "extension=memcache.so " > /etc/php.d/memcache.ini
service httpd restart
 fi

  if [[ $os_check_rpm == centos7 ]]; then
echo " Detected RHEL7 installation"
yum update -y
rm -rf /etc/yum.repos.d/remi.repo
rm -rf /etc/yum.repos.d/webtatic*
rpm -ivh https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm 2>&1 | write_log
rpm --import https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-7 2>&1 | write_log
rpm -ivh https://rpms.remirepo.net/enterprise/remi-release-7.rpm
rpm --import https://rpms.remirepo.net/RPM-GPG-KEY-remi
yum install yum-utils -y
yum-config-manager --enable remi-php74 -y
yum update -y
yum install -y httpd mod_ssl php php-common php-gd php-pear php-devel  php-cli php-zip php-devel php-gd php-mcrypt php-mbstring php-curl php-xml php-pear php-bcmath php-json php-mbstring php-xml php-curl php-intl php-ldap php-pecl-memcached php-gmp php-pecl-mongodb gcc make patch memcached openssl-devel wget unzip php74-php-pecl-memcache
echo "Securing Memcache" 2>&1 | write_log
sed -i -e "s/^OPTIONS/#OPTIONS/" /etc/sysconfig/memcached 2>&1 | write_log
echo 'OPTIONS="-l 127.0.0.1 -U 0"' >> /etc/sysconfig/memcached 2>&1 | write_log
systemctl enable memcached 2>&1 | write_log
systemctl start memcached 2>&1 | write_log
cp /opt/remi/php74/root/usr/lib64/php/modules/memcache.so /usr/lib64/php/modules/
echo "extension=memcache.so " > /etc/php.d/memcache.ini
service httpd restart
 fi
echo -e "${GREEN}Found the supporting OS for FileCloud Installation - $os_name${NOCOLOR}"
else
echo -e "${RED}Exiting Installation - Found non supporting OS for FileCloud installation - $os_name${NOCOLOR}"
exit 0
fi

 fi
}

rpm_ioncube_installer()
{
mkdir -p ${FC_INSTALL_DIR}/ioncubeinstall && cd "$_"
wget https://patch.codelathe.com/tonidocloud/live/ioncube/ioncube_10_4_5_loaders_lin_x86-64.zip  2>&1 | write_log
unzip ioncube_10_4_5_loaders_lin_x86-64.zip 2>&1 | write_log
rm -rvf /usr/lib64/php/modules/ioncube_loader_lin_* /etc/php.d/*ioncube.ini 2>&1 | write_log
mkdir -p /usr/lib64/php/modules/ioncube
cp -rvf ${FC_INSTALL_DIR}/ioncubeinstall/ioncube/ioncube_loader_lin_7.4.so /usr/lib64/php/modules/ioncube 2>&1 | write_log
echo "zend_extension = '/usr/lib64/php/modules/ioncube/ioncube_loader_lin_7.4.so'" > /etc/php.d/01-ioncube.ini 2>&1 | write_log
service httpd restart
}

filecloud_rpm_installer()
{
  mkdir -p ${FC_INSTALL_DIR}/tmp/cloudinstall
cd ${FC_INSTALL_DIR}/tmp/cloudinstall
{
wget -N "${RPM_INSTALLER_URL}" 2>&1 | \
stdbuf -o0 awk '/[.] +[0-9][0-9]?[0-9]?%/ { print substr($0,63,3) }'
} | whiptail --gauge "Downloading FileCloud" 7 60 0
echo " Running Filecloud Package verifier"  | write_log
fc_package_verification
tar -xzvf file_cloud_rpm.tgz
echo "Installing FileCloud package"  2>&1 | write_log
yum -y --nogpgcheck localinstall filecloud-*.rpm 2>&1 | write_log
echo "Configuring filecloud..."  2>&1 | write_log
bash /tmp/filecloud/config.sh  2>&1 | write_log
}

rpm_installer()
{


mkdir -p ${FC_INSTALL_DIR}/tmp
touch ${FC_INSTALL_DIR}/tmp/fcinstall.lck
rpm_package_installer
mongodb_installer
filecloud_rpm_installer
rpm_ioncube_installer
nodejs_setup
filecloud_orch
docconvertor_installer
restart_services
binary_file
filecloud_cron
fc_permission_fix
fwserule
chmod -R 777 /var/www/html/thirdparty/prop
update_clouddb
cd
rm -rvf ${FC_INSTALL_DIR}/tmp/cloudinstall 2>&1 | write_log
}

###################################################################################################################
##################################FILECLOUD RPM PACKAGE INSTALLER ENDS HERE########################################
###################################################################################################################


if [ -n "$(command -v yum)" ]; then
dependency_check_rpm
rpm_installer
fi

if [ -n "$(command -v apt-get)" ]; then
dependency_check_deb
deb_installer
fi