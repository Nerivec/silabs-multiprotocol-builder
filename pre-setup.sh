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
            --device-path)
                DEVICE_PATH="$2"
                shift
                shift
                ;;
            --baudrate)
                BAUDRATE="$2"
                shift
                shift
                ;;
            --hardware-flow)
                HARDWARE_FLOW="$2"
                shift
                shift
                ;;
            --disable-encryption)
                DISABLE_ENCRYPTION="$2"
                shift
                shift
                ;;
            --disable-conflict-services)
                DISABLE_CONFLICT_SERVICES="$2"
                shift
                shift
                ;;
            --zigbeed-iid)
                ZIGBEED_IID="$2"
                shift
                shift
                ;;
            --otbr-iid)
                OTBR_IID="$2"
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

[ -n "$DEVICE_PATH" ] || DEVICE_PATH="/dev/ttyACM0"
[ -n "$BAUDRATE" ] || BAUDRATE="460800"
[ -n "$HARDWARE_FLOW" ] || HARDWARE_FLOW="true"
[ -n "$DISABLE_ENCRYPTION" ] || DISABLE_ENCRYPTION="true"
[ -n "$DISABLE_CONFLICT_SERVICES" ] || DISABLE_CONFLICT_SERVICES="false"
[ -n "$ZIGBEED_IID" ] || ZIGBEED_IID="1"
[ -n "$OTBR_IID" ] || OTBR_IID="2"

(($ZIGBEED_IID >= 0 && $ZIGBEED_IID <= 3)) || die "zigbeed IID range [0-3]"
(($OTBR_IID >= 0 && $OTBR_IID <= 3)) || die "OTBR IID range [0-3]"
[[ $OTBR_IID == $ZIGBEED_IID ]] && die "zigbeed and OTBR IIDs cannot be the same."

echo "Using parameters:"
echo "--device-path $DEVICE_PATH"
echo "--baudrate $BAUDRATE"
echo "--hardware-flow $HARDWARE_FLOW"
echo "--disable-encryption $DISABLE_ENCRYPTION"
echo "--disable-conflict-services $DISABLE_CONFLICT_SERVICES"
echo "--zigbeed-iid $ZIGBEED_IID"
echo "--otbr-iid $OTBR_IID"
echo "--device-path $DEVICE_PATH --baudrate $BAUDRATE --hardware-flow $HARDWARE_FLOW --disable-encryption $DISABLE_ENCRYPTION --disable-conflict-services $DISABLE_CONFLICT_SERVICES --zigbeed-iid $ZIGBEED_IID --otbr-iid $OTBR_IID" > pre-setup-run.conf

read -p "Proceed (can revert by re-extracting the archive)? (YES/no) " yn

[[ $yn == 'no' || $yn == 'n' || $yn == '0' ]] && echo "Cancelled" && exit

####################
#### SET CONFIG ####
####################

sed -i -e "s+uart_device_file: /dev/ttyACM0+uart_device_file: $DEVICE_PATH+g" ./cpcd/cpcd.conf
sed -i -e "s+uart_device_baud: 115200+uart_device_baud: $BAUDRATE+g" ./cpcd/cpcd.conf
sed -i -e "s+uart_hardflow: true+uart_hardflow: $HARDWARE_FLOW+g" ./cpcd/cpcd.conf
sed -i -e "s+disable_encryption: false+disable_encryption: $DISABLE_ENCRYPTION+g" ./cpcd/cpcd.conf

sed -i -e "s+iid=1+iid=$ZIGBEED_IID+g" ./zigbeed/zigbeed.conf
sed -i -e "s+iid=%I+iid=$OTBR_IID+g" ./systemd/otbr.service

###################
#### FIX PATHS ####
###################

# change all services from syslog to journal
sed -i -e "s+StandardOutput=syslog+StandardOutput=journal+g" ./systemd/*.service
sed -i -e "s+StandardError=syslog+StandardOutput=journal+g" ./systemd/*.service
# creates an endless loop, destroying hard drive space, not needed anyway (use `otbr-agent` for `journalctl`)
sed -i -e "s+StandardOutput=journal+StandardOutput=null+g" ./systemd/otbr.service
sed -i -e "s+StandardError=journal+StandardError=null+g" ./systemd/otbr.service
sed -i -e "s+/app/etc/docker/docker_entrypoint.sh+/usr/local/bin/otbr_entrypoint.sh+g" ./systemd/otbr.service
sed -i -e "s+otbr@.service+otbr.service.sh+g" ./systemd/multiprotocol-master.service
# hijack this one (default is journal anyway) to modify CPCd service to avoid failure due to unavailable tty during boot
sed -i -e "s+StandardOutput=journal+ExecStartPre=/bin/sleep 12+g" ./systemd/cpcd.service

# Only keep RPATH value: /cpc-daemon/build:
sed -i -e "s+/cpc-daemon/build/+./+g" ./cpcd/cmake_install.cmake
sed -i -e "s+/cpc-daemon/./lib+.+g" ./cpcd/cmake_install.cmake
sed -i -e "s+/cpc-daemon/./+./+g" ./cpcd/cmake_install.cmake

sed -i -e "s+/app/script/server+RELEASE=1 REFERENCE_DEVICE=1 BACKBONE_ROUTER=1 BORDER_ROUTING=1 NAT64=1 DNS64=1 WEB_GUI=1 REST_API=1 /app/script/server+g" ./otbr/otbr_entrypoint.sh
# remove end of script
sed -i -e 's+^while+#while+g' ./otbr/otbr_entrypoint.sh
sed -i -e 's+^    sleep 1+#    sleep 1+g' ./otbr/otbr_entrypoint.sh
sed -i -e 's+^done+#done+g' ./otbr/otbr_entrypoint.sh
sed -i -e 's+^tail +#tail +g' ./otbr/otbr_entrypoint.sh
sed -i -e 's+^wait +#wait +g' ./otbr/otbr_entrypoint.sh

sed -i -e "s+examples/platforms/+platforms/+g" ./otbr/script/_initrc

# mDNSResponder patches
sed -i -e "s+../third_party/+../+g" ./otbr/script/bootstrap

# do these two steps manually since script also builds otbr
sed -i -e "s+. script/_otbr+# . script/_otbr+g" ./otbr/script/setup
sed -i -e "s+otbr_uninstall+# otbr_uninstall+g" ./otbr/script/setup
sed -i -e "s+otbr_install+# otbr_install+g" ./otbr/script/setup

# this one can be disruptive, force manual use
[[ $DISABLE_CONFLICT_SERVICES == "false" ]] || sed -i -e "s+. script/_disable_services+# . script/_disable_services+g" ./otbr/script/setup
[[ $DISABLE_CONFLICT_SERVICES == "false" ]] || sed -i -e "s+disable_services+# disable_services+g" ./otbr/script/setup
[[ $DISABLE_CONFLICT_SERVICES == "false" ]] && echo "WARNING: Not disabling conflict services. Check the script in 'script/_disable_services' for possible services conflicts you may need to resolve."

# allow testing on debian
sed -i -e "s+without NAT64 || without DNS64+# without NAT64 || without DNS64+g" ./otbr/script/_dns64
sed -i -e 's+# Currently solution was verified only on raspbian and ubuntu.+RESOLV_CONF_HEAD=/etc/resolvconf/resolv.conf.d/head+g' ./otbr/script/_dns64

sed -i -e "s+/artifacts/simplicity_sdk/util/third_party/ot-br-posix/build/otbr/src/agent/+./+g" ./otbr/cmake_install.cmake
sed -i -e "s+/artifacts/simplicity_sdk/util/third_party/ot-br-posix/build/otbr/third_party/openthread/repo/src/posix/+./+g" ./otbr/cmake_install.cmake

# for ./frontend/cmake_install.cmake
sed -i -e "s+/artifacts/simplicity_sdk/util/third_party/ot-br-posix/build/otbr/src/web/web-service/+./+g" ./otbr/web/cmake_install.cmake
sed -i -e "s+/artifacts/simplicity_sdk/util/third_party/ot-br-posix/build/otbr/src/web/+./+g" ./otbr/web/cmake_install.cmake

# called from ./otbr/web/cmake_install.cmake so keep path "./frontend/xyz"
sed -i -e "s+/artifacts/simplicity_sdk/util/third_party/ot-br-posix/src/web/web-service/+./+g" ./otbr/web/frontend/cmake_install.cmake

# called from ./otbr/web/cmake_install.cmake so keep path "./frontend/third-party/xyz"
sed -i -e "s+/artifacts/simplicity_sdk/util/third_party/ot-br-posix/build/otbr/src/web/web-service/frontend/node_modules/angular-animate/+./frontend/third-party/+g" ./otbr/web/frontend/cmake_install.cmake
sed -i -e "s+/artifacts/simplicity_sdk/util/third_party/ot-br-posix/build/otbr/src/web/web-service/frontend/node_modules/angular-aria/+./frontend/third-party/+g" ./otbr/web/frontend/cmake_install.cmake
sed -i -e "s+/artifacts/simplicity_sdk/util/third_party/ot-br-posix/build/otbr/src/web/web-service/frontend/node_modules/angular-material/+./frontend/third-party/+g" ./otbr/web/frontend/cmake_install.cmake
sed -i -e "s+/artifacts/simplicity_sdk/util/third_party/ot-br-posix/build/otbr/src/web/web-service/frontend/node_modules/angular-messages/+./frontend/third-party/+g" ./otbr/web/frontend/cmake_install.cmake
sed -i -e "s+/artifacts/simplicity_sdk/util/third_party/ot-br-posix/build/otbr/src/web/web-service/frontend/node_modules/angular/+./frontend/third-party/+g" ./otbr/web/frontend/cmake_install.cmake
sed -i -e "s+/artifacts/simplicity_sdk/util/third_party/ot-br-posix/build/otbr/src/web/web-service/frontend/node_modules/d3/+./frontend/third-party/+g" ./otbr/web/frontend/cmake_install.cmake
sed -i -e "s+/artifacts/simplicity_sdk/util/third_party/ot-br-posix/build/otbr/src/web/web-service/frontend/node_modules/material-design-lite/+./frontend/third-party/+g" ./otbr/web/frontend/cmake_install.cmake

sed -i -e "s+/artifacts/simplicity_sdk/util/third_party/openthread/build/posix/src/posix/+./+g" ./ot-cli/cmake_install.cmake
