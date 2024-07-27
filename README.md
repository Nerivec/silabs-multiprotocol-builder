# silabs-multiprotocol-builder

Builder for Silabs multiprotocol (Zigbee, OpenThread, Bluetooth Low Energy) components.

Uses Silicon Labs Simplicity SDK and Silicon Labs Configurator (slc) to build binaries and configurations files for supported architectures (arm32, arm64, x86_64).

> [!WARNING] 
> Work in progress!

The following steps have been tested on Debian bookworm x64.

> [!IMPORTANT]
> Requires an RCP firmware version 2024.6.1.
> `rcp-uart-802154-blehci` => with BLE support.
> `rcp-uart-802154` => without BLE support.

## Install prerequisites

```bash
sudo apt-get install -y tar make cmake socat
tar xf silabs-multiprotocol-components-ARCH.tar.xz
```

> [!IMPORTANT]
> Replace `ARCH` with the arch of the downloaded archive.

## Install CPCd

```bash
cd cpcd
sudo cmake -P cmake_install.cmake
sudo ln -sf /usr/local/lib/libcpc.so.4.5.1.0 /usr/local/lib/libcpc.so.3
sudo ln -sf /usr/local/lib/libcpc.so.3 /usr/local/lib/libcpc.so
sudo ldconfig
```

## Install zigbeed

```bash
cd zigbeed
sudo cp zigbeed /usr/local/bin/
sudo cp zigbeed.conf /usr/local/etc/
```

> [!TIP]
> To connect to zigbeed from your ZigBee application, use the path configured in `/etc/systemd/system/zigbeed-socat.service`. Default is: `/dev/ttyZigbeeNCP`.

## Install OTBR

NOT YET SUPPORTED

```bash
```

## Install BLE

NOT YET SUPPORTED

```bash
```

## Install systemd services

```bash
cd systemd
sudo cp *.service /etc/systemd/system/
sudo systemctl enable zigbeed-socat.service
sudo systemctl enable cpcd.service
sudo systemctl enable zigbeed.service
```

## Configure components

### CPCd

Location: `/usr/local/etc/cpcd.conf`

Set `uart_device_file`, `uart_device_baud`, and `uart_hardflow` according to your adapter/firmware.

> [!IMPORTANT]
> Replace `YOUR_PATH_HERE` with the path to your adapter. _Skip this command if the path of your adapter is `/dev/ttyACM0`._

```bash
sed -i -e "s+uart_device_file: /dev/ttyACM0+uart_device_file: YOUR_PATH_HERE+g" /usr/local/etc/cpcd.conf
```

> [!IMPORTANT]
> Replace `YOUR_BAUDRATE_HERE` with the baudrate of your firmware. _Skip this command if the baudrate of your firmware is `460800`._

```bash
sed -i -e "s+uart_device_baud: 460800+uart_device_baud: YOUR_BAUDRATE_HERE+g" /usr/local/etc/cpcd.conf
```

> [!NOTE]
Setting `disable_encryption` to false requires a firmware built with encryption enabled too.

#### Firmware with hardware flow control (hw, rtscts=true):

Nothing else.

#### Firmware with software flow control (sw, rtscts=false):

```bash
sed -i -e "s+uart_hardflow: true+uart_hardflow: false+g" /usr/local/etc/cpcd.conf
```

### zigbeed

Location: `/usr/local/etc/zigbeed.conf`

Should work out-of-the-box (adjust `ezsp-interface` if you modify the `socat` parameters).

## Start systemd services

```bash
sudo systemctl start cpcd
sudo systemctl start zigbeed-socat
sudo systemctl start zigbeed
```
