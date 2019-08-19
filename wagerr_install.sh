#!/bin/bash

TMP_FOLDER=$(mktemp -d)
CONFIG_FILE='wagerr.conf'
CONFIGFOLDER='/root/.wagerr'
COIN_DAEMON='wagerrd'
COIN_CLI='wagerr-cli'
COIN_PATH='/usr/local/bin/'
COIN_REPO='https://github.com/wagerr/wagerr.git'
COIN_TGZ='https://github.com/wagerr/wagerr/releases/download/v3.0.1/wagerr-3.0.1-x86_64-linux-gnu.tar.gz'
COIN_BOOTSTRAP='https://github.com/wagerr/Wagerr-Blockchain-Snapshots/releases/download/Block-764608/Snapshot-764608.7z'
COIN_BOOTSTRAP_ZIP=$(echo $COIN_BOOTSTRAP | awk -F'/' '{print $NF}')
COIN_BOOTSTRAP_ZIP_FOLDER='/root/Snapshot-764608'
COIN_FOLDER='/root/wagerr-3.0.1/bin'
COIN_ZIP=$(echo $COIN_TGZ | awk -F'/' '{print $NF}')
COIN_NAME='wagerr'
COIN_PORT=55002


NODEIP=$(curl -s4 icanhazip.com)


RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
swapon -s
echo "/swapfile none swap sw 0 0" >> /etc/fstab

#echo "Enter alias for new node."
   echo -e "${YELLOW}输入新节点别名.${NC}"
   read ALIAS1

function purgeOldInstallation() {
    echo -e "${GREEN}Searching and removing old $COIN_NAME files and configurations${NC}"
    #kill wallet daemon
    systemctl stop $COIN_NAME.service > /dev/null 2>&1
    sudo killall $COIN_DAEMON > /dev/null 2>&1
#	# Save Key 
#	OLDKEY=$(awk -F'=' '/masternodeprivkey/ {print $2}' $CONFIGFOLDER/$CONFIG_FILE 2> /dev/null)
#	if [ "$?" -eq "0" ]; then
#    		echo -e "${CYAN}Saving Old Installation Genkey${NC}"
#		echo -e $OLDKEY
#    echo -e "Please copy your old genkey and press enter. (Needed in later step)"
#    read -e ENTER
#	fi
    #remove old ufw port allow
    sudo ufw delete allow $COIN_PORT/tcp > /dev/null 2>&1
    #remove old files
    rm -- "$0" > /dev/null 2>&1
    sudo rm -rf $CONFIGFOLDER > /dev/null 2>&1
    sudo rm -rf /usr/local/bin/$COIN_CLI /usr/local/bin/$COIN_DAEMON> /dev/null 2>&1
    sudo rm -rf /usr/bin/$COIN_CLI /usr/bin/$COIN_DAEMON > /dev/null 2>&1
    sudo rm -rf /tmp/*
    echo -e "${GREEN}* Done${NONE}";
}

function download_node() {
  echo -e "${GREEN}Downloading and Installing VPS $COIN_NAME Daemon${NC}"
  cd $TMP_FOLDER >/dev/null 2>&1
  rm $COIN_ZIP >/dev/null 2>&1
  wget -q $COIN_TGZ
  wget -q $COIN_BOOTSTRAP
  compile_error
  tar xvzf $COIN_ZIP >/dev/null 2>&1
  tar xvzf $COIN_BOOTSTRAP_ZIP >/dev/null 2>&1
  mkdir $CONFIGFOLDER >/dev/null 2>&1
  cd $COIN_BOOTSTRAP_ZIP_FOLDER
  cp *.* $CONFIGFOLDER
  rm $COIN_BOOTSTRAP_ZIP >/dev/null 2>&1
  cd $COIN_FOLDER
  chmod +x $COIN_DAEMON $COIN_CLI
  compile_error
  cp $COIN_DAEMON $COIN_CLI $COIN_PATH
  cd - >/dev/null 2>&1
  clear
}


function configure_systemd() {
  cat << EOF > /etc/systemd/system/$COIN_NAME.service
[Unit]
Description=$COIN_NAME service
After=network.target
[Service]
User=root
Group=root
Type=forking
#PIDFile=$CONFIGFOLDER/$COIN_NAME.pid
ExecStart=$COIN_PATH$COIN_DAEMON -daemon -conf=$CONFIGFOLDER/$CONFIG_FILE -datadir=$CONFIGFOLDER
ExecStop=-$COIN_PATH_$COIN_CLI -conf=$CONFIGFOLDER/$CONFIG_FILE -datadir=$CONFIGFOLDER stop
Restart=always
PrivateTmp=true
TimeoutStopSec=60s
TimeoutStartSec=10s
StartLimitInterval=120s
StartLimitBurst=5
[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  sleep 3
  systemctl start $COIN_NAME.service
  systemctl enable $COIN_NAME.service >/dev/null 2>&1

  if [[ -z "$(ps axo cmd:100 | egrep $COIN_DAEMON)" ]]; then
    echo -e "${RED}$COIN_NAME is not running${NC}, please investigate. You should start by running the following commands as root:"
    echo -e "${GREEN}systemctl start $COIN_NAME.service"
    echo -e "systemctl status $COIN_NAME.service"
    echo -e "less /var/log/syslog${NC}"
    exit 1
  fi
}


function create_config() {
  mkdir $CONFIGFOLDER >/dev/null 2>&1
  RPCUSER=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)
  RPCPASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 20 | head -n 1)
  cat << EOF > $CONFIGFOLDER/$CONFIG_FILE
rpcuser=$RPCUSER
rpcpassword=$RPCPASSWORD
rpcallowip=127.0.0.1
listen=1
server=1
daemon=1
port=$COIN_PORT
EOF
}

function create_key() {
#  echo -e "Enter your ${RED}$COIN_NAME Masternode Private Key${NC}. Leave it blank to generate a new ${RED}Masternode Private Key${NC} for you:"
#  read -e COINKEY
  if [[ -z "$COINKEY" ]]; then
  $COIN_DAEMON -daemon
  sleep 30
  if [ -z "$(ps axo cmd:100 | grep $COIN_DAEMON)" ]; then
   echo -e "${RED}$COIN_NAME server couldn not start. Check /var/log/syslog for errors.{$NC}"
   exit 1
  fi
  COINKEY=$($COIN_CLI createmasternodekey)
  if [ "$?" -gt "0" ];
    then
    echo -e "${RED}Wallet not fully loaded. Let us wait and try again to generate the Private Key${NC}"
    sleep 30
    COINKEY=$($COIN_CLI createmasternodekey)
  fi
  $COIN_CLI stop
fi
clear
}

function update_config() {
#  sed -i 's/daemon=1/daemon=0/' $CONFIGFOLDER/$CONFIG_FILE
  cat << EOF >> $CONFIGFOLDER/$CONFIG_FILE
logintimestamps=1
maxconnections=256
masternode=1
bind=$NODEIP:$COIN_PORT
externalip=$NODEIP:$COIN_PORT
masternodeprivkey=$COINKEY
masternodeaddr=$NODEIP:$COIN_PORT
EOF
}


function enable_firewall() {
  echo -e "Installing and setting up firewall to allow ingress on port ${GREEN}$COIN_PORT${NC}"
  ufw allow $COIN_PORT/tcp comment "$COIN_NAME MN port" >/dev/null
  #ufw allow $RPCPORT/tcp comment "$COIN_NAME RPC port" >/dev/null
  ufw allow ssh comment "SSH" >/dev/null 2>&1
  ufw limit ssh/tcp >/dev/null 2>&1
  ufw default allow outgoing >/dev/null 2>&1
  echo "y" | ufw enable >/dev/null 2>&1
}



function get_ip() {
  declare -a NODE_IPS
  for ips in $(netstat -i | awk '!/Kernel|Iface|lo/ {print $1," "}')
  do
    NODE_IPS+=($(curl --interface $ips --connect-timeout 2 -s4 icanhazip.com))
  done

  if [ ${#NODE_IPS[@]} -gt 1 ]
    then
      echo -e "${GREEN}More than one IP. Please type 0 to use the first IP, 1 for the second and so on...${NC}"
      INDEX=0
      for ip in "${NODE_IPS[@]}"
      do
        echo ${INDEX} $ip
        let INDEX=${INDEX}+1
      done
      read -e choose_ip
      NODEIP=${NODE_IPS[$choose_ip]}
  else
    NODEIP=${NODE_IPS[0]}
  fi
}


function compile_error() {
if [ "$?" -gt "0" ];
 then
  echo -e "${RED}Failed to compile $COIN_NAME. Please investigate.${NC}"
  exit 1
fi
}


function checks() {
if [[ $(lsb_release -d) != *16.04* ]]; then
  echo -e "${RED}You are not running Ubuntu 16.04. Installation is cancelled.${NC}"
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}$0 must be run as root.${NC}"
   exit 1
fi

if [ -n "$(pidof $COIN_DAEMON)" ] || [ -e "$COIN_DAEMOM" ] ; then
  echo -e "${RED}$COIN_NAME is already installed.${NC}"
  exit 1
fi
}

function prepare_system() {
echo -e "Prepare the system to install ${GREEN}$COIN_NAME${NC} master node."
apt-get update >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get update > /dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y -qq upgrade >/dev/null 2>&1
apt install -y software-properties-common >/dev/null 2>&1
echo -e "${GREEN}Adding bitcoin PPA repository"
apt-add-repository -y ppa:bitcoin/bitcoin >/dev/null 2>&1
echo -e "Installing required packages, it may take some time to finish.${NC}"
apt-get update >/dev/null 2>&1
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" make software-properties-common \
build-essential libtool autoconf libssl-dev libboost-dev libboost-chrono-dev libboost-filesystem-dev libboost-program-options-dev \
libboost-system-dev libboost-test-dev libboost-thread-dev sudo automake git wget pwgen curl libdb4.8-dev bsdmainutils libdb4.8++-dev \
libminiupnpc-dev libgmp3-dev ufw pkg-config libevent-dev  libdb5.3++ unzip >/dev/null 2>&1
if [ "$?" -gt "0" ];
  then
    echo -e "${RED}Not all required packages were installed properly. Try to install them manually by running the following commands:${NC}\n"
    echo "apt-get update"
    echo "apt -y install software-properties-common"
    echo "apt-add-repository -y ppa:bitcoin/bitcoin"
    echo "apt-get update"
    echo "apt install -y make build-essential libtool software-properties-common autoconf libssl-dev libboost-dev libboost-chrono-dev libboost-filesystem-dev \
libboost-program-options-dev libboost-system-dev libboost-test-dev libboost-thread-dev sudo automake git pwgen curl libdb4.8-dev \
bsdmainutils libdb4.8++-dev libminiupnpc-dev libgmp3-dev ufw fail2ban pkg-config libevent-dev unzip"
 exit 1
fi

clear
}

function important_information() {
 echo
 echo -e "================================================================================================================================"
 echo -e "$COIN_NAME Masternode is up and running listening on port ${GREEN}$COIN_PORT${NC}."
 echo -e "Configuration file is: ${RED}$CONFIGFOLDER/$CONFIG_FILE${NC}"
 echo -e "Start: ${RED}systemctl start $COIN_NAME.service${NC}"
 echo -e "Stop: ${RED}systemctl stop $COIN_NAME.service${NC}"
 echo -e "VPS_IP:PORT ${RED}$NODEIP:$COIN_PORT${NC}"
 echo -e "MASTERNODE PRIVATEKEY is: ${RED}$COINKEY${NC}"
 echo -e "Please check ${GREEN}$COIN_NAME${NC} is running with the following command: ${GREEN}systemctl status $COIN_NAME.service${NC}"
 echo -e "${GREEN}复制下列节点配置信息并黏贴到本地钱包节点配置文件${NC}"
 echo -e "${GREEN}txhash 和 outputidx在本地钱包转25000WGR后到调试台输入 masternode outputs 得出${NC}"
 echo -e "${YELLOW}$ALIAS1 $NODEIP:$COIN_PORT $COINKEY "txhash" "outputidx"${NC}"
 echo -e "================================================================================================================================"
}

function setup_node() {
  get_ip
  create_config
  create_key
  update_config
  enable_firewall
  important_information
  configure_systemd
}


##### Main #####
clear
purgeOldInstallation
checks
prepare_system
download_node
setup_node
