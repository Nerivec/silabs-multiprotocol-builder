#!/bin/bash

die()
{
    echo >&2 " *** ERROR:  $*"
    exit 1
}

function parse_args()
{
    while [ $# -gt 0 ]; do
        case $1 in
            --zigbeed)
                INSTALL_ZIGBEED=1
                shift
                ;;
            --otbr)
                INSTALL_OTBR=1
                shift
                ;;
            --ot-cli)
                INSTALL_OT_CLI=1
                shift
                ;;
            --ble)
                INSTALL_BLE=1
                shift
                ;;
            --all)
                SKIP_INSTALL_CPCD=0
                INSTALL_ZIGBEED=1
                INSTALL_OTBR=1
                INSTALL_OT_CLI=1
                INSTALL_BLE=1
                shift
                ;;
            --skip-cpcd)
                SKIP_INSTALL_CPCD=1
                shift
                ;;
            --infra-if-name)
                INFRA_IF_NAME=$2
                shift
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
}

parse_args "$@"


# default installs only cpcd
[ -n "$SKIP_INSTALL_CPCD" ] || SKIP_INSTALL_CPCD=0
[ -n "$INSTALL_ZIGBEED" ] || INSTALL_ZIGBEED=0
[ -n "$INSTALL_OTBR" ] || INSTALL_OTBR=0
[ -n "$INSTALL_OT_CLI" ] || INSTALL_OT_CLI=0
[ -n "$INSTALL_BLE" ] || INSTALL_BLE=0
[ -n "$INFRA_IF_NAME" ] || INFRA_IF_NAME=$(ip -o -4 route show to default | awk '{print $5}')

echo "Using parameters:"
echo "--zigbeed $INSTALL_ZIGBEED"
echo "--otbr $INSTALL_OTBR"
echo "--ot-cli $INSTALL_OT_CLI"
echo "--ble $INSTALL_BLE"
echo "--skip-cpcd $SKIP_INSTALL_CPCD"
echo "--infra-if-name $INFRA_IF_NAME"

read -p "Proceed? (YES/no) " yn

[[ $yn == 'no' || $yn == 'n' || $yn == '0' ]] && echo "Cancelled" && exit

BASE_DIR=$PWD

CPCD_INSTALLED_TEST="/usr/local/bin/cpcd"
ZIGBEED_INSTALLED_TEST="/usr/local/bin/zigbeed"
OTBR_INSTALLED_TEST="/usr/sbin/otbr-agent"
OT_CLI_INSTALLED_TEST="/usr/local/bin/ot-cli"
BLE_INSTALLED_TEST="/usr/local/bin/cpc-hci-bridge"

function install_cpcd()
{
    if [ $SKIP_INSTALL_CPCD == 0 ]; then
        sudo test -f $CPCD_INSTALLED_TEST && echo "Detected CPCd already installed. Skipping." && return 0

        cd $BASE_DIR/cpcd || die "Missing CPCd installation files."
        echo "Installing CPCd from $PWD..."

        sudo cmake -P cmake_install.cmake
        # these are no longer symlinks, re-create them
        sudo ln -sf /usr/local/lib/libcpc.so.4.5.1.0 /usr/local/lib/libcpc.so.3
        sudo ln -sf /usr/local/lib/libcpc.so.3 /usr/local/lib/libcpc.so
        sudo cp -v $BASE_DIR/systemd/cpcd.service /etc/systemd/system/

        sudo ldconfig
        sudo systemctl enable cpcd || true
        sudo systemctl is-enabled cpcd || die "Failed to enable cpcd!"
        sudo systemctl daemon-reload
    else
        echo "Skipping CPCd installation... Note: This component is required by the others, make sure you have already installed it."
    fi
}

function install_zigbeed()
{
    if [ $INSTALL_ZIGBEED == 1 ]; then
        sudo test -f $ZIGBEED_INSTALLED_TEST && echo "Detected zigbeed already installed. Skipping." && return 0

        cd $BASE_DIR/zigbeed || die "Missing zigbeed installation files."
        echo "Installing zigbeed from $PWD..."

        sudo cp -v zigbeed /usr/local/bin/zigbeed
        sudo cp -v zigbeed.conf /usr/local/etc/zigbeed.conf
        sudo cp -v $BASE_DIR/systemd/zigbeed-socat.service /etc/systemd/system/
        sudo cp -v $BASE_DIR/systemd/zigbeed.service /etc/systemd/system/

        sudo ldconfig
        sudo systemctl enable zigbeed-socat || true
        sudo systemctl is-enabled zigbeed-socat || die "Failed to enable zigbeed-socat!"
        sudo systemctl enable zigbeed || true
        sudo systemctl is-enabled zigbeed || die "Failed to enable zigbeed!"
        sudo systemctl daemon-reload
    else
        echo "Skipping zigbeed installation..."
    fi
}

function install_otbr()
{
    if [ $INSTALL_OTBR == 1 ]; then
        sudo test -f $OTBR_INSTALLED_TEST && echo "Detected OTBR already installed. Skipping." && return 0
        # /usr/sbin/otbr-web

        cd $BASE_DIR/otbr || die "Missing OTBR installation files."
        echo "Installing OTBR from $PWD..."

        # mimic structure used in Docker container, which calls /app/script/server from docker_entrypoint.sh (otbr_entrypoint.sh)
        OTBR_SCRIPT_DIR="/app/script/"

        sudo mkdir -p $OTBR_SCRIPT_DIR
        sudo cp -v ./script/_initrc $OTBR_SCRIPT_DIR/_initrc
        sudo cp -v ./script/_nat64 $OTBR_SCRIPT_DIR/_nat64
        sudo cp -v ./script/_dns64 $OTBR_SCRIPT_DIR/_dns64
        sudo cp -v ./script/_firewall $OTBR_SCRIPT_DIR/_firewall
        sudo cp -v ./script/server $OTBR_SCRIPT_DIR/server
        sudo cp -v $BASE_DIR/systemd/otbr.service /etc/systemd/system/

        INFRA_IF_NAME=$INFRA_IF_NAME RELEASE=1 REFERENCE_DEVICE=1 BACKBONE_ROUTER=1 BORDER_ROUTING=1 NAT64=1 DNS64=1 WEB_GUI=1 REST_API=1 ./script/bootstrap

        sudo cmake -P cmake_install.cmake

        cd web || die "Missing OTBR Web installation files."
        sudo cmake -P cmake_install.cmake
        cd ..
        sudo cp -v otbr_entrypoint.sh /usr/local/bin/otbr_entrypoint.sh

        INFRA_IF_NAME=$INFRA_IF_NAME RELEASE=1 REFERENCE_DEVICE=1 BACKBONE_ROUTER=1 BORDER_ROUTING=1 NAT64=1 DNS64=1 WEB_GUI=1 REST_API=1 ./script/setup

        sudo cp -v pskc /usr/local/bin/pskc
        sudo cp -v steering-data /usr/local/bin/steering-data

        sudo ldconfig
        sudo systemctl reload dbus
        sudo systemctl daemon-reload
        sudo systemctl enable otbr-web || true
        sudo systemctl is-enabled otbr-web || die "Failed to enable otbr-web!"
        sudo systemctl enable otbr-agent || true
        sudo systemctl is-enabled otbr-agent || die "Failed to enable otbr-agent!"
        sudo systemctl enable otbr || true
        sudo systemctl is-enabled otbr || die "Failed to enable otbr!"

        # sudo systemctl enable testharness-discovery || true
        # sudo systemctl is-enabled testharness-discovery || die "Failed to enable otbr-agent!"

        # more config replacements
        sudo sed -i -e "s+/app/script/server+INFRA_IF_NAME=$INFRA_IF_NAME /app/script/server+g" /usr/local/bin/otbr_entrypoint.sh
        sudo sed -i -e "s+iid-list=0+iid-list=0 --backbone-interface $INFRA_IF_NAME+g" /etc/systemd/system/otbr.service

        sudo systemctl daemon-reload
    else
        echo "Skipping OTBR installation..."
    fi
}

function install_ot_cli()
{
    if [ $INSTALL_OT_CLI == 1 ]; then
        sudo test -f $OT_CLI_INSTALLED_TEST && echo "Detected ot-cli already installed. Skipping." && return 0
        # /usr/local/bin/ot-fct

        cd $BASE_DIR/ot-cli || die "Missing ot-cli installation files."
        echo "Installing ot-cli from $PWD..."

        sudo cmake -P cmake_install.cmake
        sudo cp -v ot-fct /usr/local/bin/ot-fct

        sudo ldconfig
        sudo systemctl daemon-reload
    else
        echo "Skipping ot-cli installation..."
    fi
}

function install_ble()
{
    if [ $INSTALL_BLE == 1 ]; then
        sudo test -f $BLE_INSTALLED_TEST && echo "Detected BLE already installed. Skipping." && return 0

        cd $BASE_DIR/ble || die "Missing BLE installation files."
        echo "Installing BLE from $PWD..."

        sudo apt-get install -y bluetooth bluez bluez-tools rfkill libbluetooth-dev
        # rename to match service
        sudo cp -v bt_host_cpc_hci_bridge /usr/local/bin/cpc-hci-bridge
        sudo cp -v $BASE_DIR/systemd/cpc-hci-bridge.service /etc/systemd/system/
        sudo cp -v $BASE_DIR/systemd/hciattach.service /etc/systemd/system/

        sudo ldconfig
        sudo systemctl enable bluetooth || true
        sudo systemctl is-enabled bluetooth || die "Failed to enable bluetooth!"
        sudo systemctl enable cpc-hci-bridge || true
        sudo systemctl is-enabled cpc-hci-bridge || die "Failed to enable cpc-hci-bridge!"
        sudo systemctl enable hciattach || true
        sudo systemctl is-enabled hciattach || die "Failed to enable hciattach!"

        # disable sys class check
        sudo sed -i -e "s+ConditionPathIsDirectory=/sys/class/bluetooth+#ConditionPathIsDirectory=/sys/class/bluetooth+g" /usr/lib/systemd/system/bluetooth.service

        sudo systemctl daemon-reload
    else
        echo "Skipping BLE installation..."
    fi
}

function pre_install()
{
    sudo apt-get install -y tar make cmake socat
}

function post_install()
{
    sudo test -f $CPCD_INSTALLED_TEST && echo "CPCd is installed."
    sudo test -f $ZIGBEED_INSTALLED_TEST && echo "zigbeed is installed."
    sudo test -f $OTBR_INSTALLED_TEST && echo "OTBR is installed."
    sudo test -f $OT_CLI_INSTALLED_TEST && echo "ot-cli is installed."
    sudo test -f $BLE_INSTALLED_TEST && echo "BLE is installed."

    return 0
}

pre_install
install_cpcd
install_zigbeed
install_otbr
install_ot_cli
install_ble
post_install

sudo ldconfig
sudo systemctl daemon-reload

echo "Please restart your machine to allow services to restart in proper order automatically."